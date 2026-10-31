import AppKit
import ApplicationServices

// Test-only reader. Never requests/grants permission or writes AX attributes.
// The normal CI launcher, not the sandboxed XCTest runner, owns this process.
private let reviewIdentifier = "app.lemulip.NativeUIReview"

private struct InspectionFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func attribute(_ element: AXUIElement, _ name: String) throws -> CFTypeRef? {
    var result: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(element, name as CFString, &result)
    switch status {
    case .success: return result
    case .attributeUnsupported, .noValue: return nil
    default: throw InspectionFailure("AX read failed for \(name): \(status.rawValue)")
    }
}

@MainActor
private func snapshot(path: String) throws -> [String: Any] {
    guard AXIsProcessTrusted() else {
        throw InspectionFailure("The read-only helper has no Accessibility permission; inspection is blocked")
    }
    let expected = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
    guard expected.lastPathComponent == "Lemulip Native UI Review.app" else {
        throw InspectionFailure("Only the separately staged UI review application is allowed")
    }
    let instances = NSRunningApplication.runningApplications(withBundleIdentifier: reviewIdentifier)
    guard instances.count == 1, let app = instances.first,
          app.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == expected,
          !app.isTerminated else {
        throw InspectionFailure("Expected exactly the staged review application, not another app or installed copy")
    }
    let root = AXUIElementCreateApplication(app.processIdentifier)
    guard AXUIElementSetMessagingTimeout(root, 0.5) == .success else {
        throw InspectionFailure("Could not bound AX messaging time")
    }
    var pending = [root]
    var visited: [AXUIElement] = []
    var nodes: [[String: Any]] = []
    while let element = pending.popLast() {
        if visited.contains(where: { CFEqual($0, element) }) { continue }
        guard visited.count < 512 else { throw InspectionFailure("AX hierarchy exceeded the review limit") }
        visited.append(element)
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid == app.processIdentifier else {
            throw InspectionFailure("Refusing an accessibility element outside the staged process")
        }
        let role = try attribute(element, kAXRoleAttribute) as? String
        if role == kAXSliderRole || role == kAXTextFieldRole {
            var node: [String: Any] = ["role": role!]
            for key in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueDescriptionAttribute, kAXIdentifierAttribute] {
                if let value = try attribute(element, key) as? String {
                    guard value.count <= 2048 else { throw InspectionFailure("AX attribute exceeds review size limit") }
                    node[key] = value
                }
            }
            if let value = try attribute(element, kAXValueAttribute) {
                if let number = value as? NSNumber { node["value"] = number }
                else if let text = value as? String, text.count <= 2048 { node["value"] = text }
            }
            if let enabled = try attribute(element, kAXEnabledAttribute) as? NSNumber { node["enabled"] = enabled.boolValue }
            nodes.append(node)
        }
        if let children = try attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            pending.append(contentsOf: children)
        }
    }
    return ["schema": 1, "trusted": true, "bundleIdentifier": reviewIdentifier,
            "applicationPath": expected.path, "pid": app.processIdentifier,
            "nodes": nodes, "truncated": false, "visitedNodes": visited.count]
}

do {
    guard CommandLine.arguments.count == 2 else { throw InspectionFailure("Expected only the fixed review bundle path") }
    let record = try snapshot(path: CommandLine.arguments[1])
    let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([10]))
} catch {
    let record: [String: Any] = ["schema": 1, "ok": false, "trusted": AXIsProcessTrusted(), "error": String(describing: error)]
    if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
        FileHandle.standardOutput.write(data)
    }
    exit(1)
}
