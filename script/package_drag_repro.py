#!/usr/bin/env python3
"""Package the pinned C12 arm64 app for physical drag diagnosis, without publishing."""
from __future__ import annotations

import argparse
import json
from pathlib import Path, PurePosixPath
import platform
import plistlib
import re
import shutil
import stat
import subprocess
import tempfile
import zipfile

from package_ui_review import run, sha256

ROOT = Path(__file__).resolve().parent.parent
COMMIT = "d821d7343675e2850705d141ef9b3b93a6aee945"
TREE = "425baa28f00ec24551dd70c0cc874a75fa3be0c1"
FOLDER = "Lemulip-PR45-C12-arm64"
ARCHIVE = FOLDER + ".zip"
APP = "Lemulip Native UI Review.app"
BUNDLE_ID = "app.lemulip.NativeUIReview"
FIXTURES = Path("Fixtures/FinderDrop/orchard")
LIMITS = {"diagnosticOnly": True, "releaseReady": False,
          "acceptanceXCTestExecuted": False, "physicalEscape": "UNVERIFIED", "C12": "HOLD"}

LAUNCHER = r'''#!/bin/bash
set -euo pipefail
repro_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
shopt -s nullglob
repro_existing=("$repro_root/Fixtures/FinderDrop/orchard"/Existing-*.txt)
repro_single=("$repro_root/Fixtures/FinderDrop/orchard"/Single-*.txt)
if (( ${#repro_existing[@]} != 1 || ${#repro_single[@]} != 1 )); then
    printf '%s\n' 'Örnek dosyalar eksik. ZIP paketini yeni bir klasöre açın.' >&2
    exit 1
fi
/usr/bin/open -n -a "$repro_root/Lemulip Native UI Review.app" "${repro_existing[0]}" --args \
    -language en -theme orchard -wheelEnabled NO -completionPresentation quiet \
    -NSQuitAlwaysKeepsWindows NO
/usr/bin/open "$repro_root/Fixtures/FinderDrop/orchard"
printf '%s\n' 'C12 tanı kopyası ve Finder için açılış isteği iletildi. Adımlar: OKU-BENI.txt.'
'''

README = """Lemulip PR #45 / C12 — fiziksel Escape kontrolü (Apple Silicon / arm64)

ZIP'i açın ve Kontrolu-Baslat.command dosyasına çift tıklayın.
Swift, Python, Git veya Xcode kurulumu gerekmez. Uygulama ayrı bir tanı kimliği
kullanır; bu paket bir sürüm yayını değildir ve ad hoc imzalıdır.

Bu tanı paketi Apple notarization taşımıyor. Yalnız “geliştirici doğrulanamıyor”
veya “Apple kontrol edemiyor” engelinde, Lemulip Native UI Review uygulamasını
açmayı denedikten sonra Sistem Ayarları > Gizlilik ve Güvenlik > Yine de Aç
(System Settings > Privacy & Security > Open Anyway) kullanılabilir.
Bu öneri “bozuk” veya “zararlı yazılım” uyarıları için geçerli değildir.
Apple açıklaması: https://support.apple.com/en-gb/102445

1. Lemulip listesinde yalnız Existing dosyası ve “1 Selected” görünmesini bekleyin.
2. Finder'daki Single dosyasını Lemulip dosya alanına sürükleyin; fareyi bırakmayın.
3. Alanın dışına çıkıp tekrar içine girin; fareyi basılı tutarak birkaç saniye bekleyin.
4. Fiziksel Escape tuşuna basın. Ardından fareyi dosya alanının içinde bırakın.
5. Yalnız Existing / 1 Selected mı kaldı, yoksa Single da eklendi mi? Sonucu kaydedin.
6. Single eklendiyse uygulamadaki listeden kaldırın. Sonra Single dosyasını
   Escape kullanmadan yeniden sürükleyip bırakın: Existing + Single / 2 Selected beklenir.

Escape sonrası dosya sayısını ve normal bırakmanın sonucunu paylaşın.
Yeniden denemeden önce bu tanı uygulamasını kapatın. Örnek dosyaları değiştirmeyin.

Kaynak: d821d7343675e2850705d141ef9b3b93a6aee945 (C12).
Fiziksel Escape sonucu henüz doğrulanmadı; C12 HOLD devam ediyor.
Bu paket için kabul XCTest paketi çalıştırılmaz. ZIP'in yanındaki verification.json
yalnız paket bütünlüğü ve üç saniyelik yerel açılış kontrolünün sonucunu gösterir.
"""


def checked_source(source: Path) -> dict:
    identity = {"commit": run("git", "-C", source, "rev-parse", "HEAD"),
                "tree": run("git", "-C", source, "rev-parse", "HEAD^{tree}")}
    if identity != {"commit": COMMIT, "tree": TREE} or run(
            "git", "-C", source, "status", "--porcelain", "--untracked-files=normal"):
        raise ValueError("Requires the exact clean C12 source checkout")
    return {**identity, "worktreeClean": True}


