import Foundation
import CLemulipProcess
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

/// Drains both pipes while the process runs. Each converter owns a process group, including its helper processes.
enum ProcessRunner {
    static func canonicalDirectoryPath(_ directory: URL) throws -> String {
        let path = directory.path
        guard directory.isFileURL, path.hasPrefix("/"), !path.contains("\0") else {
            throw LemulipError.invalidInput("A converter directory must be a local absolute path.")
        }
        // Foundation's resolvingSymlinksInPath may shorten /private/tmp to /tmp.
        // POSIX realpath preserves the filesystem spelling used by LibreOffice.
        guard let resolved = path.withCString({ realpath($0, nil) }) else {
            throw LemulipError.invalidInput("A converter directory could not be resolved.")
        }
        defer { free(resolved) }
        var info = stat()
        guard lstat(resolved, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
            throw LemulipError.invalidInput("A converter directory is not available.")
        }
        return String(cString: resolved)
    }

    static func canonicalUnixSocketPath(_ socket: URL) throws -> String {
        let name = socket.lastPathComponent
        guard socket.isFileURL, !socket.hasDirectoryPath,
              !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw LemulipError.invalidInput("A converter socket must be a local file path.")
        }
        // The socket usually does not exist yet, so resolve its existing parent.
        let parent = try canonicalDirectoryPath(socket.deletingLastPathComponent())
        let path = (parent == "/" ? "" : parent) + "/" + name
        var info = stat()
        if lstat(path, &info) == 0 {
            // Never turn a symlink at the requested name into a grant elsewhere.
            guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFSOCK) else {
                throw LemulipError.invalidInput("A converter socket path is already occupied.")
            }
        } else if errno != ENOENT {
            throw LemulipError.invalidInput("A converter socket path could not be checked.")
        }
        return path
    }

    static func run(executable: URL, arguments: [String], currentDirectory: URL? = nil,
                    environment: [String: String] = [:], maximumOutputBytes: Int = 524_288,
                    timeout: TimeInterval = 900, denyNetwork: Bool = true,
                    allowedUnixSockets: [URL] = []) async throws -> ProcessOutput {
        try Task.checkCancellation()
        guard executable.isFileURL, maximumOutputBytes > 0, timeout > 0, timeout.isFinite,
              allowedUnixSockets.allSatisfy({ $0.isFileURL && $0.path != "/" && !$0.path.contains("\0") }) else {
            throw LemulipError.invalidInput("Invalid converter process configuration.")
        }
        var launchURL = executable
        var launchArguments = arguments
        #if os(macOS)
        // This profile restricts optional converter processes; the app itself has no network client.
        if denyNetwork {
            guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") else {
                throw LemulipError.unsupported("This macOS installation cannot enforce offline access for optional converters because sandbox-exec is unavailable. Built-in conversions remain available.")
            }
            launchURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            var profile = "(version 1)(allow default)(deny network*)"
            var parameters: [String] = []
            // LibreOffice needs its own Unix IPC socket even in headless mode.
            // Exact path parameters grant no IP access or access to other sockets.
            for (index, socket) in allowedUnixSockets.enumerated() {
                let key = "LEMULIP_SOCKET_\(index)"
                parameters += ["-D", "\(key)=\(try canonicalUnixSocketPath(socket))"]
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
            throw LemulipError.operationFailed("\(executable.lastPathComponent) could not complete the conversion. \(reason)")
        }
        return output
    }
}

