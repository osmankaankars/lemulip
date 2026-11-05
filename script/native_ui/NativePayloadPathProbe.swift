import Foundation
import Darwin

// Read-only Foundation diagnostics for this fixed payload. No AppKit or input APIs.
@main
private struct NativePayloadPathProbe {
    static func optional(_ value: Bool?) -> Any { value.map { $0 as Any } ?? NSNull() }

    static func main() {
        guard CommandLine.arguments.count == 4,
              ["runner-temp", "private-var", "var-alias"].contains(CommandLine.arguments[1]) else { exit(2) }
        let label = CommandLine.arguments[1]
        let proposed = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let destination = URL(fileURLWithPath: CommandLine.arguments[3])
        var result: [String: Any] = ["schema": 1, "label": label, "status": "ERROR",
                                    "inputEventsSent": 0, "entryLimit": 250,
                                    "scope": "Path spelling and payload metadata only; not App Translocation reproduction."]
        do {
            guard proposed.lastPathComponent == "lemulip-native-ui" else { throw CocoaError(.fileReadInvalidFileName) }
            let root = proposed.standardizedFileURL.resolvingSymlinksInPath()
            let manifestURL = root.appendingPathComponent("kit-manifest.json")
            let attributes = try manifestURL.resourceValues(forKeys: [.fileSizeKey])
            guard let size = attributes.fileSize, size <= 2_097_152 else { throw CocoaError(.fileReadTooLarge) }
            let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
            guard let files = manifest?["files"] as? [String: String] else { throw CocoaError(.fileReadCorruptFile) }
            result["root"] = [
                "proposedEqualsStandardized": proposed.path == proposed.standardizedFileURL.path,
                "proposedEqualsResolved": proposed.path == proposed.resolvingSymlinksInPath().path,
                "standardizedEqualsResolved": proposed.standardizedFileURL.path == proposed.resolvingSymlinksInPath().path,
                "proposedHasPrivateVarPrefix": proposed.path.hasPrefix("/private/var/"),
                "verifierRootHasPrivateVarPrefix": root.path.hasPrefix("/private/var/"),
                "verifierRootHasVarPrefix": root.path.hasPrefix("/var/")]
            let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            var enumerationFailed = false
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                options: [], errorHandler: { _, _ in enumerationFailed = true; return false }) else {
                throw CocoaError(.fileReadUnknown)
            }
            var entries: [[String: Any]] = []
            var limited = false
            for case let entry as URL in enumerator {
                if entries.count == 250 { limited = true; break }
                let values = try entry.resourceValues(forKeys: Set(keys))
                if values.isSymbolicLink == true { enumerator.skipDescendants() }
                let components = entry.pathComponents
                let anchor = components.lastIndex(of: "lemulip-native-ui")
                let relative = anchor.map { components.dropFirst($0 + 1).joined(separator: "/") } ?? "(outside-payload)"
                guard relative.utf8.count <= 1_024 else { throw CocoaError(.fileReadInvalidFileName) }
                entries.append([
                    "relativePath": relative,
                    "isDirectory": optional(values.isDirectory), "isRegularFile": optional(values.isRegularFile),
                    "isSymbolicLink": optional(values.isSymbolicLink),
                    "standardizedEqualsResolved": entry.standardizedFileURL.path == entry.resolvingSymlinksInPath().path,
                    "rawPrefixMatchesVerifierRoot": entry.path.hasPrefix(root.path + "/"),
                    "resolvedPrefixMatchesResolvedRoot": entry.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/"),
                    "inManifest": files[relative] != nil,
                    "isManifest": relative == "kit-manifest.json",
                    "unexpectedRegularFile": values.isRegularFile == true && relative != "kit-manifest.json" && files[relative] == nil,
                    "isDSStore": entry.lastPathComponent == ".DS_Store",
                    "isAppleDouble": entry.lastPathComponent.hasPrefix("._")])
            }
            result["entries"] = entries
            result["entryLimitHit"] = limited
            result["enumerationFailed"] = enumerationFailed
            result["status"] = "OBSERVED"
        } catch {
            let value = error as NSError
            result["errorDomain"] = value.domain
            result["errorCode"] = value.code
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: destination, options: .withoutOverwriting)
        } catch { exit(1) }
    }
}