def inventory(directory: Path) -> dict:
    result = {}
    for path in [directory, *sorted(directory.rglob("*"))]:
        mode = path.lstat().st_mode
        if not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
            raise ValueError("Payload must contain only regular files and directories")
        entry = {"mode": format(stat.S_IMODE(mode), "04o"),
                 "type": "directory" if stat.S_ISDIR(mode) else "file"}
        if stat.S_ISREG(mode):
            entry["sha256"] = sha256(path)
        result[path.relative_to(directory).as_posix()] = entry
    return result


def verify_bundle(app: Path) -> dict:
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    expected = {"CFBundleIdentifier": BUNDLE_ID, "CFBundleExecutable": "Lemulip",
                "CFBundleName": "Lemulip Native UI Review",
                "CFBundleDisplayName": "Lemulip Native UI Review"}
    if any(info.get(key) != value for key, value in expected.items()):
        raise ValueError("Unexpected diagnostic app identity")
    binary = app / "Contents/MacOS/Lemulip"
    if run("/usr/bin/lipo", "-archs", binary).split() != ["arm64"]:
        raise ValueError("Diagnostic app must contain exactly arm64")
    run("/usr/bin/codesign", "--verify", "--all-architectures", "--strict", app)
    details = subprocess.run(["/usr/bin/codesign", "--display", "--verbose=2", str(app)],
                             check=True, capture_output=True, text=True, timeout=30).stderr.splitlines()
    if "Signature=adhoc" not in details or "Identifier=" + BUNDLE_ID not in details:
        raise ValueError("Expected the isolated app's existing ad hoc signature")
    return {"bundleIdentifier": BUNDLE_ID, "architecture": "arm64", "signature": "ad hoc verified",
            "GUI_SHA256": sha256(binary), "version": info.get("CFBundleShortVersionString"),
            "build": info.get("CFBundleVersion")}


def write_json(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def stage(source: Path, staged: Path, output: Path, workflow_commit: str) -> None:
    identity = checked_source(source)
    if not re.fullmatch(r"[0-9a-f]{40}", workflow_commit) or workflow_commit != run(
            "git", "-C", ROOT, "rev-parse", "HEAD"):
        raise ValueError("Workflow commit does not match the packaging checkout")
    app = staged / APP
    before = inventory(app)
    bundle = verify_bundle(app)
    original = json.loads((staged / "provenance.json").read_text())
    expected = {"sourceCommit": COMMIT, "sourceTree": TREE, "architecture": "arm64",
                "bundleIdentifier": BUNDLE_ID, "originalBundleUnchanged": True,
                "testStatus": "NOT RUN", "releaseReady": False,
                "stagedGUI_SHA256": bundle["GUI_SHA256"],
                "originalGUI_SHA256": sha256(source / "dist/Lemulip.app/Contents/MacOS/Lemulip"),
                "testSourceSHA256": sha256(source / "script/native_ui/QualityUITests.swift")}
    if any(original.get(key) != value for key, value in expected.items()):
        raise ValueError("Native staging provenance does not match C12 and its binaries")
    fixtures = []
    for role in ("Existing", "Single"):
        matches = list((staged / FIXTURES).glob(role + "-*.txt"))
        if len(matches) != 1 or matches[0].is_symlink() or not re.fullmatch(
                role + r"-[0-9a-f]{32}\.txt", matches[0].name) or matches[0].read_bytes() != (
                f"Synthetic Finder input: orchard, {role}. Preserve these bytes.\n".encode()):
            raise ValueError("Expected one unchanged synthetic orchard fixture per role")
        fixtures.append(matches[0])
    output.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix="lemulip-drag-stage-") as temporary:
        payload = Path(temporary) / FOLDER
        payload.mkdir()
        shutil.copytree(app, payload / APP)
        (payload / FIXTURES).mkdir(parents=True)
        for fixture in fixtures:
            shutil.copy2(fixture, payload / FIXTURES / fixture.name)
        (payload / "Kontrolu-Baslat.command").write_text(LAUNCHER, encoding="utf-8")
        (payload / "Kontrolu-Baslat.command").chmod(0o755)
        (payload / "OKU-BENI.txt").write_text(README, encoding="utf-8")
        provenance = {"schema": 1, **LIMITS, "source": identity, "workflowCommit": workflow_commit,
                      "bundle": bundle, "theme": "orchard", "fixtures": [p.name for p in fixtures],
                      "originalGUI_SHA256": expected["originalGUI_SHA256"],
                      "nativeStageProvenanceSHA256": sha256(staged / "provenance.json"),
                      "packagerSHA256": sha256(Path(__file__)),
                      "verificationScope": "package integrity and 3-second native launch only"}
        write_json(payload / "provenance.json", provenance)
        write_json(payload / "inventory.json", inventory(payload))
        if inventory(payload / APP) != before or inventory(app) != before:
            raise ValueError("The staged app changed during packaging")
        checked_source(source)
        run("/usr/bin/ditto", "-c", "-k", "--norsrc", "--noextattr", "--keepParent",
            payload, output / ARCHIVE)
    (output / "SHA256SUMS.txt").write_text(f"{sha256(output / ARCHIVE)}  {ARCHIVE}\n")
    write_json(output / "provenance.json", provenance)
    write_json(output / "verification.json", {**LIMITS, "status": "NOT RUN",
               "scope": provenance["verificationScope"], "source": identity,
               "workflowCommit": workflow_commit, "archiveSHA256": sha256(output / ARCHIVE)})
    print("C12 diagnostic ZIP staged; native verification has not run.")


