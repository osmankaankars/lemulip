import XCTest
@testable import LemulipCore
#if os(macOS)
import Darwin
#else
import Glibc
#endif

final class ProcessLifecycleTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lemulip-lifecycle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func cleanup(_ root: URL) {
        if let raw = try? String(contentsOf: root.appendingPathComponent("child.pid")),
           let pid = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1 { _ = kill(pid, SIGKILL) }
        try? FileManager.default.removeItem(at: root)
    }
    private let program = "(trap '' TERM; sleep 1; echo survived > survived.txt; sleep 10) & echo $! > child.pid; wait"

    func testTimeoutStopsOwnedDescendants() async throws {
        let root = try fixture(); defer { cleanup(root) }
        do {
            _ = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", program], currentDirectory: root, timeout: 0.3)
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error.localizedDescription.contains("time limit")) }
        try await Task.sleep(nanoseconds: 1_300_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("survived.txt").path), "A descendant continued writing after timeout")
    }
    func testCancellationStopsOwnedDescendantsButNotUnrelatedProcesses() async throws {
        let root = try fixture(); defer { cleanup(root) }
        let other = Process(); other.executableURL = URL(fileURLWithPath: "/bin/sleep"); other.arguments = ["10"]
        try other.run(); defer { _ = kill(other.processIdentifier, SIGKILL); other.waitUntilExit() }
        let running = Task { try await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", self.program], currentDirectory: root, timeout: 10) }
        try await Task.sleep(nanoseconds: 300_000_000); running.cancel()
        do { _ = try await running.value; XCTFail("Expected cancellation") } catch { }
        try await Task.sleep(nanoseconds: 1_300_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("survived.txt").path))
        XCTAssertTrue(other.isRunning, "Cancellation must not signal unrelated programs")
    }
    func testSuccessfulParentCannotLeaveWritersBehind() async throws {
        let root = try fixture(); defer { cleanup(root) }
        let output = try await ProcessRunner.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "(sleep 1; echo survived > survived.txt; sleep 10) & echo $! > child.pid; echo finished"], currentDirectory: root, timeout: 10)
        XCTAssertEqual(output.exitCode, 0)
        XCTAssertTrue(String(decoding: output.standardOutput, as: UTF8.self).contains("finished"))
        try await Task.sleep(nanoseconds: 1_300_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("survived.txt").path))
    }
}
