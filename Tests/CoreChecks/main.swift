import Foundation
import PDFKit

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): message
        }
    }
}

func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw CheckFailure.failed(message) }
}

func fixturePaper() -> Paper {
    Paper(
        category: "Systems", subcategory: "Inference", venue: "ICML", year: "2026",
        track: "Main", workshop: "", presentation: "Oral",
        title: "A Title, with \"Quotes\"", authors: "Ada Lovelace, Alan Turing",
        affiliation: "Example University", summary: "A compact summary.",
        novelty: "A new mechanism.", site: "https://example.com/paper",
        addedAt: "2026-09-02 10:00:00", file: "Papers/Systems/A Title.pdf"
    )
}

final class SetupFileManager: FileManager, @unchecked Sendable {
    let support: URL
    var requestedDirectories: [FileManager.SearchPathDirectory] = []
    init(support: URL) { self.support = support; super.init() }
    override func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        requestedDirectories.append(directory)
        return [support]
    }
}

final class RejectedStorageLinkFileManager: FileManager, @unchecked Sendable {
    override func createSymbolicLink(at url: URL, withDestinationURL destinationURL: URL) throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}

func writeRecoveryPDF(at url: URL, title: String = "", author: String = "") throws -> Data {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let document = PDFDocument()
    document.insert(PDFPage(), at: 0)
    document.documentAttributes = [PDFDocumentAttribute.titleAttribute: title, PDFDocumentAttribute.authorAttribute: author]
    guard let data = document.dataRepresentation() else { throw CheckFailure.failed("Cannot create recovery PDF fixture") }
    try data.write(to: url)
    return data
}

