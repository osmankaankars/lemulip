import Foundation

public enum ConversionJobState: Sendable { case waiting, running, succeeded, failed, cancelled }

/// A retry keeps the source ordering, editor selection and destination from submission.
/// Kept in memory only; destructive file actions are never retried automatically.
public struct ConversionRequest: Sendable {
    public let inputs: [URL]
    public let operation: FileOperation
    public let options: ConversionOptions
    public init(inputs: [URL], operation: FileOperation, options: ConversionOptions) {
        self.inputs = inputs; self.operation = operation; self.options = options
    }
    public func canRetry(after state: ConversionJobState) -> Bool {
        (state == .failed || state == .cancelled) && !operation.id.hasPrefix("action.")
    }
}

public struct ConversionProgress: Sendable {
    public enum Phase: Sendable { case preparing, converting, publishing, finished }
    public let phase: Phase
    public let completedFiles: Int
    public let totalFiles: Int
    public let fileFraction: Double?
    public var fractionCompleted: Double? {
        if phase == .finished { return 1 }
        guard phase == .converting, totalFiles > 0, let value = fileFraction, value.isFinite else { return nil }
        // Conversion completion is not file publication. Never display success early.
        return min(0.99, max(0, (Double(completedFiles) + min(1, max(0, value))) / Double(totalFiles)))
    }
}

/// Per-job scope prevents simultaneous CLI jobs from sharing counters.
enum ConversionProgressScope {
    @TaskLocal static var reporter: ConversionProgressReporter?
    static func begin(_ input: URL) { reporter?.begin(input) }
    static func complete(_ input: URL) { reporter?.complete(input) }
}

final class ConversionProgressReporter: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private let inputs: Set<URL>
    private let handler: @Sendable (ConversionProgress) -> Void
    private var completed = Set<URL>()
    private var active: URL?
    private var fraction: Double?
    private var phase: ConversionProgress.Phase = .preparing
    init(inputs: [URL], handler: @escaping @Sendable (ConversionProgress) -> Void) {
        self.inputs = Set(inputs.map { $0.standardizedFileURL.resolvingSymlinksInPath() }); self.handler = handler
    }
    func setPhase(_ value: ConversionProgress.Phase) {
        lock.lock(); defer { lock.unlock() }
        phase = value; fraction = nil
        if value == .publishing || value == .finished { completed = inputs }
        emit()
    }
    func begin(_ input: URL) {
        lock.lock(); defer { lock.unlock() }
        let input = input.standardizedFileURL.resolvingSymlinksInPath()
        guard inputs.contains(input), phase == .converting else { return }
        active = input; fraction = nil; emit()
    }
    func complete(_ input: URL) {
        lock.lock(); defer { lock.unlock() }
        let input = input.standardizedFileURL.resolvingSymlinksInPath()
        guard inputs.contains(input), phase == .converting else { return }
        completed.insert(input); active = nil; fraction = nil; emit()
    }
    func updateFraction(_ value: Double) {
        lock.lock(); defer { lock.unlock() }
        guard active != nil, phase == .converting, value.isFinite else { return }
        let next = min(1, max(fraction ?? 0, value))
        guard fraction == nil || next - fraction! >= 0.005 || next == 1 else { return }
        fraction = next; emit()
    }
    func resetAttempt() {
        lock.lock(); defer { lock.unlock() }
        guard phase == .converting else { return }
        completed.removeAll(); active = nil; fraction = nil; emit()
    }
    private func emit() {
        handler(ConversionProgress(phase: phase, completedFiles: completed.count, totalFiles: inputs.count, fileFraction: fraction))
    }
}

/// Parse only bounded numeric progress records; log text and paths are not retained.
final class FFmpegProgressParser: @unchecked Sendable {
    private var buffer = Data()
    private var droppingLine = false
    private let duration: Double?
    private let report: @Sendable (Double) -> Void
    private let lock = NSLock()
    init(duration: Double?, report: @escaping @Sendable (Double) -> Void) {
        self.duration = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }; self.report = report
    }
    var bufferedByteCount: Int { lock.lock(); defer { lock.unlock() }; return buffer.count }
    func consume(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        guard let duration else { return }
        for byte in data {
            if byte == 10 {
                if !droppingLine {
                    let line = String(decoding: buffer, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    if line.hasPrefix("out_time_us="), let time = Double(line.dropFirst(12)), time.isFinite, time >= 0 {
                        report(min(1, time / 1_000_000 / duration))
                    }
                }
                buffer.removeAll(keepingCapacity: true); droppingLine = false
            } else if !droppingLine {
                if buffer.count < 4096 { buffer.append(byte) }
                else { buffer.removeAll(keepingCapacity: true); droppingLine = true }
            }
        }
    }
}
