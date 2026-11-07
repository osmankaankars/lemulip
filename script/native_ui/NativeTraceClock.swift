import Darwin
import Foundation
import OSLog

// A synchronous, input-free clock calibration helper. This process reads boot
// metadata and clocks, emits one public log marker, and writes one JSON line.
// It does not initialize AppKit, request permissions, or configure logging.
// Usage: NativeTraceClock --phase before|after --nonce <32 lowercase hex digits>
private enum TraceClockIssue: String, Error {
    case arguments = "invalid-arguments"
    case processIdentity = "invalid-process-identity"
    case bootRead = "boot-uuid-read-failed"
    case bootValue = "invalid-boot-uuid"
    case timebase = "invalid-mach-timebase"
    case clockValue = "invalid-clock-value"
    case clockOrder = "invalid-clock-order"
    case outputLimit = "output-limit"
}

private struct ClockReceipt: Encodable {
    let schema = 1
    let phase: String
    let nonce: String
    let pid: Int
    let executablePath: String
    let bootUUID: String
    let machTimebaseNumer: UInt32
    let machTimebaseDenom: UInt32

    let absoluteBeforeUptime: UInt64
    let continuousBeforeUptime: UInt64
    let systemUptimeSample: Double
    let continuousAfterUptime: UInt64
    let absoluteAfterUptime: UInt64

    let absoluteBeforeLog: UInt64
    let continuousBeforeLog: UInt64
    let systemUptimeBeforeLog: Double
    let wallBeforeLogUnixSeconds: Double
    let wallAfterLogUnixSeconds: Double
    let systemUptimeAfterLog: Double
    let continuousAfterLog: UInt64
    let absoluteAfterLog: UInt64

    func validate() throws {
        let absolute = [absoluteBeforeUptime, absoluteAfterUptime, absoluteBeforeLog, absoluteAfterLog]
        let continuous = [continuousBeforeUptime, continuousAfterUptime, continuousBeforeLog, continuousAfterLog]
        let uptime = [systemUptimeSample, systemUptimeBeforeLog, systemUptimeAfterLog]
        let wall = [wallBeforeLogUnixSeconds, wallAfterLogUnixSeconds]
        guard absolute.allSatisfy({ $0 > 0 }), continuous.allSatisfy({ $0 > 0 }),
              (uptime + wall).allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw TraceClockIssue.clockValue
        }
        // Check each clock family separately. No shared epoch, tick scale, or
        // relationship between the absolute and continuous clocks is assumed.
        guard zip(absolute, absolute.dropFirst()).allSatisfy({ $0.0 <= $0.1 }),
              zip(continuous, continuous.dropFirst()).allSatisfy({ $0.0 <= $0.1 }),
              zip(uptime, uptime.dropFirst()).allSatisfy({ $0.0 <= $0.1 }),
              wallBeforeLogUnixSeconds <= wallAfterLogUnixSeconds else {
            throw TraceClockIssue.clockOrder
        }
    }
}

private func bootUUID() throws -> String {
    var length = 0
    guard sysctlbyname("kern.bootsessionuuid", nil, &length, nil, 0) == 0,
          length > 1, length <= 128 else {
        throw TraceClockIssue.bootRead
    }
    var bytes = [UInt8](repeating: 0, count: length)
    var actualLength = length
    let result = bytes.withUnsafeMutableBytes { buffer in
        sysctlbyname("kern.bootsessionuuid", buffer.baseAddress, &actualLength, nil, 0)
    }
    guard result == 0, actualLength > 1, actualLength <= bytes.count else {
        throw TraceClockIssue.bootRead
    }
    let value = bytes.prefix(actualLength)
    guard value.last == 0, !value.dropLast().contains(0),
          let text = String(bytes: value.dropLast(), encoding: .utf8), text.utf8.count == 36,
          let uuid = UUID(uuidString: text), uuid.uuidString.caseInsensitiveCompare(text) == .orderedSame else {
        throw TraceClockIssue.bootValue
    }
    return uuid.uuidString
}