do {
    let original = fixturePaper()
    let encoded = try CSVCodec.encode([original])
    let decoded = try CSVCodec.decode(encoded)
    try check(decoded == [original], "CSV round-trip changed paper metadata")
    try check(encoded.contains("\"A Title, with \"\"Quotes\"\"\""), "CSV quotes were not escaped")

    let row = "\"Systems\",\"\",\"arXiv\",2026,\"\",\"\",\"Preprint\",\"Title\",\"Author\",\"Lab\",\"Summary\",\"Novelty\",\"\",\"2026-09-02\",\"Papers/Systems/Title.pdf\""
    let crlfCatalog = CSVCodec.headers.joined(separator: ",") + "\r\n" + row + "\r\n"
    let crlfPapers = try CSVCodec.decode(crlfCatalog)
    try check(crlfPapers.first?.title == "Title", "CRLF catalog did not decode")

    let oldLayoutRow = row.replacingOccurrences(
        of: "Papers/Systems/Title.pdf",
        with: "Systems/Title.pdf"
    )
    let oldLayoutCatalog = CSVCodec.headers.joined(separator: ",") + "\n" + oldLayoutRow + "\n"
    do {
        _ = try CSVCodec.decode(oldLayoutCatalog)
        throw CheckFailure.failed("A catalog PDF outside Papers/ was accepted")
    } catch CatalogCSVError.invalidFile {
        // Expected.
    }

    let duplicateCatalog = CSVCodec.headers.joined(separator: ",") + "\n" + row + "\n" + row + "\n"
    do {
        _ = try CSVCodec.decode(duplicateCatalog)
        throw CheckFailure.failed("Duplicate PDF paths were accepted")
    } catch CatalogCSVError.duplicateFile {
        // Expected.
    }

    let invalidPresentationCatalog = CSVCodec.headers.joined(separator: ",") + "\n" +
        row.replacingOccurrences(of: "\"Preprint\"", with: "\"Talk\"") + "\n"
    do {
        _ = try CSVCodec.decode(invalidPresentationCatalog)
        throw CheckFailure.failed("An unsupported presentation value was accepted")
    } catch CatalogCSVError.invalidPresentation {
        // Expected.
    }

    let root = URL(fileURLWithPath: "/tmp/paper-library")
    var unsafe = original
    try check(unsafe.pdfURL(in: root) != nil, "Valid PDF path was rejected")
    unsafe.file = "../private.pdf"
    try check(unsafe.pdfURL(in: root) == nil, "Parent-directory path was accepted")
    unsafe.file = "/tmp/private.pdf"
    try check(unsafe.pdfURL(in: root) == nil, "Absolute PDF path was accepted")
    unsafe.file = "Systems/private.pdf"
    try check(unsafe.pdfURL(in: root) == nil, "A catalog PDF outside Papers/ was accepted")

    var invalid = original
    invalid.track = ""
    try check(invalid.validationError() == "A published paper needs a track.", "Track validation did not run")

    var unknownAffiliation = original
    unknownAffiliation.affiliation = ""
    try check(
        unknownAffiliation.validationError() == nil,
        "A paper without a known affiliation was rejected"
    )

    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let setupFiles = SetupFileManager(support: temporaryDirectory.appendingPathComponent("app-support"))
    try check(!LibraryLayout.hasExistingCatalog(fileManager: setupFiles), "A new library bypassed the access explanation")
    let setupRoot = try LibraryLayout.managedRoot(fileManager: setupFiles)
    try check(!FileManager.default.fileExists(atPath: setupRoot.path), "The startup probe created storage before consent")
    _ = try LibraryLayout.prepareLibrary(at: setupRoot)
    try check(LibraryLayout.hasExistingCatalog(fileManager: setupFiles), "An existing library was treated as first launch")
    try check(setupFiles.requestedDirectories.allSatisfy { $0 == .applicationSupportDirectory },
              "The startup probe requested Documents before explaining access")
    let library = temporaryDirectory.appendingPathComponent("library", isDirectory: true)
    _ = try LibraryLayout.prepareLibrary(at: library)
    let inbox = LibraryLayout.waitingURL(in: library)
    let downloads = temporaryDirectory.appendingPathComponent("downloads", isDirectory: true)
    let secondDownloads = temporaryDirectory.appendingPathComponent("second-downloads", isDirectory: true)
    try check(FileManager.default.fileExists(atPath: inbox.path), "Waiting directory was not created")
    try check(
        FileManager.default.fileExists(atPath: LibraryLayout.papersURL(in: library).path),
        "Papers directory was not created"
    )
    try check(
        FileManager.default.fileExists(atPath: LibraryLayout.catalogCSVURL(in: library).path),
        "Empty catalog was not created"
    )
    try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: secondDownloads, withIntermediateDirectories: true)

    let sourcePDF = downloads.appendingPathComponent("paper.pdf")
    try Data("%PDF-1.4 test".utf8).write(to: sourcePDF)
    let moveResult = IncomingPDFMover.move([sourcePDF], to: inbox, excluding: library)
    try check(moveResult.failures.isEmpty, "Valid PDF move failed")
    try check(!FileManager.default.fileExists(atPath: sourcePDF.path), "PDF was copied instead of moved")
    try check(FileManager.default.fileExists(atPath: inbox.appendingPathComponent("paper.pdf").path), "Moved PDF is missing")

    let conflictingPDF = secondDownloads.appendingPathComponent("paper.pdf")
    try Data("%PDF-1.4 conflict".utf8).write(to: conflictingPDF)
    let conflictResult = IncomingPDFMover.move([conflictingPDF], to: inbox, excluding: library)
    try check(conflictResult.failures.count == 1, "Duplicate filename was not rejected")
    try check(FileManager.default.fileExists(atPath: conflictingPDF.path), "Conflicting source PDF was removed")

    let textFile = downloads.appendingPathComponent("notes.txt")
    try Data("not a PDF".utf8).write(to: textFile)
    let nonPDFResult = IncomingPDFMover.move([textFile], to: inbox, excluding: library)
    try check(nonPDFResult.failures.count == 1, "Non-PDF input was accepted")

    let organizedDirectory = library.appendingPathComponent("Papers/Systems", isDirectory: true)
    try FileManager.default.createDirectory(at: organizedDirectory, withIntermediateDirectories: true)
    let organizedPDF = organizedDirectory.appendingPathComponent("organized.pdf")
    try Data("%PDF-1.4 organized".utf8).write(to: organizedPDF)
    let organizedResult = IncomingPDFMover.move([organizedPDF], to: inbox, excluding: library)
    try check(organizedResult.failures.count == 1, "An organized library PDF was moved back to the inbox")
    try check(FileManager.default.fileExists(atPath: organizedPDF.path), "Organized library PDF was removed")

    let symlinkPDF = downloads.appendingPathComponent("linked.pdf")
    try FileManager.default.createSymbolicLink(at: symlinkPDF, withDestinationURL: inbox.appendingPathComponent("paper.pdf"))
    let symlinkResult = IncomingPDFMover.move([symlinkPDF], to: inbox, excluding: library)
    try check(symlinkResult.failures.count == 1, "A symbolic link was accepted as a PDF")
    try check(FileManager.default.fileExists(atPath: symlinkPDF.path), "Rejected symbolic link was removed")

    let publicPapers = temporaryDirectory.appendingPathComponent("Documents/Paper Library/Papers", isDirectory: true)
    let storageLock = temporaryDirectory.appendingPathComponent("runtime/on-demand-worker.lock", isDirectory: true)
    let catalogBeforeMove = try Data(contentsOf: LibraryLayout.catalogCSVURL(in: library))
    try check(
        try PaperStorage.prepare(in: library, at: publicPapers, lockDirectory: storageLock),
        "Existing PDFs were not moved to Documents"
    )
    try check(try Data(contentsOf: publicPapers.appendingPathComponent("Systems/organized.pdf")) == Data("%PDF-1.4 organized".utf8), "PDF contents changed during relocation")
    try check(try Data(contentsOf: LibraryLayout.catalogCSVURL(in: library)) == catalogBeforeMove, "Relocation rewrote the catalog")
    try check(try LibraryLayout.papersURL(in: library).resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true, "Private Papers path is not a link")
    try check(try !PaperStorage.prepare(in: library, at: publicPapers, lockDirectory: storageLock), "Relocation ran again on an existing link")
    _ = try LibraryLayout.prepareLibrary(at: library)
    try check(try LibraryLayout.papersURL(in: library).resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true, "Library startup replaced the PDF folder link")
    var publicPaper = original
    publicPaper.file = "Papers/Systems/organized.pdf"
    try check(publicPaper.pdfURL(in: library) == publicPapers.appendingPathComponent("Systems/organized.pdf"), "Open PDF did not resolve the public document location")
    let reimport = IncomingPDFMover.move([publicPapers.appendingPathComponent("Systems/organized.pdf")], to: inbox, excluding: library)
    try check(reimport.failures.count == 1, "An already organized public PDF was imported again")

    let conflictLibrary = temporaryDirectory.appendingPathComponent("conflict-library", isDirectory: true)
    _ = try LibraryLayout.prepareLibrary(at: conflictLibrary)
    let conflictSource = LibraryLayout.papersURL(in: conflictLibrary).appendingPathComponent("keep.pdf")
    try Data("keep".utf8).write(to: conflictSource)
    do {
        _ = try PaperStorage.prepare(in: conflictLibrary, at: publicPapers, lockDirectory: storageLock)
        throw CheckFailure.failed("An existing destination was merged or overwritten")
    } catch StorageError.destinationConflict(let path) {
        try check(path == publicPapers.path, "The folder shown for resolving the conflict was incorrect")
    }
    try check(try String(contentsOf: conflictSource, encoding: .utf8) == "keep", "A conflicting migration lost its source")

    try FileManager.default.createDirectory(at: storageLock, withIntermediateDirectories: true)
    let busyOwner = try JSONSerialization.data(withJSONObject: ["pid": ProcessInfo.processInfo.processIdentifier])
    try busyOwner.write(to: storageLock.appendingPathComponent("owner.json"))
    do {
        _ = try PaperStorage.prepare(in: conflictLibrary, at: temporaryDirectory.appendingPathComponent("busy-target"), lockDirectory: storageLock)
        throw CheckFailure.failed("Storage changed while the organizer held its lock")
    } catch is CheckFailure { throw CheckFailure.failed("Storage changed while the organizer held its lock") }
      catch { /* Expected busy organizer. */ }
    try check(FileManager.default.fileExists(atPath: conflictSource.path), "Busy migration moved a PDF")
    try FileManager.default.removeItem(at: storageLock)

    let recoveredLibrary = temporaryDirectory.appendingPathComponent("recovered-library", isDirectory: true)
    _ = try LibraryLayout.prepareLibrary(at: recoveredLibrary)
    try CSVCodec.encode([publicPaper]).write(to: LibraryLayout.catalogCSVURL(in: recoveredLibrary), atomically: true, encoding: .utf8)
    try check(try PaperStorage.prepare(in: recoveredLibrary, at: publicPapers, lockDirectory: storageLock), "An interrupted directory move could not be recovered")
    try check(publicPaper.pdfURL(in: recoveredLibrary) == publicPaper.pdfURL(in: library), "Recovered storage points to the wrong PDF")

    let lostCatalogLibrary = temporaryDirectory.appendingPathComponent("lost-catalog-library")
    _ = try LibraryLayout.prepareLibrary(at: lostCatalogLibrary)
    let existingShelf = temporaryDirectory.appendingPathComponent("existing-documents")
    let firstPDF = existingShelf.appendingPathComponent("Systems/Inference/first.pdf")
    let secondPDF = existingShelf.appendingPathComponent("Robotics/Filename Title.PDF")
    let firstPDFBytes = try writeRecoveryPDF(at: firstPDF, title: "Original PDF Title", author: "Original Author")
    let secondPDFBytes = try writeRecoveryPDF(at: secondPDF)
    let unreadablePDF = existingShelf.appendingPathComponent("Robotics/Missing Metadata.pdf")
    try Data("No readable PDF metadata".utf8).write(to: unreadablePDF)
    try check(PaperStorage.recoveryMetadata(at: firstPDF, fileFlags: UInt32(SF_DATALESS)) == nil, "An iCloud placeholder was opened to read PDF contents")
    try check(PaperStorage.recoveryMetadata(at: firstPDF, fileFlags: 0)?[PDFDocumentAttribute.titleAttribute] as? String == "Original PDF Title", "A locally available PDF did not retain its metadata")
    try Data("Finder metadata".utf8).write(to: existingShelf.appendingPathComponent(".DS_Store"))
    let outsidePDF = temporaryDirectory.appendingPathComponent("outside/Private.pdf")
    _ = try writeRecoveryPDF(at: outsidePDF)
    try FileManager.default.createSymbolicLink(at: existingShelf.appendingPathComponent("Outside"), withDestinationURL: outsidePDF.deletingLastPathComponent())
    try FileManager.default.createSymbolicLink(at: existingShelf.appendingPathComponent("Systems/linked.pdf"), withDestinationURL: outsidePDF)
    let recoveredCSV = LibraryLayout.catalogCSVURL(in: lostCatalogLibrary)
    try check(try PaperStorage.prepare(in: lostCatalogLibrary, at: existingShelf, lockDirectory: storageLock), "An empty local catalog could not recover the existing Documents shelf")
    var recoveredPapers = try CSVCodec.decode(String(contentsOf: recoveredCSV, encoding: .utf8))
    try check(recoveredPapers.count == 3, "Recovery missed a PDF or followed a hidden file or symlink")
    let firstIndex = recoveredPapers.firstIndex(where: { $0.file == "Papers/Systems/Inference/first.pdf" })!
    let recoveredFirst = recoveredPapers[firstIndex]
    try check(recoveredFirst.title == "Original PDF Title" && recoveredFirst.authors == "Original Author", "Recovery did not prefer embedded PDF metadata")
    try check(recoveredFirst.category == "Systems" && recoveredFirst.subcategory == "Inference", "Recovery lost the existing folder classification")
    try check(recoveredPapers.contains(where: { $0.title == "Filename Title" }), "Missing PDF metadata did not fall back to the filename")
    try check(recoveredPapers.contains(where: { $0.title == "Missing Metadata" }), "A PDF metadata read failure prevented filename recovery")
    try check(recoveredFirst.year.isEmpty && recoveredFirst.venue.isEmpty && recoveredFirst.presentation.isEmpty && recoveredFirst.summary.isEmpty, "Recovery invented missing publication metadata")
    try check(recoveredFirst.validationError() == nil, "Recovered metadata cannot be edited with unknown publication fields")
    try check(try CSVCodec.decode(CSVCodec.encode(recoveredPapers)) == recoveredPapers, "Unknown metadata did not survive a CSV round-trip")
    try check(recoveredFirst.pdfURL(in: lostCatalogLibrary) == firstPDF, "The recovered PDF cannot be opened through the private storage link")
    try check(try Data(contentsOf: firstPDF) == firstPDFBytes && Data(contentsOf: secondPDF) == secondPDFBytes, "Recovery modified existing PDF content")
    let firstRecoveryCSV = try Data(contentsOf: recoveredCSV)
    _ = try PaperStorage.prepare(in: lostCatalogLibrary, at: existingShelf, lockDirectory: storageLock)
    try check(try Data(contentsOf: recoveredCSV) == firstRecoveryCSV, "Retrying recovery rewrote the catalog or duplicated papers")

    recoveredPapers[firstIndex].summary = "Keep the existing personal summary."
    recoveredPapers[firstIndex].year = "2024"
    try CSVCodec.encode(recoveredPapers).write(to: recoveredCSV, atomically: true, encoding: .utf8)
    _ = try writeRecoveryPDF(at: existingShelf.appendingPathComponent("Systems/new.pdf"), title: "New PDF")
    _ = try PaperStorage.prepare(in: lostCatalogLibrary, at: existingShelf, lockDirectory: storageLock)
    let synchronizedPapers = try CSVCodec.decode(String(contentsOf: recoveredCSV, encoding: .utf8))
    try check(synchronizedPapers.count == 4 && synchronizedPapers[firstIndex] == recoveredPapers[firstIndex], "Synchronization lost existing metadata while adding an unlisted PDF")

    let interruptedLibrary = temporaryDirectory.appendingPathComponent("interrupted-recovery")
    _ = try LibraryLayout.prepareLibrary(at: interruptedLibrary)
    do {
        _ = try PaperStorage.prepare(in: interruptedLibrary, at: existingShelf, lockDirectory: storageLock, fileManager: RejectedStorageLinkFileManager())
        throw CheckFailure.failed("The simulated storage link failure did not occur")
    } catch let error as CocoaError {
        try check(error.code == .fileWriteNoPermission, "Unexpected storage recovery failure")
    }
    try check(try Data(contentsOf: firstPDF) == firstPDFBytes, "Failed recovery changed an existing PDF")
    try check(try FileManager.default.contentsOfDirectory(atPath: LibraryLayout.papersURL(in: interruptedLibrary).path).isEmpty, "Failed recovery did not restore the empty private Papers directory")
    let interruptedCSV = try Data(contentsOf: LibraryLayout.catalogCSVURL(in: interruptedLibrary))
    try check(try PaperStorage.prepare(in: interruptedLibrary, at: existingShelf, lockDirectory: storageLock), "Interrupted catalog recovery could not be retried")
    try check(try Data(contentsOf: LibraryLayout.catalogCSVURL(in: interruptedLibrary)) == interruptedCSV, "Retry after a link failure duplicated or rewrote recovered rows")

    let catalogDirectory = library.appendingPathComponent("Catalog", isDirectory: true)
    try FileManager.default.createDirectory(at: catalogDirectory, withIntermediateDirectories: true)
    let unconfiguredLibrary = temporaryDirectory.appendingPathComponent("unconfigured-library", isDirectory: true)
    try FileManager.default.createDirectory(at: unconfiguredLibrary, withIntermediateDirectories: true)
    let unconfiguredStatus = OrganizerStatusFile.read(from: unconfiguredLibrary, now: Date())
    try check(!unconfiguredStatus.hasRuntimeStatus, "An unconfigured library was treated as connected")
    try check(
        unconfiguredStatus.lastError == "Paper Organizer has not been configured for this library.",
        "An unconfigured library showed a stale-heartbeat warning"
    )

    let settingsURL = catalogDirectory.appendingPathComponent("organizer-settings.json")
    let settingsJSON = """
    {
      "version": 1,
      "automationDevice": {"id":"remote-id","name":"Office Mac","platform":"darwin"},
      "model": "gpt-5.6-terra",
      "reasoning": "medium",
      "language": "korean",
      "catalogTranslation": null
    }
    """
    try settingsJSON.write(to: settingsURL, atomically: true, encoding: .utf8)
    let waitingStatus = OrganizerStatusFile.read(from: library, now: Date())
    try check(
        waitingStatus.lastError == "The local organizer has not reported its status yet.",
        "A configured library without runtime status showed the wrong warning"
    )
    let runtimeJSON = """
    {"phase":"processing","machine":"Office Mac","currentDisplayFiles":["Queued Paper.pdf"],"queuedFiles":["Next.pdf"],"lastError":"","updatedAt":"2026-09-02T01:02:03.456Z"}
    """
    try runtimeJSON.write(
        to: catalogDirectory.appendingPathComponent("runtime-status.json"),
        atomically: true,
        encoding: .utf8
    )
    let statusTime = try Date("2026-09-02T01:03:00Z", strategy: .iso8601)
    let organizerStatus = OrganizerStatusFile.read(from: library, now: statusTime)
    try check(organizerStatus.hasRuntimeStatus, "Runtime status JSON did not decode")
    try check(organizerStatus.automationDeviceName == "Office Mac", "Remote automation device was not read")
    try check(organizerStatus.phase == "processing", "Organizer phase was not read")
    try check(organizerStatus.activeFiles == ["Queued Paper.pdf"], "Active PDF names were not read")
    try check(organizerStatus.processingPapers.isEmpty, "A display-only status became a processing paper")

    let progressiveRuntimeJSON = """
    {"mode":"on-demand","phase":"processing","machine":"Office Mac","currentFiles":["Waiting/2605.13778v1.pdf"],"queuedFiles":[],"lastError":"","updatedAt":"2026-09-02T01:02:03.456Z"}
    """
    try progressiveRuntimeJSON.write(
        to: catalogDirectory.appendingPathComponent("runtime-status.json"),
        atomically: true,
        encoding: .utf8
    )
    let filenameOnlyStatus = OrganizerStatusFile.read(from: library, now: statusTime)
    try check(filenameOnlyStatus.processingPapers.count == 1, "The processing paper was not shown before its title was resolved")
    try check(filenameOnlyStatus.processingPapers[0].displayTitle == "2605.13778v1.pdf", "The original filename was not used as the initial title")

    let processingJSON = """
    {"version":1,"items":[{"file":"Waiting/2605.13778v1.pdf","title":"Resolved Paper Title"}]}
    """
    try processingJSON.write(
        to: catalogDirectory.appendingPathComponent("processing-papers.json"),
        atomically: true,
        encoding: .utf8
    )
    let progressiveStatus = OrganizerStatusFile.read(from: library, now: statusTime)
    try check(progressiveStatus.processingPapers.count == 1, "The active processing paper was not decoded")
    try check(progressiveStatus.processingPapers[0].filename == "2605.13778v1.pdf", "The original PDF filename was not preserved")
    try check(progressiveStatus.processingPapers[0].displayTitle == "Resolved Paper Title", "The resolved paper title was not shown")
    try check(progressiveStatus.activeFiles == ["Resolved Paper Title"], "The status badge did not use the resolved title")

    let staleTime = try Date("2026-09-02T01:05:04Z", strategy: .iso8601)
    let staleStatus = OrganizerStatusFile.read(from: library, now: staleTime)
    try check(!staleStatus.hasRuntimeStatus, "A stale runtime heartbeat was treated as connected")
    try check(staleStatus.phase == "offline", "A stale active run did not mark the organizer offline")
    try check(staleStatus.activeFiles.isEmpty, "Stale processing files were still shown as active")

    let editingRuntimeJSON = """
    {"mode":"on-demand","phase":"editing","machine":"Office Mac","currentFiles":[],"queuedFiles":[],"lastError":"","updatedAt":"2026-09-02T01:02:03.456Z"}
    """
    try editingRuntimeJSON.write(
        to: catalogDirectory.appendingPathComponent("runtime-status.json"),
        atomically: true,
        encoding: .utf8
    )
    let editingStatus = OrganizerStatusFile.read(from: library, now: statusTime)
    try check(editingStatus.hasRuntimeStatus, "A current library editing command was treated as stale")
    try check(editingStatus.phaseLabel == "Updating library with Codex", "The library editing label is incorrect")

    let onDemandIdleRuntimeJSON = """
    {"mode":"on-demand","phase":"idle","machine":"Office Mac","currentFiles":[],"queuedFiles":[],"lastError":"","updatedAt":"2026-09-02T01:02:03.456Z"}
    """
    try onDemandIdleRuntimeJSON.write(
        to: catalogDirectory.appendingPathComponent("runtime-status.json"),
        atomically: true,
        encoding: .utf8
    )
    let laterTime = try Date("2026-09-03T01:05:04Z", strategy: .iso8601)
    let onDemandIdleStatus = OrganizerStatusFile.read(from: library, now: laterTime)
    try check(onDemandIdleStatus.hasRuntimeStatus, "An idle on-demand organizer became stale")
    try check(onDemandIdleStatus.phase == "idle", "An idle on-demand organizer was not shown as ready")
    try check(onDemandIdleStatus.phaseLabel == "Ready for Finder", "The on-demand ready label is incorrect")

    try OrganizerStatusFile.update(.model, value: "gpt-5.6-sol", in: library)
    let changedStatus = OrganizerStatusFile.read(from: library, now: statusTime)
    try check(changedStatus.model == "gpt-5.6-sol", "Organizer model setting was not saved")
    let preservedSettings = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any]
    try check((preservedSettings?["automationDevice"] as? [String: Any])?["name"] as? String == "Office Mac", "Automation owner was lost while saving settings")

    try check(OrganizerStatus.unavailable.model == "gpt-6-luna", "The recommended model is not Luna")
    try check(OrganizerStatus.unavailable.reasoning == "xhigh", "The recommended reasoning is not Extra High")
    let modelCatalog = CodexModelCatalog(version: 1, codexPath: "/test/codex", fetchedAt: "2026-09-23T00:00:00Z", models: [
        CodexModel(id: "gpt-6-luna", displayName: "GPT-6 Luna", reasoningEfforts: ["low", "high", "xhigh", "max"], defaultReasoningEffort: "high"),
        CodexModel(id: "future/model-v2", displayName: "Future Model", reasoningEfforts: ["none", "ultra"], defaultReasoningEffort: "none"),
    ])
    try modelCatalog.save(in: library)
    try check(CodexModelCatalog.read(from: library) == modelCatalog, "The model catalog cache did not round-trip")
    try check(OrganizerStatusFile.read(from: library).model == "gpt-5.6-sol", "Caching a catalog changed the selected model")
    try check(modelCatalog.models[0].compatibleReasoning(preferred: "xhigh") == "xhigh", "Supported reasoning was not preserved")
    try check(modelCatalog.models[1].compatibleReasoning(preferred: "xhigh") == "none", "Unsupported reasoning was not replaced with a compatible default")
    try OrganizerStatusFile.update([.model: "future/model-v2", .reasoning: "ultra"], in: library)
    let futureStatus = OrganizerStatusFile.read(from: library)
    try check(futureStatus.model == "future/model-v2" && futureStatus.reasoning == "ultra", "New model IDs or reasoning levels require an app update")
    do {
        try OrganizerStatusFile.update([.model: "--unsafe", .reasoning: "high"], in: library)
        throw CheckFailure.failed("An invalid model ID was accepted")
    } catch is OrganizerStatusError {}
    try check(OrganizerStatusFile.read(from: library).reasoning == "ultra", "A rejected change partially overwrote settings")
    try "{}".write(to: catalogDirectory.appendingPathComponent("codex-models.json"), atomically: true, encoding: .utf8)
    try check(CodexModelCatalog.read(from: library) == nil, "A corrupt cache was accepted")

    if let bundlePath = ProcessInfo.processInfo.environment["PAPER_LIBRARY_TEST_APP_BUNDLE"] {
        guard let appBundle = Bundle(path: bundlePath) else {
            throw CheckFailure.failed("The test app bundle could not be opened")
        }
        let seededRoot = temporaryDirectory.appendingPathComponent("seeded-library", isDirectory: true)
        _ = try LibraryLayout.prepareLibrary(at: seededRoot, bundle: appBundle)
        for relativePath in [
            "Automation/PAPER_LIBRARY_EDITOR.md",
            "Automation/PAPER_ORGANIZER.md",
            "Automation/library-command-schema.json",
            "Automation/codex-models.mjs",
            "Automation/paper-organizer.mjs",
        ] {
            try check(
                FileManager.default.fileExists(atPath: seededRoot.appendingPathComponent(relativePath).path),
                "The app did not install \(relativePath) into managed storage"
            )
        }
    }

    print("Core checks passed (managed storage, CSV, validation, safe paths, Finder PDF move, organizer status).")
} catch {
    fputs("Core check failed: \(error)\n", stderr)
    exit(1)
}