private final class ProcessState: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.lemulip.converter.\(UUID().uuidString)")
    private let executable: URL
    private let arguments: [String]
    private let currentDirectory: URL?
    private let environment: [String: String]
    private let maximumOutputBytes: Int
    private let timeout: TimeInterval
    private var continuation: CheckedContinuation<ProcessOutput, Error>?
    private var processID: pid_t = 0
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
            if cancellationRequested { finish(.failure(LemulipError.cancelled)); return }
            let inherited = ProcessInfo.processInfo.environment
            let allowed = ["PATH", "HOME", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "FONTCONFIG_PATH", "FONTCONFIG_FILE"]
            var cleanEnvironment: [String: String] = [:]
            for key in allowed { if let value = inherited[key] { cleanEnvironment[key] = value } }
            cleanEnvironment["PATH"] = cleanEnvironment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            cleanEnvironment["LANG"] = cleanEnvironment["LANG"] ?? "en_US.UTF-8"
            cleanEnvironment.merge(environment) { _, replacement in replacement }
            let out = Pipe(), err = Pipe()
            outputPipe = out; errorPipe = err
            outputSource = makeSource(out.fileHandleForReading, isError: false)
            errorSource = makeSource(err.fileHandleForReading, isError: true)
            let values = [executable.path] + arguments
            let variables = cleanEnvironment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
            guard values.allSatisfy({ !$0.contains("\0") }), variables.allSatisfy({ !$0.contains("\0") }),
                  currentDirectory?.isFileURL != false, currentDirectory?.path.contains("\0") != true else {
                finish(.failure(LemulipError.invalidInput("Invalid converter arguments."))); return
            }
            let argv = values.map { strdup($0) } + [nil]
            let envp = variables.map { strdup($0) } + [nil]
            defer { for pointer in argv + envp { free(pointer) } }
            guard argv.dropLast().allSatisfy({ $0 != nil }), envp.dropLast().allSatisfy({ $0 != nil }) else {
                finish(.failure(LemulipError.operationFailed("Not enough memory to start the converter."))); return
            }
            let spawnError = argv.withUnsafeBufferPointer { args in
                envp.withUnsafeBufferPointer { env in
                    lemulip_process_spawn(&processID, executable.path, args.baseAddress, env.baseAddress,
                        currentDirectory?.path, out.fileHandleForWriting.fileDescriptor, err.fileHandleForWriting.fileDescriptor)
                }
            }
            try? out.fileHandleForWriting.close(); try? err.fileHandleForWriting.close()
            guard spawnError == 0 else {
                finish(.failure(LemulipError.operationFailed("Could not start \(executable.lastPathComponent): \(String(cString: strerror(spawnError)))"))); return
            }
            let pid = processID
            DispatchQueue.global(qos: .utility).async { [self] in
                var status: Int32 = 0
                let waitError = lemulip_process_wait(pid, &status)
                let exitCode = status
                self.queue.async { [self] in
                    // WNOWAIT keeps the leader unreaped until signals are done, preventing
                    // PID reuse. Never let an exited converter leave background writers.
                    if waitError == 0 {
                        _ = lemulip_process_signal_group(pid, SIGKILL)
                        _ = lemulip_process_reap(pid)
                    }
                    processID = 0
                    drain(isError: false); drain(isError: true)
                    if let terminalError { finish(.failure(terminalError)) }
                    else if waitError != 0 { finish(.failure(LemulipError.operationFailed("Could not observe converter completion."))) }
                    else { finish(.success(ProcessOutput(standardOutput: stdout, standardError: stderr, exitCode: exitCode))) }
                }
            }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler { [weak self] in
                self?.stop(error: LemulipError.operationFailed("The converter exceeded its time limit and was stopped."))
            }
            deadline = timer; timer.resume()
            if cancellationRequested { stop(error: LemulipError.cancelled) }

        }
    }

    func cancel() {
        queue.async { [self] in
            cancellationRequested = true
            if continuation != nil { stop(error: LemulipError.cancelled) }
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
        guard terminalError == nil else { return }
        terminalError = error
        guard processID > 1 else { finish(.failure(error)); return }
        let pid = processID
        _ = lemulip_process_signal_group(pid, SIGTERM)
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, !self.finished, self.processID == pid else { return }
            _ = lemulip_process_signal_group(pid, SIGKILL)
        }
    }

    private func finish(_ result: Result<ProcessOutput, Error>) {
        guard !finished else { return }
        finished = true
        deadline?.cancel(); deadline = nil
        outputSource?.cancel(); errorSource?.cancel(); outputSource = nil; errorSource = nil
        try? outputPipe?.fileHandleForReading.close(); try? errorPipe?.fileHandleForReading.close()
        try? outputPipe?.fileHandleForWriting.close(); try? errorPipe?.fileHandleForWriting.close()
        let completion = continuation; continuation = nil
        completion?.resume(with: result)
    }
}
