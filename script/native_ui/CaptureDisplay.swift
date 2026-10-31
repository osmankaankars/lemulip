import AppKit
import CoreGraphics
import Foundation

// Public display modes only. Never create an invented Retina bitmap or change
// privacy grants. The hosted runner's display is restored after screenshots.
let directory = URL(fileURLWithPath: CommandLine.arguments[2])
let recordURL = directory.appendingPathComponent("display.json")
let id = CGMainDisplayID()
let modes = (CGDisplayCopyAllDisplayModes(id, [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary) as? [CGDisplayMode]) ?? []
if CommandLine.arguments[1] == "restore" {
    let record = try JSONSerialization.jsonObject(with: Data(contentsOf: recordURL)) as! [String: Any]
    if let number = record["originalModeID"] as? NSNumber,
       let original = modes.first(where: { $0.ioDisplayModeID == number.uint32Value }) {
        let result = CGDisplaySetDisplayMode(id, original, nil)
        print("Display restoration:", result.rawValue)
        if result != .success { exit(1) }
    }
} else {
    guard let original = CGDisplayCopyDisplayMode(id) else { exit(1) }
    let usable = modes.filter { $0.width >= 1024 && $0.height >= 768 && $0.isUsableForDesktopGUI() }
    let highDensity = usable.filter { $0.pixelWidth >= 2 * $0.width && $0.pixelHeight >= 2 * $0.height }
    let candidate = highDensity.sorted { $0.width * $0.height < $1.width * $1.height }.first
        ?? usable.filter { $0.width >= 1280 && $0.height >= 800 }.sorted { $0.width * $0.height < $1.width * $1.height }.first
    let result = candidate.map { CGDisplaySetDisplayMode(id, $0, nil).rawValue }
    Thread.sleep(forTimeInterval: 1)
    let current = CGDisplayCopyDisplayMode(id) ?? original
    func describe(_ mode: CGDisplayMode) -> [String: Any] {
        ["id": mode.ioDisplayModeID, "width": mode.width, "height": mode.height,
         "pixelWidth": mode.pixelWidth, "pixelHeight": mode.pixelHeight]
    }
    var record: [String: Any] = ["originalModeID": original.ioDisplayModeID,
        "original": describe(original), "selected": describe(current),
        "offeredModes": modes.map(describe), "offeredHighDensity": !highDensity.isEmpty,
        "method": "Public CGDisplayCopyAllDisplayModes / CGDisplaySetDisplayMode",
        "requiresScreenshotGeometryVerification": true]
    if let result { record["modeChangeResult"] = result }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]).write(to: recordURL)
    print(String(data: try JSONSerialization.data(withJSONObject: record, options: .sortedKeys), encoding: .utf8)!)
}
