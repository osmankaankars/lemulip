import Foundation

/// Original Lemulip cue, including the generated samples, under the repository's
/// MIT license. No recording, stock sound, or third-party sample is embedded.
/// This deterministic recipe makes a 60 ms, mono, 16-bit PCM WAVE with no metadata.
/// Its duration and envelope are engineering bounds, not a claim of an ear audition.
enum SelectionCue {
    static let sampleRate = 44_100
    static let frameCount = 2_646

    static func waveData() -> Data {
        let duration = Double(frameCount) / Double(sampleRate)
        var data = Data()
        data.reserveCapacity(44 + frameCount * 2)
        data.append(contentsOf: "RIFF".utf8)
        append(UInt32(36 + frameCount * 2), to: &data)
        data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data) // Linear PCM.
        append(UInt16(1), to: &data) // Mono.
        append(UInt32(sampleRate), to: &data)
        append(UInt32(sampleRate * 2), to: &data)
        append(UInt16(2), to: &data)
        append(UInt16(16), to: &data)
        data.append(contentsOf: "data".utf8)
        append(UInt32(frameCount * 2), to: &data)

        for frame in 0..<frameCount {
            let time = Double(frame) / Double(sampleRate)
            // Rounded 4 ms attack, a low descending body, and a short damped tail.
            // The quiet upper partial adds definition without a notification bell.
            let attack = pow(sin(min(1, time / 0.004) * .pi / 2), 2)
            let tail = pow(1 - time / duration, 2) * exp(-time / 0.014)
            let phase = 2 * Double.pi * (740 * time - 1_000 * time * time)
            let body = 0.86 * sin(phase) + 0.14 * sin(phase * 2.4)
            let value = Int16((0.17 * attack * tail * body * Double(Int16.max)).rounded())
            append(UInt16(bitPattern: value), to: &data)
        }
        return data
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}

/// System Sound Services reads from a URL. Keep the tiny generated file private
/// and alive for exactly as long as the sound object, then remove its directory.
final class SelectionCueFile {
    let url: URL
    private let directory: URL

    init(parent: URL = FileManager.default.temporaryDirectory) throws {
        directory = parent.appendingPathComponent("Lemulip-Selection-Cue-" + UUID().uuidString,
                                                  isDirectory: true)
        url = directory.appendingPathComponent("selection.wav")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        do {
            try SelectionCue.waveData().write(to: url, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}
