import CryptoKit
import Darwin
import Foundation

/// Keep user PDFs in Documents while preserving the catalog's Papers/... paths.
/// The private Papers entry is a link, not a second copy of the user's PDFs.
enum PaperStorage {
    static func defaultPapersURL(fileManager: FileManager = .default) throws -> URL {
        let documents = try fileManager.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false
        )
        return documents.appendingPathComponent("Paper Library/Papers", isDirectory: true)
    }

    @discardableResult
    static func prepare(
        in root: URL,
        at destination: URL,
        lockDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> Bool {
        let source = LibraryLayout.papersURL(in: root)
        let attributes = try fileManager.attributesOfItem(atPath: source.path)
        if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw StorageError.missingPDFDirectory(source.resolvingSymlinksInPath().path)
            }
            return false
        }
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw StorageError.invalidPDFDirectory
        }

        let target = destination.standardizedFileURL
        guard !target.path.hasPrefix(root.standardizedFileURL.path + "/") else {
            throw StorageError.invalidPDFDirectory
        }
        let lock = try lockDirectory ?? organizerLockDirectory(in: root, fileManager: fileManager)
        try acquireLock(at: lock, fileManager: fileManager)
        defer { try? fileManager.removeItem(at: lock) }

        let sourceContents = try fileManager.contentsOfDirectory(atPath: source.path)
        let targetExists = fileManager.fileExists(atPath: target.path)
        if targetExists {
            let values = try target.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true, sourceContents.isEmpty else {
                throw StorageError.destinationConflict(target.path)
            }
            // Recover a move interrupted just before the private link was made,
            // but never adopt an unrelated existing folder into a new library.
            let targetContents = try fileManager.contentsOfDirectory(atPath: target.path)
            if !targetContents.isEmpty {
                let papers = try CSVCodec.decode(String(contentsOf: LibraryLayout.catalogCSVURL(in: root), encoding: .utf8))
                guard !papers.isEmpty, papers.allSatisfy({ paper in
                    let relative = paper.file.split(separator: "/").dropFirst().joined(separator: "/")
                    return fileManager.fileExists(atPath: target.appendingPathComponent(relative).path)
                }) else { throw StorageError.destinationConflict(target.path) }
            }
            try fileManager.removeItem(at: source) // Verified empty directory.
        } else {
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: source, to: target)
        }

        do {
            try fileManager.createSymbolicLink(at: source, withDestinationURL: target)
            guard source.resolvingSymlinksInPath().standardizedFileURL == target.resolvingSymlinksInPath().standardizedFileURL else {
                throw StorageError.invalidPDFDirectory
            }
        } catch {
            // Remove only a link we just created, then restore the original
            // directory. Never delete the target or merge/overwrite PDFs.
            if (try? fileManager.attributesOfItem(atPath: source.path)[.type] as? FileAttributeType) == .typeSymbolicLink {
                try? fileManager.removeItem(at: source)
            }
            if !targetExists {
                try? fileManager.moveItem(at: target, to: source)
            } else {
                try? fileManager.createDirectory(at: source, withIntermediateDirectories: false)
            }
            throw error
        }
        return true
    }

    static func requestSpotlightImport(at url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdimport")
        process.arguments = ["-i", url.resolvingSymlinksInPath().path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    private static func organizerLockDirectory(in root: URL, fileManager: FileManager) throws -> URL {
        // Matches repositoryId/platformPaths in paper-organizer.mjs.
        let digest = SHA256.hash(data: Data(root.standardizedFileURL.path.utf8))
        let id = digest.map { String(format: "%02x", $0) }.joined().prefix(12)
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return support.appendingPathComponent("PaperOrganizer/\(id)/on-demand-worker.lock", isDirectory: true)
    }

    private static func acquireLock(at lock: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: lock.deletingLastPathComponent(), withIntermediateDirectories: true)
        for _ in 0..<2 {
            if mkdir(lock.path, 0o700) == 0 {
                do {
                    let owner = try JSONSerialization.data(withJSONObject: ["pid": ProcessInfo.processInfo.processIdentifier])
                    try owner.write(to: lock.appendingPathComponent("owner.json"), options: .atomic)
                    return
                } catch {
                    try? fileManager.removeItem(at: lock)
                    throw error
                }
            }
            guard errno == EEXIST else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            let ownerData = try? Data(contentsOf: lock.appendingPathComponent("owner.json"))
            let owner = ownerData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let pid = (owner?["pid"] as? NSNumber)?.int32Value
            if let pid, pid > 0, kill(pid, 0) == 0 || errno == EPERM { throw StorageError.organizerBusy }
            let modified = try fileManager.attributesOfItem(atPath: lock.path)[.modificationDate] as? Date
            if owner == nil, let modified, Date().timeIntervalSince(modified) < 30 { throw StorageError.organizerBusy }
            try fileManager.removeItem(at: lock)
        }
        throw StorageError.organizerBusy
    }
}

private enum StorageError: LocalizedError {
    case organizerBusy
    case destinationConflict(String)
    case missingPDFDirectory(String)
    case invalidPDFDirectory

    var errorDescription: String? {
        switch self {
        case .organizerBusy:
            "Paper Organizer is still working. Reopen Paper Library after it finishes to move your PDFs to Documents."
        case .destinationConflict(let path):
            "The PDF folder at \(path) already exists. No PDFs were overwritten or merged. Move that folder elsewhere, then reopen Paper Library."
        case .missingPDFDirectory(let path):
            "The PDF folder is unavailable at \(path). Restore the folder, then reopen Paper Library."
        case .invalidPDFDirectory:
            "The PDF storage path is not a valid folder."
        }
    }
}
