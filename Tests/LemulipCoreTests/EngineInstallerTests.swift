import XCTest
@testable import LemulipCore

final class EngineInstallerTests: XCTestCase {
    func testOnlyPinnedArchitecturesAndHTTPSReleaseHostsAreAllowed() throws {
        for arch in ["arm64", "x86_64"] {
            let package = try PandocPackage(architecture: arch)
            XCTAssertEqual(package.version, "3.12.1")
            XCTAssertEqual(package.sha256.count, 64)
            XCTAssertTrue(PandocPackage.allowsDownload(package.url))
        }
        XCTAssertThrowsError(try PandocPackage(architecture: "other"))
        for value in ["http://github.com/file", "https://github.com.evil.invalid/file", "file:///tmp/a", "https://github.com:444/a"] {
            XCTAssertFalse(PandocPackage.allowsDownload(URL(string: value)!))
        }
        var credentials = URLComponents(string: "https://github.com/a")!
        credentials.user = "fixture"; credentials.password = "fixture"
        XCTAssertFalse(PandocPackage.allowsDownload(credentials.url!))
        XCTAssertTrue(PandocPackage.allowsDownload(URL(string: "https://release-assets.githubusercontent.com/asset")!))
    }
    #if os(macOS)
    func testCorruptPackageCannotInstallOrReplaceExistingEngine() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("bad.zip")
        try Data("not the official archive".utf8).write(to: archive)
        do {
            _ = try await EngineInstaller.installDownloadedPandoc(archive, homeDirectory: root)
            XCTFail("Corrupted download must fail before execution")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Library/Application Support/Lemulip/Engines/pandoc").path))
    }
    #endif
}

#if os(macOS)
extension EngineIntegrationTests {
    func testOfficialPandocCommandlessInstallAndNoOverwrite() async throws {
        guard let path = ProcessInfo.processInfo.environment["LEMULIP_PANDOC_ARCHIVE"] else {
            throw XCTSkip("A verified official archive is supplied by native integration CI")
        }
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("lemulip-installer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let report = try await EngineInstaller.installDownloadedPandoc(URL(fileURLWithPath: path), homeDirectory: home)
        XCTAssertEqual(report.state, .ready)
        let executable = try XCTUnwrap(report.executable)
        XCTAssertTrue(executable.path.hasPrefix(home.path))
        let bytes = try Data(contentsOf: executable)
        do {
            _ = try await EngineInstaller.installDownloadedPandoc(URL(fileURLWithPath: path), homeDirectory: home)
            XCTFail("An existing engine must not be overwritten")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: executable), bytes)
    }
}
#endif
