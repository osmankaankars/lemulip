import Foundation
#if os(macOS)
import Darwin
#else
import Glibc
#endif

public enum OutputStore {
    public static func uniqueURL(in directory: URL, stem: String, extension fileExtension: String) -> URL {
        let base = safeStem(stem)
        let cleanedExtension = String(fileExtension.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ".") }.prefix(24)).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let suffix = cleanedExtension.isEmpty ? "" : ".\(cleanedExtension)"
        var number = 1
        while true {
            let filename = number == 1 ? base + suffix : "\(base) (\(number))\(suffix)"
            let candidate = directory.appendingPathComponent(filename)
            if !existsIncludingSymlink(candidate) { return candidate }
            number += 1
        }
    }

    static func safeStem(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:").union(.controlCharacters)
        let cleaned = value.components(separatedBy: forbidden).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        var shortened = String(cleaned.prefix(160))
        while shortened.utf8.count > 180 { shortened.removeLast() }
        return shortened.isEmpty || shortened == "." || shortened == ".." ? "Converted" : shortened
    }

    static func prepare(destination: URL) throws -> URL {
        guard destination.isFileURL else { throw FreewheelError.invalidInput("Choose a local output folder.") }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw FreewheelError.invalidInput("The output folder does not exist.")
        }
        let stage = destination.appendingPathComponent(".freewheel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return stage
    }

    /// Publishing regular files uses an atomic hard link so another file can never be replaced.
    static func publish(_ result: ConversionResult, from stage: URL, to destination: URL) throws -> ConversionResult {
        let rootPath = stage.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        var published: [URL] = []
        do {
            guard result.outputs.count <= 10_000 else { throw FreewheelError.operationFailed("The conversion produced too many files.") }
            for source in result.outputs {
                try Task.checkCancellation()
                let path = source.standardizedFileURL.path
                guard source.isFileURL, path.hasPrefix(rootPath), path != String(rootPath.dropLast()), source.resolvingSymlinksInPath().path == path else {
                    throw FreewheelError.operationFailed("The converter returned an invalid output location.")
                }
                try validateOutputTree(source)
                let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                let target: URL
                if values.isDirectory == true {
                    target = try reserveDirectory(in: destination, stem: source.lastPathComponent)
                    published.append(target)
                    for child in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                        try FileManager.default.moveItem(at: child, to: target.appendingPathComponent(child.lastPathComponent))
                    }
                } else {
                    target = try publishFile(source, destination: destination)
                    published.append(target)
                }
            }
            return ConversionResult(outputs: published, note: result.note)
        } catch {
            for output in published { try? FileManager.default.removeItem(at: output) }
            throw error
        }
    }

    private static func publishFile(_ source: URL, destination: URL) throws -> URL {
        for _ in 0..<10_000 {
            let candidate = uniqueURL(in: destination, stem: source.deletingPathExtension().lastPathComponent, extension: source.pathExtension)
            let code = source.path.withCString { sourcePath in candidate.path.withCString { link(sourcePath, $0) } }
            if code == 0 { return candidate }
            if errno == EEXIST { continue }
            if [EPERM, EOPNOTSUPP, ENOTSUP, EXDEV, ENOSYS, EMLINK].contains(errno) {
                if try copyFileExclusively(source, to: candidate) { return candidate }
                continue
            }
            throw FreewheelError.operationFailed("Could not save the converted file: \(String(cString: strerror(errno))).")
        }
        throw FreewheelError.operationFailed("Could not find an unused output filename.")
    }

    /// FAT/exFAT and some network volumes have no hard links. O_EXCL preserves the same no-overwrite guarantee.
    static func copyFileExclusively(_ source: URL, to target: URL) throws -> Bool {
        let input = source.path.withCString { open($0, O_RDONLY | O_NOFOLLOW) }
        guard input >= 0 else { throw FreewheelError.operationFailed("Could not read the staged output.") }
        defer { _ = close(input) }
        var info = stat()
        guard fstat(input, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw FreewheelError.operationFailed("The staged output is not a regular file.")
        }
        let output = target.path.withCString { open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600) }
        if output < 0 {
            if errno == EEXIST { return false }
            throw FreewheelError.operationFailed("Could not reserve a new output file: \(String(cString: strerror(errno))).")
        }
        var completed = false
        defer {
            _ = close(output)
            if !completed { _ = target.path.withCString { unlink($0) } }
        }
        var bytes = [UInt8](repeating: 0, count: 65_536)
        while true {
            try Task.checkCancellation()
            let count = bytes.withUnsafeMutableBytes { read(input, $0.baseAddress, $0.count) }
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw FreewheelError.operationFailed("Could not read a converted file while saving it.")
            }
            var offset = 0
            while offset < count {
                let written = bytes.withUnsafeBytes { write(output, $0.baseAddress!.advanced(by: offset), count - offset) }
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { throw FreewheelError.operationFailed("Could not save a converted file. Check available space in the output folder.") }
                offset += written
            }
        }
        completed = true
        return true
    }

    private static func reserveDirectory(in destination: URL, stem: String) throws -> URL {
        for _ in 0..<10_000 {
            let candidate = uniqueURL(in: destination, stem: stem, extension: "")
            let code = candidate.path.withCString { mkdir($0, 0o700) }
            if code == 0 { return candidate }
            if errno == EEXIST { continue }
            throw FreewheelError.operationFailed("Could not create the output folder: \(String(cString: strerror(errno))).")
        }
        throw FreewheelError.operationFailed("Could not find an unused output folder name.")
    }

    private static func validateOutputTree(_ root: URL) throws {
        func validate(_ url: URL) throws {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
            guard values.isSymbolicLink != true, values.isDirectory == true || values.isRegularFile == true else {
                throw FreewheelError.operationFailed("A converter produced an unsafe file type.")
            }
        }
        try validate(root)
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey]) {
            var count = 0
            for case let child as URL in enumerator {
                count += 1
                guard count <= 20_000 else { throw FreewheelError.operationFailed("The output folder contains too many files.") }
                try validate(child)
            }
        }
    }

    private static func existsIncludingSymlink(_ url: URL) -> Bool {
        var info = stat()
        return url.path.withCString { lstat($0, &info) } == 0
    }
}
