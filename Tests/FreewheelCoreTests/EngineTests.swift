import XCTest
@testable import FreewheelCore
#if os(macOS)
import Darwin
#endif

final class EngineTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("freewheel-engine-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { if let root { try FileManager.default.removeItem(at: root) } }

    func testBatchTextConversionAndConcurrencyNeverOverwriteInputs() async throws {
        let source = root.appendingPathComponent("subtitles.srt")
        let content = "1\n00:00:00,000 --> 00:00:01,000\nHello\n"
        try content.write(to: source, atomically: true, encoding: .utf8)
        let engine = ConversionEngine()
        let operation = FileOperation(id: "convert.vtt", title: "VTT", outputExtension: "vtt")
        async let first = engine.run(inputs: [source], operation: operation)
        async let second = engine.run(inputs: [source], operation: operation)
        let results = try await [first, second]
        XCTAssertEqual(Set(results.flatMap(\.outputs)).count, 2)
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), content)
        for output in results.flatMap(\.outputs) { XCTAssertTrue(try String(contentsOf: output, encoding: .utf8).hasPrefix("WEBVTT")) }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains(where: { $0.hasPrefix(".freewheel-") }))
    }

    func testInvalidBatchLeavesNoPartialConvertedFiles() async throws {
        let valid = root.appendingPathComponent("valid.srt"), invalid = root.appendingPathComponent("invalid.srt")
        try "1\n00:00:00,000 --> 00:00:01,000\nHello\n".write(to: valid, atomically: true, encoding: .utf8)
        try "This is not a subtitle".write(to: invalid, atomically: true, encoding: .utf8)
        do {
            _ = try await ConversionEngine().run(inputs: [valid, invalid], operation: FileOperation(id: "convert.vtt", title: "VTT"))
            XCTFail("Converted an invalid batch")
        } catch { XCTAssertTrue(error is FreewheelError) }
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)), ["valid.srt", "invalid.srt"])
    }

    func testRemoteURLAndUnsafeExtensionAreRejected() async throws {
        do {
            _ = try await ConversionEngine().run(inputs: [URL(string: "https://example.com/file.png")!], operation: FileOperation(id: "convert.jpg", title: "JPG"))
            XCTFail("Accepted a remote input")
        } catch { XCTAssertTrue(error is FreewheelError) }
        let input = root.appendingPathComponent("table.csv")
        try "a,b\n1,2\n".write(to: input, atomically: true, encoding: .utf8)
        do {
            _ = try await ConversionEngine().run(inputs: [input], operation: FileOperation(id: "convert.tsv", title: "TSV", outputExtension: "../../outside"))
            XCTFail("Accepted an unsafe extension")
        } catch { XCTAssertTrue(error is FreewheelError) }
    }

    func testProcessDrainsBothLargePipesAndBoundsMemory() async throws {
        guard let awk = EngineLocator.find("awk") else { throw XCTSkip("awk is unavailable") }
        let program = "BEGIN { for (i=0; i<6000; i++) { print \"stdout line with enough bytes to fill a pipe\"; print \"stderr line with enough bytes to fill a pipe\" > \"/dev/stderr\" } }"
        let result = try await ProcessRunner.run(executable: awk, arguments: [program], maximumOutputBytes: 16_384, timeout: 10)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.standardOutput.count, 16_384)
        XCTAssertEqual(result.standardError.count, 16_384)
    }

    func testProcessCancellationAndTimeoutStopChild() async throws {
        guard let sleep = EngineLocator.find("sleep") else { throw XCTSkip("sleep is unavailable") }
        let start = Date()
        let running = Task { try await ProcessRunner.run(executable: sleep, arguments: ["30"], timeout: 40) }
        try await Task.sleep(nanoseconds: 100_000_000)
        running.cancel()
        do { _ = try await running.value; XCTFail("Cancellation was ignored") }
        catch { XCTAssertTrue(error is FreewheelError || error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        do { _ = try await ProcessRunner.run(executable: sleep, arguments: ["30"], timeout: 0.1); XCTFail("Timeout was ignored") }
        catch { XCTAssertTrue(error.localizedDescription.contains("time limit")) }
    }

    func testOfficeProfileURLAndIPCNameMatchLibreOffice() throws {
        let profile = root.appendingPathComponent("office profile % # []", isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: false)
        let url = try ExternalConverters.officeProfileURL(profile)
        XCTAssertTrue(url.hasSuffix("/office%20profile%20%25%20%23%20%5B%5D"))
        let canonicalProfile = try XCTUnwrap(URL(string: url))
        let sourceInfo = try FileManager.default.attributesOfItem(atPath: profile.path)
        let resolvedInfo = try FileManager.default.attributesOfItem(atPath: canonicalProfile.path)
        XCTAssertEqual(try XCTUnwrap(sourceInfo[.systemFileNumber] as? NSNumber), try XCTUnwrap(resolvedInfo[.systemFileNumber] as? NSNumber))
        XCTAssertEqual(try XCTUnwrap(sourceInfo[.systemNumber] as? NSNumber), try XCTUnwrap(resolvedInfo[.systemNumber] as? NSNumber))
        let link = root.appendingPathComponent("profile link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: profile)
        XCTAssertEqual(try ExternalConverters.officeProfileURL(link), url)

        let pendingSocket = link.appendingPathComponent("private.sock")
        XCTAssertEqual(try ProcessRunner.canonicalUnixSocketPath(pendingSocket), canonicalProfile.path + "/private.sock")
        XCTAssertThrowsError(try ProcessRunner.canonicalUnixSocketPath(link.appendingPathComponent("missing/socket")))
        try FileManager.default.createSymbolicLink(at: pendingSocket, withDestinationURL: canonicalProfile.appendingPathComponent("other.sock"))
        XCTAssertThrowsError(try ProcessRunner.canonicalUnixSocketPath(pendingSocket), "A dangling socket symlink must not become a grant")
        try FileManager.default.removeItem(at: pendingSocket)
        try Data("occupied".utf8).write(to: pendingSocket)
        XCTAssertThrowsError(try ProcessRunner.canonicalUnixSocketPath(pendingSocket), "An occupied non-socket path must be rejected")
        XCTAssertThrowsError(try ExternalConverters.officeProfileURL(pendingSocket))
        #if os(macOS)
        // Foundation shortens /private paths. LibreOffice hashes their POSIX spelling.
        let fixture = "fw-office-\(UUID().uuidString)"
        let alias = URL(fileURLWithPath: "/tmp/\(fixture)/profile % # []", isDirectory: true)
        let physical = URL(fileURLWithPath: "/private/tmp/\(fixture)", isDirectory: true)
        try FileManager.default.createDirectory(at: alias, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: physical) }
        XCTAssertEqual(try ExternalConverters.officeProfileURL(alias), "file:///private/tmp/\(fixture)/profile%20%25%20%23%20%5B%5D")
        let pending = alias.appendingPathComponent("not-created.sock")
        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path))
        XCTAssertEqual(try ProcessRunner.canonicalUnixSocketPath(pending), "/private/tmp/\(fixture)/profile % # []/not-created.sock")

        // Independent MD5 vectors exercise LibreOffice's unpadded-byte spelling.
        for (profileURL, digest) in [
            ("file:///private/tmp/freewheel-profile", "8dde90caf5ca1b752d47c91e1954854"),
            ("file:///private/tmp/office%20profile%20%25%20%23%20%5B%5D", "1fa5e9fd753261a2573ad92a1224b74")
        ] {
            let sockets = try ExternalConverters.officeIPCSockets(profileURL: profileURL)
            XCTAssertEqual(sockets.map(\.lastPathComponent), Array(repeating: "OSL_PIPE_\(getuid())_SingleOfficeIPC_\(digest)", count: 2))
            XCTAssertEqual(sockets.map { $0.deletingLastPathComponent().path }, ["/private/tmp", "/private/var/tmp"])
        }
        #endif
    }

    #if os(macOS)
    func testProcessAllowsOnlyRequestedUnixSocketAndStillBlocksIP() async throws {
        let python = try XCTUnwrap(EngineLocator.find("python3"), "Python 3 is required for the native sandbox regression")
        // Keep below sockaddr_un's length limit, independent of Darwin's temp path.
        let directory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("fw-ipc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let allowed = directory.appendingPathComponent("allowed\"(x).sock")
        let other = directory.appendingPathComponent("other.sock")
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        let listener = try XCTUnwrap(descriptor >= 0 ? descriptor : nil, "Could not create the ungranted test listener")
        defer { _ = Darwin.close(listener) }
        guard Darwin.fcntl(listener, F_SETFD, FD_CLOEXEC) == 0 else {
            XCTFail("Could not keep the test listener out of child processes")
            return
        }
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array((other.path + "\0").utf8)
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            XCTFail("Generated IPC fixture exceeds the Unix socket path limit")
            return
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, Darwin.listen(listener, 1) == 0 else {
            XCTFail("Could not start the ungranted test listener")
            return
        }
        let program = """
        import errno, os, socket, sys
        allowed, other = sys.argv[1:]
        def blocked(address, family, kind, operation):
            with socket.socket(family, kind) as candidate:
                candidate.settimeout(1)
                try:
                    getattr(candidate, operation)(address)
                except OSError as error:
                    assert error.errno in (errno.EPERM, errno.EACCES), str(error)
                else:
                    raise AssertionError('An ungranted socket operation was allowed')
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
            server.settimeout(1)
            server.bind(allowed)
            server.listen(1)
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
                client.settimeout(1)
                client.connect(allowed)
                connection, _ = server.accept()
                with connection:
                    client.sendall(b'private IPC')
                    assert connection.recv(32) == b'private IPC'
            # These paths have valid parents; failure must be permission denial.
            blocked(allowed + '.other', socket.AF_UNIX, socket.SOCK_STREAM, 'bind')
            blocked(other, socket.AF_UNIX, socket.SOCK_STREAM, 'connect')
            blocked(('127.0.0.1', 0), socket.AF_INET, socket.SOCK_STREAM, 'bind')
            blocked(('127.0.0.1', 9), socket.AF_INET, socket.SOCK_STREAM, 'connect')
            blocked(('::1', 0), socket.AF_INET6, socket.SOCK_STREAM, 'bind')
            blocked(('::1', 9), socket.AF_INET6, socket.SOCK_STREAM, 'connect')
        os.unlink(allowed)
        """
        let result = try await ProcessRunner.run(executable: python, arguments: ["-I", "-c", program, allowed.path, other.path], timeout: 10, allowedUnixSockets: [allowed])
        XCTAssertEqual(result.exitCode, 0, result.errorText)
        let denied = try await ProcessRunner.run(executable: python, arguments: ["-I", "-c", program, allowed.path, other.path], timeout: 10)
        XCTAssertNotEqual(denied.exitCode, 0, "Unix sockets should remain blocked unless explicitly granted")
    }
    #endif
}
