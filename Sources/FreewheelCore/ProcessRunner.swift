import Foundation
#if os(macOS)
import Darwin
#else
import Glibc
#endif

struct ProcessOutput: Sendable {
    let standardOutput: Data
    let standardError: Data
    let exitCode: Int32
    var errorText: String { String(decoding: standardError, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Drains both pipes while the process runs. Cancellation also stops the child.
enum ProcessRunner {
    static func run(executable: URL, arguments: [String], currentDirectory: URL? = nil,
                    environment: [String: String] = [:], maximumOutputBytes: Int = 524_288,
                    timeout: TimeInterval = 900, denyNetwork: Bool = true,
                    allowedUnixSockets: [URL] = []) async throws -> ProcessOutput {
        try Task.checkCancellation()
        guard executable.isFileURL, maximumOutputBytes > 0, timeout > 0,
              allowedUnixSockets.allSatisfy({ $0.isFileURL && $0.path != "/" && !$0.path.contains("\0") }) else {
            throw FreewheelError.invalidInput("Invalid converter process configuration.")
        }
        var launchURL = executable
        var launchArguments = arguments
        #if os(macOS)
        // This profile restricts optional converter processes; the app itself has no network client.
        if denyNetwork {
            guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") else {
                throw FreewheelError.unsupported("This macOS installation cannot enforce offline access for optional converters because sandbox-exec is unavailable. Built-in conversions remain available.")
            }
            launchURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            var profile = "(version 1)(allow default)(deny network*)"
            var parameters: [String] = []
            // LibreOffice needs its own Unix IPC socket even in headless mode.
            // Exact path parameters grant no IP access or access to other sockets.
            for (index, socket) in allowedUnixSockets.enumerated() {
                let key = "FREEWHEEL_SOCKET_\(index)"
                parameters += ["-D", "\(key)=\(socket.resolvingSymlinksInPath().path)"]
                profile += "(allow network-bind network-inbound (local unix-socket (path-literal (param \"\(key)\"))))"
                profile += "(allow network-outbound (remote unix-socket (path-literal (param \"\(key)\"))))"
            }
            launchArguments = parameters + ["-p", profile, executable.path] + arguments
        }
        #endif
        let state = ProcessState(executable: launchURL, arguments: launchArguments,
                                 currentDirectory: currentDirectory, environment: environment,
                                 maximumOutputBytes: maximumOutputBytes, timeout: timeout)
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in state.start(continuation) }
        }, onCancel: { state.cancel() })
    }

    static func checked(executable: URL, arguments: [String], currentDirectory: URL? = nil,
                        environment: [String: String] = [:], timeout: TimeInterval = 900,
                        allowedUnixSockets: [URL] = []) async throws -> ProcessOutput {
        let output = try await run(executable: executable, arguments: arguments, currentDirectory: currentDirectory,
                                   environment: environment, timeout: timeout, allowedUnixSockets: allowedUnixSockets)
        guard output.exitCode == 0 else {
            let reason = output.errorText.isEmpty ? "Exit status \(output.exitCode)." : String(output.errorText.prefix(3_000))
            throw FreewheelError.operationFailed("\(executable.lastPathComponent) could not complete the conversion. \(reason)")
        }
        return output
    }
}

