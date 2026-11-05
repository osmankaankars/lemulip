#!/usr/bin/env python3
"""Build and verify an isolated, compiled same-host drag diagnostic kit."""
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
APPLICATION_COMMIT = "d821d7343675e2850705d141ef9b3b93a6aee945"
APPLICATION_TREE = "425baa28f00ec24551dd70c0cc874a75fa3be0c1"
OBSERVER_BASE = "c91b08e1f6f5293281e2b54423c53221a289ad90"
FOLDER = "Lemulip-PR45-Girdi-Karsilastirma-arm64"
ARCHIVE = FOLDER + ".zip"
HELPER = "Lemulip Input Check.app"
HELPER_ID = "app.lemulip.SameHostDragReview"
EXECUTABLE = "LemulipInputCheck"
APPLICATION = "Lemulip Native UI Review.app"
APPLICATION_ID = "app.lemulip.NativeUIReview"
PAYLOAD = Path("Contents/Resources/Payload/lemulip-native-ui")
FIXTURES = Path("Fixtures/FinderDrop/orchard")
LIMITS = {"diagnosticOnly": True, "releaseReady": False,
          "acceptanceXCTestExecuted": False, "comparisonExecution": "NOT RUN", "C12": "HOLD"}
ESCAPE_FAILURE = "Escape did not cancel the actual Finder drag"

README = """Lemulip PR #45 — aynı Mac'te girdi karşılaştırması (Apple Silicon / arm64)

ZIP'i açın ve Lemulip Input Check uygulamasına çift tıklayın. Swift, Python,
Git, Command Line Tools veya Xcode kurulumu gerekmez. Bu ayrı bir tanı kopyasıdır.
Uygulama C12 kaynağını ve yalnız sentetik Orchard dosyalarını kullanır.

Yardımcı, bu sentetik dosyaları Finder'dan sürüklemek için Erişilebilirlik
iznine ihtiyaç duyar. Önkontrol izin eksik derse Sistem Ayarları > Gizlilik ve
Güvenlik > Erişilebilirlik altında yalnız Lemulip Input Check uygulamasını
ekleyip etkinleştirin, ardından uygulamayı kapatıp yeniden açın. Terminal'e
izin vermek gerekmez. Kit izinleri veya sistem ayarlarını kendisi değiştirmez.
Ekran görüntüsü almaz ve Ekran Kaydı izni istemez.

Uygulamadaki adımları izleyin. Önce aynı bilgisayarda otomatik sürükleme ve
otomatik Escape ölçülür. Fiziksel Escape aşamasında yönergeyi bekleyin;
fareye dokunmadan yalnız Escape kullanın: “Basılı tut” yönergesinde basılı tutun,
“Bırak” yönergesinde bırakın. Erken bırakma denemeyi engeller. Diğer tuşlara basmayın.
Hazır anından önce başka pencereye geçmeyin. Sonuç raporunu uygulamadan alın.
Başlangıçta Existing / 1 Selected doğrulanamazsa sonuç kabul edilmez.
Başarılı fiziksel denemeden sonra ölçülen zamanlamayla otomatik tekrar yapılır;
bu tekrar sırasında ek bir tuşa basmanız gerekmez.

Paket ad hoc imzalıdır; Apple notarization taşımaz. Yalnız “geliştirici
doğrulanamıyor” veya “Apple kontrol edemiyor” engelinde, açmayı denedikten
sonra Sistem Ayarları > Gizlilik ve Güvenlik > Yine de Aç kullanılabilir.
Bu öneri “bozuk” veya “zararlı yazılım” uyarıları için geçerli değildir.
Apple açıklaması: https://support.apple.com/en-gb/102445

Bu paket bir sürüm yayını değildir. Kabul XCTest paketi çalıştırılmaz ve
PR #45/C12 genel HOLD durumu korunur. CI paket/açılış veya tanı çalıştırma
kontrolünün PASS olması Escape iptalinin veya fiziksel girdinin PASS olduğu
anlamına gelmez. Kullanıcının Mac'inde sonuç, gerçek deneme raporuyla belirlenir.
"""