private func receipt() throws -> ClockReceipt {
    let arguments = CommandLine.arguments
    guard arguments.count == 5, arguments[1] == "--phase", arguments[3] == "--nonce",
          arguments[2] == "before" || arguments[2] == "after",
          arguments[4].utf8.count == 32,
          arguments[4].utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
        throw TraceClockIssue.arguments
    }
    let phase = arguments[2]
    let nonce = arguments[4]
    let pid = Int(getpid())
    guard pid > 0, let executableURL = Bundle.main.executableURL else {
        throw TraceClockIssue.processIdentity
    }
    let executablePath = executableURL.resolvingSymlinksInPath().standardizedFileURL.path
    guard executablePath.hasPrefix("/"), executablePath.utf8.count <= 4096 else {
        throw TraceClockIssue.processIdentity
    }
    let boot = try bootUUID()
    var timebase = mach_timebase_info_data_t(numer: 0, denom: 0)
    guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.numer > 0, timebase.denom > 0 else {
        throw TraceClockIssue.timebase
    }
    let logger = Logger(subsystem: "app.lemulip.NativeTraceClock", category: "calibration")

    // Keep this acquisition order explicit. The raw UInt64 ticks are retained
    // for empirical matching to the timestamp in the actual log record.
    let absoluteBeforeUptime = mach_absolute_time()
    let continuousBeforeUptime = mach_continuous_time()
    let systemUptimeSample = ProcessInfo.processInfo.systemUptime
    let continuousAfterUptime = mach_continuous_time()
    let absoluteAfterUptime = mach_absolute_time()

    let absoluteBeforeLog = mach_absolute_time()
    let continuousBeforeLog = mach_continuous_time()
    let systemUptimeBeforeLog = ProcessInfo.processInfo.systemUptime
    let wallBeforeLogUnixSeconds = Date().timeIntervalSince1970
    logger.notice("LEMULIP_NATIVE_TRACE_CLOCK \(nonce, privacy: .public) \(phase, privacy: .public)")
    let wallAfterLogUnixSeconds = Date().timeIntervalSince1970
    let systemUptimeAfterLog = ProcessInfo.processInfo.systemUptime
    let continuousAfterLog = mach_continuous_time()
    let absoluteAfterLog = mach_absolute_time()

    let result = ClockReceipt(phase: phase, nonce: nonce, pid: pid, executablePath: executablePath,
        bootUUID: boot, machTimebaseNumer: timebase.numer, machTimebaseDenom: timebase.denom,
        absoluteBeforeUptime: absoluteBeforeUptime, continuousBeforeUptime: continuousBeforeUptime,
        systemUptimeSample: systemUptimeSample, continuousAfterUptime: continuousAfterUptime,
        absoluteAfterUptime: absoluteAfterUptime, absoluteBeforeLog: absoluteBeforeLog,
        continuousBeforeLog: continuousBeforeLog, systemUptimeBeforeLog: systemUptimeBeforeLog,
        wallBeforeLogUnixSeconds: wallBeforeLogUnixSeconds, wallAfterLogUnixSeconds: wallAfterLogUnixSeconds,
        systemUptimeAfterLog: systemUptimeAfterLog, continuousAfterLog: continuousAfterLog,
        absoluteAfterLog: absoluteAfterLog)
    try result.validate()
    return result
}

@main
private enum NativeTraceClock {
    static func main() {
        do {
            let result = try receipt()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            var data = try encoder.encode(result)
            guard data.count < 16 * 1024 else { throw TraceClockIssue.outputLimit }
            data.append(0x0a)
            try FileHandle.standardOutput.write(contentsOf: data)
        } catch {
            let code = (error as? TraceClockIssue)?.rawValue ?? "serialization-or-output-failed"
            try? FileHandle.standardError.write(contentsOf: Data(("NativeTraceClock: \(code)\n").utf8))
            Darwin.exit(2)
        }
    }
}
