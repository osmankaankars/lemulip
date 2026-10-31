#!/usr/bin/env python3
"""Prepare an isolated production app copy and external XCTest runner, without publishing."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import platform
import plistlib
import shutil
import struct
import subprocess
import zlib

ROOT = Path(__file__).resolve().parent.parent
BUNDLE_ID = "app.lemulip.NativeUIReview"


def isolated_info(info: dict) -> dict:
    if info.get("CFBundleIdentifier") != "app.freewheel.Freewheel" or info.get("CFBundleExecutable") != "Lemulip":
        raise ValueError("Select a locally built production Lemulip bundle")
    result = copy.deepcopy(info)
    result.update(CFBundleIdentifier=BUNDLE_ID, CFBundleName="Lemulip Native UI Review",
                  CFBundleDisplayName="Lemulip Native UI Review")
    return result


PROJECT = r'''// !$*UTF8*$!
{
 archiveVersion = 1;
 classes = {};
 objectVersion = 56;
 objects = {
  A00000000000000000000001 = {isa = PBXProject; attributes = {LastUpgradeCheck = 1600;}; buildConfigurationList = A00000000000000000000002; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en, Base); mainGroup = A00000000000000000000003; productRefGroup = A00000000000000000000004; projectDirPath = ""; projectRoot = ""; targets = (A00000000000000000000005);};
  A00000000000000000000002 = {isa = XCConfigurationList; buildConfigurations = (A00000000000000000000006); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;};
  A00000000000000000000003 = {isa = PBXGroup; children = (A00000000000000000000007, A00000000000000000000008, A00000000000000000000004); sourceTree = "<group>";};
  A00000000000000000000004 = {isa = PBXGroup; children = (A00000000000000000000009); name = Products; sourceTree = "<group>";};
  A00000000000000000000005 = {isa = PBXNativeTarget; buildConfigurationList = A0000000000000000000000A; buildPhases = (A0000000000000000000000B, A0000000000000000000000C); buildRules = (); dependencies = (); name = QualityReview; productName = QualityReview; productReference = A00000000000000000000009; productType = "com.apple.product-type.bundle.ui-testing";};
  A00000000000000000000006 = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 13.0; SWIFT_VERSION = 5.0; CLANG_ENABLE_MODULES = YES;}; name = Debug;};
  A00000000000000000000007 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = QualityUITests.swift; sourceTree = "<group>";};
  A00000000000000000000008 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ReviewConfiguration.swift; sourceTree = "<group>";};
  A00000000000000000000009 = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = QualityReview.xctest; sourceTree = BUILT_PRODUCTS_DIR;};
  A0000000000000000000000A = {isa = XCConfigurationList; buildConfigurations = (A0000000000000000000000D); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;};
  A0000000000000000000000B = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (A0000000000000000000000E, A0000000000000000000000F); runOnlyForDeploymentPostprocessing = 0;};
  A0000000000000000000000C = {isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;};
  A0000000000000000000000D = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_BUNDLE_IDENTIFIER = app.lemulip.NativeQualityUITests; PRODUCT_NAME = "$(TARGET_NAME)"; GENERATE_INFOPLIST_FILE = YES; CODE_SIGN_IDENTITY = "-"; CODE_SIGN_STYLE = Manual; ENABLE_HARDENED_RUNTIME = NO; ENABLE_TESTING_SEARCH_PATHS = YES; SWIFT_OPTIMIZATION_LEVEL = "-Onone"; SKIP_INSTALL = YES; LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/../Frameworks", "@loader_path/../Frameworks");}; name = Debug;};
  A0000000000000000000000E = {isa = PBXBuildFile; fileRef = A00000000000000000000007;};
  A0000000000000000000000F = {isa = PBXBuildFile; fileRef = A00000000000000000000008;};
 };
 rootObject = A00000000000000000000001;
}
'''

SCHEME = '''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
 <BuildAction parallelizeBuildables="NO" buildImplicitDependencies="YES">
  <BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">
   <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A00000000000000000000005" BuildableName="QualityReview.xctest" BlueprintName="QualityReview" ReferencedContainer="container:QualityReview.xcodeproj"/>
  </BuildActionEntry></BuildActionEntries>
 </BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
  <Testables><TestableReference skipped="NO" parallelizable="NO">
   <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A00000000000000000000005" BuildableName="QualityReview.xctest" BlueprintName="QualityReview" ReferencedContainer="container:QualityReview.xcodeproj"/>
  </TestableReference></Testables>
 </TestAction>
</Scheme>
'''


def swift_string(value: str) -> str:
    # JSON escapes ordinary path quotes/backslashes. Encode uncommon control
    # characters using Swift's braced Unicode syntax rather than JSON's form.
    import re
    return re.sub(r'\\u([0-9a-fA-F]{4})', r'\\u{\1}', json.dumps(value, ensure_ascii=False))


def write_project(output: Path, suite: Path, app: Path, fixtures: Path) -> Path:
    output.mkdir(parents=True, exist_ok=False)
    project = output / "QualityReview.xcodeproj"
    scheme = project / "xcshareddata/xcschemes"
    scheme.mkdir(parents=True)
    (project / "project.pbxproj").write_text(PROJECT)
    (scheme / "QualityReview.xcscheme").write_text(SCHEME)
    shutil.copy2(suite, output / "QualityUITests.swift")
    (output / "ReviewConfiguration.swift").write_text(
        "import Foundation\nenum ReviewConfiguration {\n"
        f" static let application = URL(fileURLWithPath: {swift_string(str(app))})\n"
        f" static let fixtures = URL(fileURLWithPath: {swift_string(str(fixtures))})\n"
        "}\n")
    return project


def hash_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(*args: str | Path, timeout: int = 90) -> str:
    return subprocess.check_output([str(arg) for arg in args], text=True, timeout=timeout).strip()


def prepare(app: Path, output: Path) -> None:
    if platform.system() != "Darwin":
        raise ValueError("External native UI review requires macOS and Xcode")
    app = app.resolve(strict=True)
    info_file = app / "Contents/Info.plist"
    info = isolated_info(plistlib.loads(info_file.read_bytes()))
    if any(path.is_symlink() for path in app.rglob("*")):
        raise ValueError("Review only self-contained local app bundles without symlinks")
    original = {str(p.relative_to(app)): hash_file(p) for p in app.rglob("*") if p.is_file()}
    output.mkdir(parents=True, exist_ok=False)
    output = output.resolve()
    staged = output / "Lemulip Native UI Review.app"
    shutil.copytree(app, staged)
    (staged / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    run("/usr/bin/codesign", "--force", "--sign", "-", "--identifier", BUNDLE_ID, staged)
    run("/usr/bin/codesign", "--verify", "--strict", staged)
    fixtures = output / "Fixtures"
    run("/usr/bin/xcrun", "--sdk", "macosx", "swift", ROOT / "script/ui_review_fixtures.swift", "make", fixtures)
    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    rows = b"".join(
        b"\0" + b"".join(bytes((x * 7, y * 9, 96)) for x in range(32)) for y in range(24))
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 32, 24, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")
    (fixtures / "Quality.png").write_bytes(png)
    write_project(output / "Runner", ROOT / "script/native_ui/QualityUITests.swift", staged, fixtures)
    if original != {str(p.relative_to(app)): hash_file(p) for p in app.rglob("*") if p.is_file()}:
        raise ValueError("Original app changed while staging the isolated copy")
    record = {"schema": 1, "sourceCommit": run("git", "-C", ROOT, "rev-parse", "HEAD"),
              "sourceTree": run("git", "-C", ROOT, "rev-parse", "HEAD^{tree}"),
              "architecture": platform.machine(), "bundleIdentifier": BUNDLE_ID,
              "version": info.get("CFBundleShortVersionString"), "build": info.get("CFBundleVersion"),
              "originalGUI_SHA256": original["Contents/MacOS/Lemulip"],
              "stagedGUI_SHA256": hash_file(staged / "Contents/MacOS/Lemulip"),
              "testSourceSHA256": hash_file(ROOT / "script/native_ui/QualityUITests.swift"),
              "originalBundleUnchanged": True, "testStatus": "NOT RUN", "releaseReady": False,
              "scope": "External XCUIAutomation of the staged production app. No VoiceOver or audio audition."}
    (output / "provenance.json").write_text(json.dumps(record, indent=2) + "\n")
    print("Prepared isolated native UI runner without changing or installing the original app.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    prepare(args.app, args.output)
