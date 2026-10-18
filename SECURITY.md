# Security and Privacy

Lemulip processes user-selected local files. It does not include an upload API,
analytics, crash-reporting service, automatic update check, cloud account, or API
key requirement. Activity is not persisted. Preferences contain UI settings only.

Optional converter processes receive explicit argument arrays and a minimal
environment. On macOS their network access is denied through the local process
sandbox; unavailable sandbox enforcement fails closed. LibreOffice uses a
dedicated profile with macros and active content disabled. ImageMagick has an
isolated policy with delegate and resource restrictions. FFmpeg uses explicit
local demuxer/protocol restrictions. These reduce risk; they are not a guarantee
against vulnerabilities in macOS or independently installed codecs.

Archive extraction uses libarchive through a small C bridge. Every output path
component is opened relative to a private directory with O_NOFOLLOW. Absolute
paths, traversal, links, devices, duplicate files, excessive depth, excessive
entry counts, and oversized expanded contents are rejected. Conversion outputs
are staged privately and published under unused names. Conversion preserves
originals; the explicit Move action changes their location.

The application reads the drag pasteboard only when it detects a new file drag.
It does not monitor ordinary clipboard contents or record keystrokes. AirDrop
uses the system sharing service only when selected by the user.

## Public Source Hygiene

Run `python3 script/privacy_check.py` and review the diff before publishing.
The check never prints matching secret values. The source allowlist excludes
environment files, keys, build products, private directories, and personal home
paths. Do not attach real customer documents, credentials, private account data,
or crash logs containing personal file paths to public issues.

Public PNG assets are limited to named, visually reviewed illustrations with
pinned content digests. Text, EXIF, and arbitrary metadata chunks are rejected;
the generated cover retains its reviewed C2PA origin provenance. This automated
check is a guardrail, not a complete secret detector;
review the exact source and images before each publication.

## Reporting a Problem

If a repository maintainer has enabled GitHub private vulnerability reporting,
use Security → Report a vulnerability. Otherwise open an issue describing the
affected component without exploit attachments or private files, and ask the
maintainer to establish an appropriate reporting channel. No private contact
address is embedded in this project.
