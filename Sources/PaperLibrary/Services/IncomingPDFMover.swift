import Foundation

struct PDFMoveFailure: Equatable {
    let source: URL
    let message: String
}

struct PDFMoveResult: Equatable {
    let moved: [URL]
    let failures: [PDFMoveFailure]

    var failureSummary: String {
        failures.map { "\($0.source.lastPathComponent): \($0.message)" }
            .joined(separator: "\n")
    }
}

enum IncomingPDFMover {
    static func move(
        _ sourceURLs: [URL],
        to waitingDirectoryURL: URL,
        excluding libraryRootURL: URL
    ) -> PDFMoveResult {
        let fileManager = FileManager.default
        let waitingDirectory = waitingDirectoryURL.standardizedFileURL
        let libraryRoot = libraryRootURL.standardizedFileURL
        var moved: [URL] = []
        var failures: [PDFMoveFailure] = []

        for sourceURL in sourceURLs {
            let source = sourceURL.standardizedFileURL
            let accessStarted = source.startAccessingSecurityScopedResource()
            defer {
                if accessStarted { source.stopAccessingSecurityScopedResource() }
            }

            do {
                guard source.isFileURL else {
                    throw MoveError.notLocal
                }
                guard source.pathExtension.caseInsensitiveCompare("pdf") == .orderedSame else {
                    throw MoveError.notPDF
                }
                let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else {
                    throw MoveError.notRegularFile
                }
                guard source != libraryRoot,
                      !source.path.hasPrefix(libraryRoot.path + "/") else {
                    throw MoveError.alreadyInLibrary
                }

                let destination = waitingDirectory.appendingPathComponent(
                    source.lastPathComponent,
                    isDirectory: false
                )
                guard !fileManager.fileExists(atPath: destination.path) else {
                    throw MoveError.nameConflict
                }

                try fileManager.moveItem(at: source, to: destination)
                moved.append(destination)
            } catch {
                failures.append(PDFMoveFailure(
                    source: source,
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                ))
            }
        }

        return PDFMoveResult(moved: moved, failures: failures)
    }
}

private enum MoveError: LocalizedError {
    case notLocal
    case notPDF
    case notRegularFile
    case alreadyInLibrary
    case nameConflict

    var errorDescription: String? {
        switch self {
        case .notLocal:
            "Only local files can be moved."
        case .notPDF:
            "Only PDF files can be moved."
        case .notRegularFile:
            "The selected item is not a regular file."
        case .alreadyInLibrary:
            "This PDF is already managed by Paper Library."
        case .nameConflict:
            "A PDF with the same filename is already waiting to be processed."
        }
    }
}