def checked_archive(output: Path) -> str:
    digest = sha256(output / ARCHIVE)
    if (output / "SHA256SUMS.txt").read_text() != f"{digest}  {ARCHIVE}\n":
        raise ValueError("Diagnostic ZIP checksum mismatch")
    with zipfile.ZipFile(output / ARCHIVE) as zipped:
        names = set()
        for entry in zipped.infolist():
            path = PurePosixPath(entry.filename)
            if (path.is_absolute() or not path.parts or path.parts[0] != FOLDER
                    or ".." in path.parts or "\\" in entry.filename
                    or any(ord(c) < 32 for c in entry.filename) or path.as_posix() in names
                    or stat.S_ISLNK(entry.external_attr >> 16)):
                raise ValueError("Unexpected diagnostic ZIP entry")
            names.add(path.as_posix())
        if not names or zipped.testzip() is not None:
            raise ValueError("Diagnostic ZIP is empty or has a CRC failure")
    return digest


def verify_contents(payload: Path) -> dict:
    actual = inventory(payload)
    actual.pop("inventory.json")
    if actual != json.loads((payload / "inventory.json").read_text()):
        raise ValueError("Extracted payload hashes or modes differ from the staged inventory")
    provenance = json.loads((payload / "provenance.json").read_text())
    if any(provenance.get(key) != value for key, value in LIMITS.items()):
        raise ValueError("Diagnostic-only provenance is missing")
    return provenance


def verify(source: Path, output: Path) -> None:
    report = {**LIMITS, "status": "FAIL", "scope": "package integrity and 3-second native launch only"}
    try:
        report["source"] = checked_source(source)
        report["archiveSHA256"] = checked_archive(output)
        with tempfile.TemporaryDirectory(prefix="lemulip-drag-verify-") as temporary:
            run("/usr/bin/ditto", "-x", "-k", output / ARCHIVE, temporary)
            payload = Path(temporary) / FOLDER
            provenance = verify_contents(payload)
            report["workflowCommit"] = run("git", "-C", ROOT, "rev-parse", "HEAD")
            if (provenance != json.loads((output / "provenance.json").read_text())
                    or provenance["source"] != report["source"]
                    or provenance["workflowCommit"] != report["workflowCommit"]
                    or provenance["bundle"] != verify_bundle(payload / APP)):
                raise ValueError("Extracted app provenance differs from this verification")
            run("/bin/bash", source / "script/build_and_run.sh", "--verify-bundle", payload / APP)
            verify_contents(payload)
            report.update(inventoryHashesAndModes="PASS", signatureIdentityAndArm64="PASS",
                          nativeLaunch={"status": "PASS", "seconds": 3,
                                        "scriptSHA256": sha256(source / "script/build_and_run.sh")})
        checked_source(source)
        if sha256(output / ARCHIVE) != report["archiveSHA256"]:
            raise ValueError("Diagnostic ZIP changed during verification")
        report["status"] = "PASS"
    except Exception as error:
        report["errorType"] = type(error).__name__  # Never distribute runner paths or raw logs.
        raise
    finally:
        write_json(output / "verification.json", report)
    print("PASS: package integrity and 3-second native launch only. Physical Escape remains UNVERIFIED; C12 HOLD.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["stage", "verify"])
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--staged", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--workflow-commit")
    args = parser.parse_args()
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        parser.error("Packaging and verification require a native arm64 Mac")
    if args.operation == "stage":
        if args.staged is None or args.workflow_commit is None:
            parser.error("stage requires --staged and --workflow-commit")
        stage(args.source.resolve(), args.staged.resolve(), args.output.resolve(), args.workflow_commit)
    else:
        verify(args.source.resolve(), args.output.resolve())


if __name__ == "__main__":
    main()
