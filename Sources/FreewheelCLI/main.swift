import Foundation
import FreewheelCore

let usage = """
Lemulip — free, local file conversion

Usage:
  lemulip list <file> [--mode convert|tools|actions]
  lemulip convert <format> <file>... [--output <directory>]
  lemulip run <operation-id> <file>... [options]
  lemulip engines

Options:
  --output PATH       Existing destination directory (default: beside original)
  --quality 0.15...1   Image/media quality
  --size PIXELS       Maximum image/video dimension
  --width PIXELS      Center-crop width
  --height PIXELS     Center-crop height
  --start SECONDS     Trim start
  --end SECONDS       Trim end
  --pages 1,3-5       PDF pages to extract
  --rotate 90         Clockwise rotation (90, 180, 270)
  --speed 2           Playback speed multiplier
  --volume 1.5        Audio volume multiplier

Examples:
  lemulip convert png photo.heic
  lemulip convert docx notes.txt
  lemulip convert xlsx table.csv
  lemulip run pdf.merge first.pdf second.pdf
  lemulip run media.trim video.mp4 --start 5 --end 25
  lemulip run archive.extract example.zip

Conversions never replace the original. No files are uploaded.
TXT to DOCX is built into macOS. CSV/TSV to XLSX is built in on both platforms:
one worksheet per file, with every value kept as text (no formula or date inference).
Image/PDF/native media operations require macOS; portable text/archive and
installed external engines can also be used on Linux.
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("Lemulip: " + message + "\n").utf8))
    exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())
if arguments.isEmpty || arguments.contains("--help") || arguments.contains("-h") { print(usage); exit(0) }
let command = arguments.removeFirst()
if command == "engines" {
    for name in ["ffmpeg", "imagemagick", "libreoffice", "pandoc"] { print("\(name): \(EngineLocator.find(name)?.path ?? "not installed")") }
    exit(0)
}

var options = ConversionOptions()
var mode = WheelMode.convert
var positional: [String] = []
var index = 0
while index < arguments.count {
    let value = arguments[index]
    if value.hasPrefix("--") {
        guard index + 1 < arguments.count else { fail("Missing value for \(value)") }
        let next = arguments[index + 1]
        switch value {
        case "--output": options.destinationDirectory = URL(fileURLWithPath: next, isDirectory: true)
        case "--quality": guard let n = Double(next), n.isFinite, (0.15...1).contains(n) else { fail("Invalid quality") }; options.quality = n
        case "--size": guard let n = Int(next), (16...16000).contains(n) else { fail("Invalid maximum dimension") }; options.maxDimension = n
        case "--width": guard let n = Int(next), (1...16000).contains(n) else { fail("Invalid width") }; options.width = n
        case "--height": guard let n = Int(next), (1...16000).contains(n) else { fail("Invalid height") }; options.height = n
        case "--start": guard let n = Double(next), n.isFinite, n >= 0 else { fail("Invalid start time") }; options.startSeconds = n
        case "--end": guard let n = Double(next), n.isFinite, n > 0 else { fail("Invalid end time") }; options.endSeconds = n
        case "--pages": options.pageRange = next
        case "--rotate": guard let n = Int(next), [90,180,270].contains(n) else { fail("Rotation must be 90, 180, or 270") }; options.rotationDegrees = n
        case "--speed": guard let n = Double(next), n.isFinite, (0.5...4).contains(n) else { fail("Speed must be between 0.5 and 4") }; options.speedMultiplier = n
        case "--volume": guard let n = Double(next), n.isFinite, (0...3).contains(n) else { fail("Volume must be between 0 and 3") }; options.volumeMultiplier = n
        case "--mode": guard let n = WheelMode(rawValue: next) else { fail("Mode must be convert, tools, or actions") }; mode = n
        default: fail("Unknown option: \(value)")
        }
        index += 2
    } else { positional.append(value); index += 1 }
}
guard !positional.isEmpty else { fail("No files or operation supplied. Use --help.") }
if command == "list" {
    let urls = positional.map { URL(fileURLWithPath: $0) }
    for operation in Catalog.operations(for: urls, mode: mode) {
        let dependency = operation.dependency.map { EngineLocator.isAvailable($0) ? "" : " [needs \($0)]" } ?? ""
        print("\(operation.id)\t\(operation.title)\(dependency)")
    }
    exit(0)
}
guard command == "convert" || command == "run" else { fail("Unknown command: \(command)") }
let requested = positional.removeFirst()
guard !positional.isEmpty else { fail("Select at least one input file") }
let urls = positional.map { URL(fileURLWithPath: $0) }
let operationID = command == "convert" ? "convert.\(Catalog.normalizedExtension(requested))" : requested
if operationID.hasPrefix("action.") { fail("Finder, AirDrop, and shelf actions are available in the desktop app.") }
let known = (Catalog.operations(for: urls, mode: .convert) + Catalog.operations(for: urls, mode: .tools)).first { $0.id == operationID }
guard let operation = known else { fail("This operation is not available for the selected files. Run lemulip list first.") }
if operationID == "pdf.compress" { FileHandle.standardError.write(Data("Notice: PDF compression flattens pages to images; links, forms, text selection, and signatures are not retained in the new copy. Originals are preserved.\n".utf8)) }
if operationID == "media.trim" && options.endSeconds <= options.startSeconds { fail("End time must be after start time") }
let runner = ConversionEngine()
do {
    let result = try await runner.run(inputs: urls, operation: operation, options: options)
    for output in result.outputs { print(output.path) }
    if let note = result.note { FileHandle.standardError.write(Data((note + "\n").utf8)) }
} catch { fail(error.localizedDescription) }
