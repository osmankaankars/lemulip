#!/usr/bin/env python3
"""Read-only, bounded Mach-O identity for the installed D24 sampler.

The retained copy is data only.  The experiment invokes /usr/bin/sample and
compares its bytes before and after the observation.  CPU family is distinct
from CPU subtype: arm64e is a native arm64-family image, not a translated one.
"""

from __future__ import annotations

import hashlib
import struct
import uuid


MAX_TOOL_BYTES = 64 * 1024 * 1024
MAX_SLICES = 32
MAX_COMMANDS = 4096
CPU_FAMILIES = {0x0100000C: "arm64", 0x01000007: "x86_64"}


class IdentityError(ValueError):
    """The file does not support a bounded native executable identity."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise IdentityError(message)


def _slice(raw: bytes, offset: int, size: int, table_cpu=None) -> dict:
    require(0 <= offset <= len(raw) and 32 <= size <= len(raw) - offset,
            "Mach-O slice is outside the file")
    part = raw[offset:offset + size]
    endian = {b"\xcf\xfa\xed\xfe": "<", b"\xfe\xed\xfa\xcf": ">"}.get(part[:4])
    require(endian is not None, "Expected a 64-bit Mach-O slice")
    _, cpu, subtype, filetype, count, command_bytes, _, _ = struct.unpack_from(endian + "8I", part)
    require(filetype == 2, "Mach-O is not an executable")
    require(cpu in CPU_FAMILIES, "Unsupported native CPU family")
    require(table_cpu is None or table_cpu == (cpu, subtype),
            "FAT table and Mach-O CPU identities differ")
    require(0 < count <= MAX_COMMANDS and 0 < command_bytes <= size - 32,
            "Mach-O load-command bounds are invalid")
    command_end, position, uuids = 32 + command_bytes, 32, []
    for _ in range(count):
        require(position + 8 <= command_end, "Truncated Mach-O load command")
        kind, length = struct.unpack_from(endian + "2I", part, position)
        require(length >= 8 and length % 8 == 0 and length <= command_end - position,
                "Invalid Mach-O load-command size")
        if kind == 0x1B:
            require(length == 24, "Invalid LC_UUID size")
            uuids.append(str(uuid.UUID(bytes=part[position + 8:position + 24])).upper())
        position += length
    require(position == command_end and len(uuids) == 1 and uuids[0] != str(uuid.UUID(int=0)).upper(),
            "Mach-O requires exactly one nonzero UUID and complete commands")
    return {"uuid": uuids[0], "architecture": CPU_FAMILIES[cpu],
            "cpuType": cpu, "cpuSubtype": subtype, "offset": offset,
            "bytes": size, "sha256": hashlib.sha256(part).hexdigest()}


def inspect_tool(raw: bytes, architecture: str) -> dict:
    """Return byte identity and all native-family slice UUIDs; execute nothing."""
    require(type(raw) is bytes and 32 <= len(raw) <= MAX_TOOL_BYTES,
            "Tool is not a bounded nonempty executable")
    require(architecture in ("arm64", "x86_64"), "Unsupported host architecture")
    fat = {b"\xca\xfe\xba\xbe": (">", False), b"\xbe\xba\xfe\xca": ("<", False),
           b"\xca\xfe\xba\xbf": (">", True), b"\xbf\xba\xfe\xca": ("<", True)}.get(raw[:4])
    if fat is None:
        slices = [_slice(raw, 0, len(raw))]
        container = "thin"
    else:
        endian, wide = fat
        count = struct.unpack_from(endian + "I", raw, 4)[0]
        width = 32 if wide else 20
        table_end = 8 + count * width
        require(0 < count <= MAX_SLICES and table_end <= len(raw), "Invalid FAT table bounds")
        entries, occupied, cpu_pairs = [], [], set()
        for index in range(count):
            position = 8 + index * width
            if wide:
                cpu, subtype, offset, size, align, reserved = struct.unpack_from(endian + "IIQQII", raw, position)
                require(reserved == 0, "FAT64 reserved field is nonzero")
            else:
                cpu, subtype, offset, size, align = struct.unpack_from(endian + "5I", raw, position)
            require(align <= 31 and offset >= table_end and offset <= len(raw)
                    and 32 <= size <= len(raw) - offset and offset % (1 << align) == 0,
                    "Invalid FAT slice alignment or bounds")
            require((cpu, subtype) not in cpu_pairs, "Duplicate FAT CPU/subtype entry")
            require(all(offset + size <= start or offset >= end for start, end in occupied),
                    "Overlapping FAT slices")
            cpu_pairs.add((cpu, subtype))
            occupied.append((offset, offset + size))
            entries.append((offset, size, (cpu, subtype)))
        slices = [_slice(raw, offset, size, cpu) for offset, size, cpu in entries]
        container = "fat64" if wide else "fat"
    require(len({part["uuid"] for part in slices}) == len(slices), "Duplicate Mach-O slice UUID")
    native = [part for part in slices if part["architecture"] == architecture]
    require(bool(native), "Tool contains no native-family image for this host")
    return {"bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest(),
            "architecture": architecture, "container": container,
            "nativeUUIDs": sorted(part["uuid"] for part in native),
            "nativeSlices": native, "slices": slices}
