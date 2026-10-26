import XCTest
@testable import LemulipCore
final class EngineHealthTests: XCTestCase {
    private func engine(_ body: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lemulip-engine-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent("ffmpeg")
        try ("#!/bin/sh\n" + body).write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return path
    }
    func testMissingExecutableIsReportedWithoutLaunching() async throws {
        let report = try await EngineHealth.inspect("ffmpeg", executable: URL(fileURLWithPath: "/nonexistent-lemulip/ffmpeg"))
        XCTAssertEqual(report.state, .unusable)
    }
    func testBundledFFprobeUsesFFmpegPackAndTakesPriority() throws {
        let root = try engine("exit 0").deletingLastPathComponent()
        let bin = root.appendingPathComponent("Lemulip.app/Contents/Helpers/Engines/ffmpeg/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let probe = bin.appendingPathComponent("ffprobe")
        try "#!/bin/sh\nexit 0\n".write(to: probe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: probe.path)
        XCTAssertEqual(EngineLocator.find("ffprobe", bundleURL: root.appendingPathComponent("Lemulip.app"), homeDirectory: root), probe)
    }
    func testRequiredCodecCheckFailsBeforeConversion() throws {
        let report = EngineReport(name: "ffmpeg", executable: URL(fileURLWithPath: "/tmp/ffmpeg"), state: .limited,
                                  version: "8", capabilities: ["aac"], detail: "")
        XCTAssertThrowsError(try EngineHealth.require(report, capabilities: ["libx264"]))
        XCTAssertNoThrow(try EngineHealth.require(report, capabilities: ["aac"]))
    }
    func testUnusedOptionalAudioEncoderDoesNotBlockVideoConversion() {
        let optional = ["-map", "0:v:0", "-map", "0:a:0?", "-c:v", "libx264", "-c:a", "aac"]
        XCTAssertEqual(ExternalConverters.requiredEncoders(in: optional), ["libx264"])
        let muted = ["-an", "-c:v", "libx264", "-c:a", "aac"]
        XCTAssertEqual(ExternalConverters.requiredEncoders(in: muted), ["libx264"])
        let audio = ["-map", "0:a:0", "-vn", "-c:a", "libopus"]
        XCTAssertEqual(ExternalConverters.requiredEncoders(in: audio), ["libopus"])
    }
    func testExecutableThatFailsIsNotHealthy() async throws {
        let path = try engine("exit 126")
        let report = try await EngineHealth.inspect("ffmpeg", executable: path)
        XCTAssertEqual(report.state, .unusable)
    }
    func testUnrelatedExecutableCannotPassByExitingZero() async throws {
        let path = try engine("echo unrelated-command")
        let report = try await EngineHealth.inspect("ffmpeg", executable: path)
        XCTAssertEqual(report.state, .unusable)
    }
    func testMissingCodecsAreReportedWithoutDisablingAvailableOnes() async throws {
        let path = try engine("case \"$*\" in *-encoders*) printf ' A..... aac AAC encoder\\n A..... libopus Opus encoder\\n';; *) echo 'ffmpeg version 8.0';; esac")
        let report = try await EngineHealth.inspect("ffmpeg", executable: path)
        XCTAssertEqual(report.state, .limited)
        XCTAssertEqual(report.version, "8.0")
        XCTAssertTrue(report.capabilities.contains("aac"))
        XCTAssertFalse(report.capabilities.contains("libx264"))
    }
    func testImageMagickFormatTablesWithAndWithoutModuleColumn() async throws {
        for row in ["PNG* rw- PNG image", "PNG* PNG rw- PNG image"] {
            let path = try engine("case \"$*\" in *-list*) echo '\(row)';; *) echo 'Version: ImageMagick 7.1.2-1';; esac")
            let report = try await EngineHealth.inspect("imagemagick", executable: path)
            XCTAssertTrue(report.capabilities.contains("read:PNG"), row)
            XCTAssertTrue(report.capabilities.contains("write:PNG"), row)
            XCTAssertFalse(report.capabilities.contains("write:AVIF"), "Do not infer codecs from explanatory text")
        }
    }
    func testStalledProbeHasBoundedRuntime() async throws {
        let path = try engine("sleep 20")
        let start = Date()
        let report = try await EngineHealth.inspect("ffmpeg", executable: path, timeout: 0.2)
        XCTAssertEqual(report.state, .unusable)
        XCTAssertLessThan(Date().timeIntervalSince(start), 4)
    }
    func testCancellationDoesNotBecomeMissingOrHealthyStatus() async throws {
        let path = try engine("sleep 20")
        let task = Task { try await EngineHealth.inspect("ffmpeg", executable: path) }
        try await Task.sleep(nanoseconds: 100_000_000); task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected cancellation error: \(error)") }
    }
}