private final class ProcessState: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.freewheel.converter.\(UUID().uuidString)")
    private let executable: URL
    private let arguments: [String]
    private let currentDirectory: URL?
    private let environment: [String: String]
    private let maximumOutputBytes: Int
    private let timeout: TimeInterval
    private var continuation: CheckedContinuation<ProcessOutput, Error>?
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var outputSource: DispatchSourceRead?
    private var errorSource: DispatchSourceRead?
    private var deadline: DispatchSourceTimer?
    private var stdout = Data()
    private var stderr = Data()
    private var cancellationRequested = false
    private var terminalError: Error?
    private var finished = false

    init(executable: URL, arguments: [String], currentDirectory: URL?, environment: [String: String],
         maximumOutputBytes: Int, timeout: TimeInterval) {
        self.executable = executable; self.arguments = arguments; self.currentDirectory = currentDirectory
        self.environment = environment; self.maximumOutputBytes = maximumOutputBytes; self.timeout = timeout
    }

    func start(_ continuation: CheckedContinuation<ProcessOutput, Error>) {
        queue.async { [self] in
            self.continuation = continuation
            if cancellationRequested { finish(.failure(FreewheelError.cancelled)); return }
            let child = Process()
            child.executableURL = executable; child.arguments = arguments; child.currentDirectoryURL = currentDirectory
            let inherited = ProcessInfo.processInfo.environment
            let allowed = ["PATH", "HOME", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "FONTCONFIG_PATH", "FONTCONFIG_FILE"]
            var cleanEnvironment: [String: String] = [:]
            for key in allowed { if let value = inherited[key] { cleanEnvironment[key] = value } }
            cleanEnvironment["PATH"] = cleanEnvironment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            cleanEnvironment["LANG"] = cleanEnvironment["LANG"] ?? "en_US.UTF-8"
            cleanEnvironment.merge(environment) { _, replacement in replacement }
            child.environment = cleanEnvironment
            child.standardInput = FileHandle.nullDevice
            let out = Pipe(), err = Pipe()
            child.standardOutput = out; child.standardError = err
            outputPipe = out; errorPipe = err; process = child
            outputSource = makeSource(out.fileHandleForReading, isError: false)
            errorSource = makeSource(err.fileHandleForReading, isError: true)
            child.terminationHandler = { [weak self] child in
                guard let self else { return }
                self.queue.async { [self] in
                    self.drain(isError: false); self.drain(isError: true)
                    if let terminalError = self.terminalError { self.finish(.failure(terminalError)) }
                    else { self.finish(.success(ProcessOutput(standardOutput: self.stdout, standardError: self.stderr, exitCode: child.terminationStatus))) }
                }
            }
            do {
                try child.run()
                let timer = DispatchSource.makeTimerSource(queue: queue)
                timer.schedule(deadline: .now() + timeout)
                timer.setEventHandler { [weak self] in
                    self?.stop(error: FreewheelError.operationFailed("The converter exceeded its time limit and was stopped."))
                }
                deadline = timer; timer.resume()
                if cancellationRequested { stop(error: FreewheelError.cancelled) }
            } catch { finish(.failure(FreewheelError.operationFailed("Could not start \(executable.lastPathComponent): \(error.localizedDescription)"))) }
        }
    }

    func cancel() {
        queue.async { [self] in
            cancellationRequested = true
            if continuation != nil { stop(error: FreewheelError.cancelled) }
        }
    }

    private func makeSource(_ handle: FileHandle, isError: Bool) -> DispatchSourceRead {
        let descriptor = handle.fileDescriptor
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.drain(isError: isError) }
        source.resume()
        return source
    }

    private func drain(isError: Bool) {
        guard !finished, let pipe = isError ? errorPipe : outputPipe else { return }
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        var bytes = [UInt8](repeating: 0, count: 32_768)
        while true {
            let count = bytes.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if count > 0 {
                let existing = isError ? stderr.count : stdout.count
                let available = min(count, max(0, maximumOutputBytes - existing))
                if available > 0 {
                    if isError { stderr.append(contentsOf: bytes.prefix(available)) }
                    else { stdout.append(contentsOf: bytes.prefix(available)) }
                }
            } else if count < 0, errno == EINTR { continue }
            else {
                if count == 0 {
                    if isError { errorSource?.cancel(); errorSource = nil }
                    else { outputSource?.cancel(); outputSource = nil }
                }
                return
            }
        }
    }

    private func stop(error: Error) {
        guard !finished else { return }
        terminalError = error
        guard let process else { finish(.failure(error)); return }
        if process.isRunning {
            process.terminate()
            queue.asyncAfter(deadline: .now() + 2) { [weak self, weak process] in
                guard let self, !self.finished, let process, process.isRunning else { return }
                _ = kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    private func finish(_ result: Result<ProcessOutput, Error>) {
        guard !finished else { return }
        finished = true
        deadline?.cancel(); deadline = nil
        outputSource?.cancel(); errorSource?.cancel(); outputSource = nil; errorSource = nil
        try? outputPipe?.fileHandleForReading.close(); try? errorPipe?.fileHandleForReading.close()
        process?.terminationHandler = nil
        let completion = continuation; continuation = nil
        completion?.resume(with: result)
    }
}