def write_json(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def checked_source(source: Path) -> dict:
    identity = {"commit": run("git", "-C", source, "rev-parse", "HEAD"),
                "tree": run("git", "-C", source, "rev-parse", "HEAD^{tree}")}
    if identity != {"commit": APPLICATION_COMMIT, "tree": APPLICATION_TREE} or run(
            "git", "-C", source, "status", "--porcelain", "--untracked-files=normal"):
        raise ValueError("Requires the exact clean C12 application source")
    return {**identity, "worktreeClean": True}


def helper_source(expected: str) -> dict:
    if not re.fullmatch(r"[0-9a-f]{40}", expected) or expected != run("git", "-C", ROOT, "rev-parse", "HEAD"):
        raise ValueError("Helper source does not match the workflow commit")
    run("git", "-C", ROOT, "diff", "--exit-code", "HEAD", "--")
    run("git", "-C", ROOT, "merge-base", "--is-ancestor", OBSERVER_BASE, "HEAD")
    return {"helperCommit": expected, "helperTree": run("git", "-C", ROOT, "rev-parse", "HEAD^{tree}"),
            "observerBaseCommit": OBSERVER_BASE,
            "observerSourceSHA256": sha256(ROOT / "script/native_ui/NativeDragReview.swift"),
            "helperSourceSHA256": sha256(ROOT / "script/native_ui/NativeDragSameHost.swift")}


def inventory(directory: Path) -> dict:
    result = {}
    for path in [directory, *sorted(directory.rglob("*"))]:
        mode = path.lstat().st_mode
        if not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
            raise ValueError("Only regular files and directories are allowed")
        entry = {"mode": format(stat.S_IMODE(mode), "04o"),
                 "type": "directory" if stat.S_ISDIR(mode) else "file"}
        if stat.S_ISREG(mode):
            entry["sha256"] = sha256(path)
        result[path.relative_to(directory).as_posix()] = entry
    return result


def payload_hashes(payload: Path) -> dict:
    return {name: value["sha256"] for name, value in inventory(payload).items()
            if value["type"] == "file" and name != "kit-manifest.json"}


def verify_bundle(app: Path, identifier: str, executable: str) -> dict:
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    expected = {"CFBundleIdentifier": identifier, "CFBundleExecutable": executable,
                "CFBundleName": app.stem, "CFBundleDisplayName": app.stem}
    if any(info.get(k) != v for k, v in expected.items()):
        raise ValueError("Unexpected diagnostic bundle identity")
    binary = app / "Contents/MacOS" / executable
    if run("/usr/bin/lipo", "-archs", binary).split() != ["arm64"]:
        raise ValueError("Expected exactly the arm64 architecture")
    minimum = re.findall(r"^\s*minos\s+(\S+)", run("/usr/bin/otool", "-l", binary), re.MULTILINE)
    plist_minimum = info.get("LSMinimumSystemVersion", "")
    for value in [*minimum, plist_minimum]:
        if not re.fullmatch(r"\d+(?:\.\d+){1,2}", value) or tuple(map(int, value.split("."))) > (15, 6, 1):
            raise ValueError("Deployment metadata is incompatible with macOS 15.6.1")
    if len(minimum) != 1:
        raise ValueError("Missing unambiguous Mach-O minimum OS metadata")
    run("/usr/bin/codesign", "--verify", "--deep", "--all-architectures", "--strict", app)
    details = subprocess.run(["/usr/bin/codesign", "--display", "--verbose=2", str(app)],
                             check=True, capture_output=True, text=True, timeout=30).stderr.splitlines()
    if "Signature=adhoc" not in details or "Identifier=" + identifier not in details:
        raise ValueError("Expected the isolated bundle's ad hoc signature")
    return {"bundleIdentifier": identifier, "executableSHA256": sha256(binary),
            "architecture": "arm64", "signature": "ad hoc verified",
            "minimumOS": minimum[0], "LSMinimumSystemVersion": plist_minimum}


def verify_payload(payload: Path) -> dict:
    manifest = read_json(payload / "kit-manifest.json")
    expected = {"schema": 1, "applicationCommit": APPLICATION_COMMIT,
                "applicationTree": APPLICATION_TREE, "observerBaseCommit": OBSERVER_BASE,
                "diagnosticOnly": True, "releaseReady": False}
    if any(manifest.get(k) != v for k, v in expected.items()):
        raise ValueError("Incorrect application pins or diagnostic scope")
    for field, length in (("helperCommit", 40), ("observerSourceSHA256", 64),
                          ("helperSourceSHA256", 64), ("stagedGUI_SHA256", 64)):
        if not re.fullmatch(r"[0-9a-f]{" + str(length) + "}", manifest.get(field, "")):
            raise ValueError("Missing source or executable identity")
    if manifest.get("files") != payload_hashes(payload):
        raise ValueError("Payload file hashes or membership changed")
    if sha256(payload / APPLICATION / "Contents/MacOS/Lemulip") != manifest["stagedGUI_SHA256"]:
        raise ValueError("C12 executable does not match the payload manifest")
    provenance = read_json(payload / "provenance.json")
    if any(provenance.get(k) != v for k, v in {
            "sourceCommit": APPLICATION_COMMIT, "sourceTree": APPLICATION_TREE,
            "stagedGUI_SHA256": manifest["stagedGUI_SHA256"], "architecture": "arm64",
            "bundleIdentifier": APPLICATION_ID, "originalBundleUnchanged": True,
            "testStatus": "NOT RUN", "releaseReady": False}.items()):
        raise ValueError("C12 staging provenance changed")
    return manifest


def stage(source: Path, staged: Path, observer_binary: Path, output: Path, workflow_commit: str) -> None:
    application_source = checked_source(source)
    sources = helper_source(workflow_commit)
    app = staged / APPLICATION
    before = inventory(app)
    application = verify_bundle(app, APPLICATION_ID, "Lemulip")
    original = read_json(staged / "provenance.json")
    if original.get("originalGUI_SHA256") != sha256(source / "dist/Lemulip.app/Contents/MacOS/Lemulip"):
        raise ValueError("Staging provenance does not identify the original C12 binary")
    output.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix="lemulip-same-host-stage-") as temporary:
        folder = Path(temporary) / FOLDER
        helper = folder / HELPER
        payload = helper / PAYLOAD
        payload.mkdir(parents=True)
        shutil.copytree(app, payload / APPLICATION)
        shutil.copy2(staged / "provenance.json", payload / "provenance.json")
        (payload / FIXTURES).mkdir(parents=True)
        for role in ("Existing", "Single", "Multi-A", "Multi-B"):
            matches = list((staged / FIXTURES).glob(role + "-*.txt"))
            if len(matches) != 1 or matches[0].is_symlink() or not re.fullmatch(
                    re.escape(role) + r"-[0-9a-f]{32}\.txt", matches[0].name) or matches[0].read_bytes() != (
                    f"Synthetic Finder input: orchard, {role}. Preserve these bytes.\n".encode()):
                raise ValueError("Expected the four unchanged synthetic Orchard fixtures")
            shutil.copy2(matches[0], payload / FIXTURES / matches[0].name)
        manifest = {"schema": 1, "applicationCommit": APPLICATION_COMMIT, "applicationTree": APPLICATION_TREE,
                    **sources, "stagedGUI_SHA256": application["executableSHA256"],
                    "diagnosticOnly": True, "releaseReady": False, "files": payload_hashes(payload)}
        write_json(payload / "kit-manifest.json", manifest)
        verify_payload(payload)
        macos = helper / "Contents/MacOS"
        macos.mkdir()
        shutil.copy2(observer_binary, macos / EXECUTABLE)
        (macos / EXECUTABLE).chmod(0o755)
        info = {"CFBundleIdentifier": HELPER_ID, "CFBundleExecutable": EXECUTABLE,
                "CFBundleName": helper.stem, "CFBundleDisplayName": helper.stem,
                "CFBundlePackageType": "APPL", "CFBundleVersion": "1",
                "CFBundleShortVersionString": "0.0.0", "LSMinimumSystemVersion": "13.0",
                "NSHighResolutionCapable": True, "NSPrincipalClass": "NSApplication"}
        (helper / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
        run("/usr/bin/codesign", "--force", "--sign", "-", "--identifier", HELPER_ID, helper)
        helper_identity = verify_bundle(helper, HELPER_ID, EXECUTABLE)
        if inventory(payload / APPLICATION) != before or inventory(app) != before:
            raise ValueError("The staged C12 application changed during packaging")
        provenance = {"schema": 1, **LIMITS, "applicationSource": application_source, **sources,
                      "application": application, "helper": helper_identity,
                      "packagerSHA256": sha256(Path(__file__)), "kitManifestSHA256": sha256(payload / "kit-manifest.json"),
                      "scope": "package integrity, C12 launch and input-free helper startup; no cancellation acceptance"}
        (folder / "OKU-BENI.txt").write_text(README, encoding="utf-8")
        write_json(folder / "provenance.json", provenance)
        write_json(folder / "inventory.json", inventory(folder))
        checked_source(source)
        with zipfile.ZipFile(output / ARCHIVE, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zipped:
            for path in [folder, *sorted(folder.rglob("*"))]:
                zipped.write(path, path.relative_to(folder.parent).as_posix())
    (output / "SHA256SUMS.txt").write_text(f"{sha256(output / ARCHIVE)}  {ARCHIVE}\n")
    write_json(output / "provenance.json", provenance)
    write_json(output / "verification.json", {**LIMITS, "status": "NOT RUN", "scope": provenance["scope"]})


def checked_archive(output: Path) -> str:
    digest = sha256(output / ARCHIVE)
    if (output / "SHA256SUMS.txt").read_text() != f"{digest}  {ARCHIVE}\n":
        raise ValueError("Diagnostic ZIP checksum mismatch")
    with zipfile.ZipFile(output / ARCHIVE) as zipped:
        names = set()
        for entry in zipped.infolist():
            path = PurePosixPath(entry.filename)
            if (path.is_absolute() or not path.parts or path.parts[0] != FOLDER or ".." in path.parts
                    or "\\" in entry.filename or any(ord(c) < 32 for c in entry.filename)
                    or path.as_posix() in names or stat.S_ISLNK(entry.external_attr >> 16)):
                raise ValueError("Unexpected diagnostic ZIP entry")
            names.add(path.as_posix())
        if not names or zipped.testzip() is not None:
            raise ValueError("Diagnostic ZIP is empty or has a CRC failure")
    return digest


def verify_contents(folder: Path) -> dict:
    actual = inventory(folder)
    actual.pop("inventory.json")
    if actual != read_json(folder / "inventory.json"):
        raise ValueError("Extracted payload hashes or executable modes changed")
    provenance = read_json(folder / "provenance.json")
    if any(provenance.get(k) != v for k, v in LIMITS.items()):
        raise ValueError("Diagnostic-only provenance is missing")
    return provenance


def verify(source: Path, output: Path, extracted: Path) -> None:
    report = {**LIMITS, "status": "FAIL", "scope": "package integrity and input-free native startup only"}
    try:
        report["verificationHost"] = {"macOS": platform.mac_ver()[0], "architecture": platform.machine(),
                                      "build": run("/usr/bin/sw_vers", "-buildVersion"),
                                      "xcode": run("/usr/bin/xcodebuild", "-version")}
        report["applicationSource"] = checked_source(source)
        report["archiveSHA256"] = checked_archive(output)
        extracted.mkdir(parents=True, exist_ok=False)
        run("/usr/bin/ditto", "-x", "-k", output / ARCHIVE, extracted)
        folder = extracted / FOLDER
        helper = folder / HELPER
        payload = helper / PAYLOAD
        provenance = verify_contents(folder)
        manifest = verify_payload(payload)
        expected_sources = helper_source(run("git", "-C", ROOT, "rev-parse", "HEAD"))
        if (provenance != read_json(output / "provenance.json")
                or provenance["applicationSource"] != report["applicationSource"]
                or any(manifest.get(k) != v or provenance.get(k) != v for k, v in expected_sources.items())
                or provenance["application"] != verify_bundle(payload / APPLICATION, APPLICATION_ID, "Lemulip")
                or provenance["helper"] != verify_bundle(helper, HELPER_ID, EXECUTABLE)
                or provenance["kitManifestSHA256"] != sha256(payload / "kit-manifest.json")):
            raise ValueError("Extracted bundle/source identity differs from this verification")
        run("/bin/bash", source / "script/build_and_run.sh", "--verify-bundle", payload / APPLICATION)
        package_check = json.loads(run(helper / "Contents/MacOS" / EXECUTABLE, "--verify-package"))
        expected = {"schema": 1, "status": "PASS", "payloadVerified": True, "inputEventsSent": 0,
                    "helperBundleIdentifier": HELPER_ID, "diagnosticOnly": True, "releaseReady": False}
        if any(package_check.get(k) != v for k, v in expected.items()):
            raise ValueError("Helper package self-check did not verify its own payload")
        smoke = output / "smoke-ui.json"
        if smoke.exists():
            raise ValueError("Refusing an existing helper smoke receipt")
        run("/usr/bin/open", "-n", "-W", "-a", helper, "--args", "--smoke-ui", smoke)
        if any(read_json(smoke).get(k) != v for k, v in {**expected, "mode": "ui-smoke", "seconds": 3}.items()):
            raise ValueError("Helper input-free UI smoke did not complete")
        verify_contents(folder)
        checked_source(source)
        if sha256(output / ARCHIVE) != report["archiveSHA256"]:
            raise ValueError("Diagnostic ZIP changed during verification")
        report.update(status="PASS", inventoryHashesAndModes="PASS", signatureIdentityAndArm64="PASS",
                      nativeApplicationLaunch={"status": "PASS", "seconds": 3},
                      helperPackageCheck=package_check, helperUISmoke=read_json(smoke))
    except Exception as error:
        report["errorType"] = type(error).__name__
        raise
    finally:
        write_json(output / "verification.json", report)


def validate_observation(result: dict, mode: str, manifest: dict) -> dict:
    expected = {"schema": 1, "mode": mode, "diagnosticOnly": True, "releaseReady": False,
                "physicalInputVerified": False, "reportRetained": True}
    if any(result.get(k) != v for k, v in expected.items()):
        raise ValueError("Missing diagnostic execution receipt")
    case = result.get("case", {})
    identity = {"sourceCommit": APPLICATION_COMMIT, "sourceTree": APPLICATION_TREE,
                "stagedGUI_SHA256": manifest["stagedGUI_SHA256"],
                "theme": "orchard", "targetKind": "production", "inputDriver": "CGEvent",
                "permissionRequested": False,
                **{k: manifest[k] for k in ("helperCommit", "observerSourceSHA256", "helperSourceSHA256")}}
    if any(case.get(k) != v for k, v in identity.items()):
        raise ValueError("Observed source/binary identity does not match the package")
    cleanup = case.get("cleanup", {})
    if (cleanup.get("completed") is not True or cleanup.get("errors") != []
            or cleanup.get("leftButtonReportedDown") is not False
            or not all(cleanup.get(k) is True for k in
                       ("applicationStopped", "fixtureFinderWindowClosed", "fixedBundleRegistryEmpty"))):
        raise ValueError("Diagnostic cleanup did not complete")
    same_host = case.get("sameHost", {})
    if (same_host.get("imagesCaptured") is not False or same_host.get("screenCaptureRequired") is not False
            or same_host.get("captureKind") != "target-ax-and-input-state"
            or case.get("preflight") != {"accessibility": True, "postEvents": True}):
        raise ValueError("Missing image-free authorized observation")
    before = [r.get("workspace", {}) for r in case.get("escapeObservations", []) if r.get("phase") == "before-key"]
    if len(before) != 1:
        raise ValueError("Missing initial workspace observation")
    state = before[0]
    names = state.get("observedFilenames", [])
    if (len(names) != 1 or not re.fullmatch(r"Existing-[0-9a-f]{32}\.txt", names[0])
            or state.get("matchesExpectedWorkspace") is not True or state.get("selectedCountLabels") != ["1 Selected"]):
        raise ValueError("Initial workspace is not exactly Existing / 1 Selected")
    escape = case.get("sameHostEscape", {})
    if any(escape.get(k) != v for k, v in {"leadInSeconds": 0, "dwellSeconds": 0.15,
            "externalDownTimeoutSeconds": 12, "externalUpTimeoutSeconds": 4}.items()):
        raise ValueError("Unexpected diagnostic timing options")
    if mode == "ci-baseline":
        cancellation = case.get("escapeCancellation")
        captured = case.get("status") == "captured" and case.get("gestureOutcomesVerified") is True
        expected_failure = case.get("status") == "failed" and case.get("reason") == ESCAPE_FAILURE
        if (not isinstance(cancellation, dict) or not (captured or expected_failure)
                or cancellation.get("matchesExpectedWorkspace") is not captured
                or escape.get("mode") != "automatic" or escape.get("syntheticEscapePosts") != 2):
            raise ValueError("Baseline did not reach the specific cancellation observation")
    elif mode == "ci-human-timeout":
        if (case.get("status") != "blocked" or escape.get("mode") != "external"
                or escape.get("status") != "timed-out-waiting-down" or escape.get("syntheticEscapePosts") != 0):
            raise ValueError("Physical-key timeout did not retain a clean zero-Escape-post boundary")
    else:
        raise ValueError("Unknown diagnostic validation mode")
    return {"schema": 1, "diagnosticOnly": True, "releaseReady": False, "mode": mode,
            "executionValidated": True, "observedCaseStatus": case["status"],
            "cancellationAcceptedByThisCheck": False, "physicalInputVerified": False}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["stage", "verify", "check-observation"])
    for name in ("source", "staged", "observer-binary", "output", "extracted", "report", "payload"):
        parser.add_argument("--" + name, type=Path)
    parser.add_argument("--workflow-commit")
    parser.add_argument("--mode", choices=["ci-baseline", "ci-human-timeout"])
    args = parser.parse_args()
    if args.operation == "check-observation":
        if not all((args.report, args.payload, args.mode)):
            parser.error("check-observation requires --report, --payload and --mode")
        result = validate_observation(read_json(args.report), args.mode, verify_payload(args.payload))
        if any(p.suffix.lower() == ".png" and not any(c.endswith(".app") for c in p.relative_to(args.report.parent).parts)
               for p in args.report.parent.rglob("*")):
            raise ValueError("Unexpected screenshot in the diagnostic evidence")
        write_json(args.report.parent / "execution-validation.json", result)
        print(json.dumps(result))
        return
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        parser.error("Packaging and native verification require an arm64 Mac")
    if not args.source or not args.output:
        parser.error("stage and verify require --source and --output")
    if args.operation == "stage":
        if not all((args.staged, args.observer_binary, args.workflow_commit)):
            parser.error("stage requires --staged, --observer-binary and --workflow-commit")
        stage(args.source.resolve(), args.staged.resolve(), args.observer_binary.resolve(), args.output.resolve(), args.workflow_commit)
    else:
        if not args.extracted:
            parser.error("verify requires a new --extracted directory")
        verify(args.source.resolve(), args.output.resolve(), args.extracted.resolve())


if __name__ == "__main__":
    main()
