import Foundation

enum LibraryLayout {
    static let rootDirectoryName = "Paper Library"
    static let waitingDirectoryName = "Waiting"
    static let papersDirectoryName = "Papers"
    static let catalogDirectoryName = "Catalog"
    static let automationDirectoryName = "Automation"

    static func managedRoot(fileManager: FileManager = .default) throws -> URL {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "The Application Support folder is unavailable.",
            ])
        }
        return applicationSupport.appendingPathComponent(rootDirectoryName, isDirectory: true)
    }

    static func waitingURL(in root: URL) -> URL {
        root.appendingPathComponent(waitingDirectoryName, isDirectory: true)
    }

    static func papersURL(in root: URL) -> URL {
        root.appendingPathComponent(papersDirectoryName, isDirectory: true)
    }

    static func catalogURL(in root: URL) -> URL {
        root.appendingPathComponent(catalogDirectoryName, isDirectory: true)
    }

    static func catalogCSVURL(in root: URL) -> URL {
        catalogURL(in: root).appendingPathComponent("papers.csv", isDirectory: false)
    }

    static func prepareManagedLibrary(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) throws -> URL {
        let root = try managedRoot(fileManager: fileManager)
        return try prepareLibrary(at: root, bundle: bundle, fileManager: fileManager)
    }

    static func prepareLibrary(
        at root: URL,
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) throws -> URL {
        for directory in [
            root,
            waitingURL(in: root),
            papersURL(in: root),
            catalogURL(in: root),
            root.appendingPathComponent(automationDirectoryName, isDirectory: true),
        ] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        let csvURL = catalogCSVURL(in: root)
        if !fileManager.fileExists(atPath: csvURL.path) {
            try (CSVCodec.headers.joined(separator: ",") + "\n")
                .write(to: csvURL, atomically: true, encoding: .utf8)
        }

        try installBundledResources(into: root, bundle: bundle, fileManager: fileManager)
        return root
    }

    private static func installBundledResources(
        into root: URL,
        bundle: Bundle,
        fileManager: FileManager
    ) throws {
        guard let seedRoot = bundle.resourceURL?
            .appendingPathComponent("LibrarySeed", isDirectory: true),
              fileManager.fileExists(atPath: seedRoot.path)
        else { return }

        let relativeFiles = [
            "Automation/PAPER_LIBRARY_EDITOR.md",
            "Automation/PAPER_ORGANIZER.md",
            "Automation/library-command-schema.json",
            "Automation/paper-organizer.mjs",
        ]
        for relativePath in relativeFiles {
            let source = seedRoot.appendingPathComponent(relativePath, isDirectory: false)
            guard fileManager.fileExists(atPath: source.path) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [
                    NSLocalizedDescriptionKey: "The app is missing the bundled resource \(relativePath).",
                ])
            }
            let destination = root.appendingPathComponent(relativePath, isDirectory: false)
            let data = try Data(contentsOf: source)
            try data.write(to: destination, options: .atomic)
        }
    }
}
