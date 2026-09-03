import Foundation

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): message
        }
    }
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure.failed(message) }
}

func fixturePaper() -> Paper {
    Paper(
        category: "Systems", subcategory: "Inference", venue: "ICML", year: "2026",
        track: "Main", workshop: "", presentation: "Oral",
        title: "A Title, with \"Quotes\"", authors: "Ada Lovelace, Alan Turing",
        affiliation: "Example University", summary: "A compact summary.",
        novelty: "A new mechanism.", site: "https://example.com/paper",
        addedAt: "2026-09-02 10:00:00", file: "paper/Systems/A Title.pdf"
    )
}

do {
    let original = fixturePaper()
    let encoded = try CSVCodec.encode([original])
    let decoded = try CSVCodec.decode(encoded)
    try check(decoded == [original], "CSV round-trip changed paper metadata")
    try check(encoded.contains("\"A Title, with \"\"Quotes\"\"\""), "CSV quotes were not escaped")

    let row = "\"Systems\",\"\",\"arXiv\",2026,\"\",\"\",\"Preprint\",\"Title\",\"Author\",\"Lab\",\"Summary\",\"Novelty\",\"\",\"2026-09-02\",\"paper/Systems/Title.pdf\""
    let crlfCatalog = CSVCodec.headers.joined(separator: ",") + "\r\n" + row + "\r\n"
    let crlfPapers = try CSVCodec.decode(crlfCatalog)
    try check(crlfPapers.first?.title == "Title", "CRLF catalog did not decode")

    let oldLayoutRow = row.replacingOccurrences(
        of: "paper/Systems/Title.pdf",
        with: "Systems/Title.pdf"
    )
    let oldLayoutCatalog = CSVCodec.headers.joined(separator: ",") + "\n" + oldLayoutRow + "\n"
    do {
        _ = try CSVCodec.decode(oldLayoutCatalog)
        throw CheckFailure.failed("A catalog PDF outside paper/ was accepted")
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

    let root = URL(fileURLWithPath: "/tmp/paper-library")
    var unsafe = original
    try check(unsafe.pdfURL(in: root) != nil, "Valid PDF path was rejected")
    unsafe.file = "../private.pdf"
    try check(unsafe.pdfURL(in: root) == nil, "Parent-directory path was accepted")
    unsafe.file = "/tmp/private.pdf"
    try check(unsafe.pdfURL(in: root) == nil, "Absolute PDF path was accepted")
    unsafe.file = "Systems/private.pdf"
    try check(unsafe.pdfURL(in: root) == nil, "A catalog PDF outside paper/ was accepted")

    var invalid = original
    invalid.track = ""
    try check(invalid.validationError() == "A published paper needs a track.", "Track validation did not run")

    let temporaryDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
    let htmlURL = temporaryDirectory.appendingPathComponent("papers.html")
    try "before /* CATALOG_DATA_START */ old /* CATALOG_DATA_END */ after"
        .write(to: htmlURL, atomically: true, encoding: .utf8)
    let htmlWasUpdated = try HTMLCatalogUpdater.update(papers: [], at: htmlURL)
    try check(htmlWasUpdated, "HTML viewer was not updated")
    let html = try String(contentsOf: htmlURL, encoding: .utf8)
    try check(html.hasPrefix("before /* CATALOG_DATA_START */"), "HTML prefix changed")
    try check(html.hasSuffix("/* CATALOG_DATA_END */ after"), "HTML suffix changed")
    try check(html.contains("const CATALOG = [];"), "HTML catalog JSON was not embedded")

    let inbox = temporaryDirectory.appendingPathComponent("library", isDirectory: true)
    let downloads = temporaryDirectory.appendingPathComponent("downloads", isDirectory: true)
    let secondDownloads = temporaryDirectory.appendingPathComponent("second-downloads", isDirectory: true)
    try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: secondDownloads, withIntermediateDirectories: true)

    let sourcePDF = downloads.appendingPathComponent("paper.pdf")
    try Data("%PDF-1.4 test".utf8).write(to: sourcePDF)
    let moveResult = IncomingPDFMover.move([sourcePDF], to: inbox)
    try check(moveResult.failures.isEmpty, "Valid PDF move failed")
    try check(!FileManager.default.fileExists(atPath: sourcePDF.path), "PDF was copied instead of moved")
    try check(FileManager.default.fileExists(atPath: inbox.appendingPathComponent("paper.pdf").path), "Moved PDF is missing")

    let conflictingPDF = secondDownloads.appendingPathComponent("paper.pdf")
    try Data("%PDF-1.4 conflict".utf8).write(to: conflictingPDF)
    let conflictResult = IncomingPDFMover.move([conflictingPDF], to: inbox)
    try check(conflictResult.failures.count == 1, "Duplicate filename was not rejected")
    try check(FileManager.default.fileExists(atPath: conflictingPDF.path), "Conflicting source PDF was removed")

    let textFile = downloads.appendingPathComponent("notes.txt")
    try Data("not a PDF".utf8).write(to: textFile)
    let nonPDFResult = IncomingPDFMover.move([textFile], to: inbox)
    try check(nonPDFResult.failures.count == 1, "Non-PDF input was accepted")

    let organizedDirectory = inbox.appendingPathComponent("paper/Systems", isDirectory: true)
    try FileManager.default.createDirectory(at: organizedDirectory, withIntermediateDirectories: true)
    let organizedPDF = organizedDirectory.appendingPathComponent("organized.pdf")
    try Data("%PDF-1.4 organized".utf8).write(to: organizedPDF)
    let organizedResult = IncomingPDFMover.move([organizedPDF], to: inbox)
    try check(organizedResult.failures.count == 1, "An organized library PDF was moved back to the inbox")
    try check(FileManager.default.fileExists(atPath: organizedPDF.path), "Organized library PDF was removed")

    let symlinkPDF = downloads.appendingPathComponent("linked.pdf")
    try FileManager.default.createSymbolicLink(at: symlinkPDF, withDestinationURL: inbox.appendingPathComponent("paper.pdf"))
    let symlinkResult = IncomingPDFMover.move([symlinkPDF], to: inbox)
    try check(symlinkResult.failures.count == 1, "A symbolic link was accepted as a PDF")
    try check(FileManager.default.fileExists(atPath: symlinkPDF.path), "Rejected symbolic link was removed")

    let catalogDirectory = inbox.appendingPathComponent(".catalog", isDirectory: true)
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
    let waitingStatus = OrganizerStatusFile.read(from: inbox, now: Date())
    try check(
        waitingStatus.lastError == "No watcher status has been received from the automation device yet.",
        "A configured library without runtime status showed the wrong warning"
    )
    let runtimeJSON = """
    window.PAPER_RUNTIME_STATUS = {"phase":"processing","machine":"Office Mac","currentDisplayFiles":["Queued Paper.pdf"],"queuedFiles":["Next.pdf"],"lastError":"","updatedAt":"2026-09-02T01:02:03.456Z"};
    """
    try runtimeJSON.write(
        to: catalogDirectory.appendingPathComponent("runtime-status.js"),
        atomically: true,
        encoding: .utf8
    )
    let statusTime = try Date("2026-09-02T01:03:00Z", strategy: .iso8601)
    let organizerStatus = OrganizerStatusFile.read(from: inbox, now: statusTime)
    try check(organizerStatus.hasRuntimeStatus, "Runtime status JavaScript did not decode")
    try check(organizerStatus.automationDeviceName == "Office Mac", "Remote automation device was not read")
    try check(organizerStatus.phase == "processing", "Organizer phase was not read")
    try check(organizerStatus.activeFiles == ["Queued Paper.pdf"], "Active PDF names were not read")

    let staleTime = try Date("2026-09-02T01:05:04Z", strategy: .iso8601)
    let staleStatus = OrganizerStatusFile.read(from: inbox, now: staleTime)
    try check(!staleStatus.hasRuntimeStatus, "A stale runtime heartbeat was treated as connected")
    try check(staleStatus.phase == "offline", "A stale runtime heartbeat did not mark the watcher offline")
    try check(staleStatus.activeFiles.isEmpty, "Stale processing files were still shown as active")

    try OrganizerStatusFile.update(.model, value: "gpt-5.6-sol", in: inbox)
    let changedStatus = OrganizerStatusFile.read(from: inbox, now: statusTime)
    try check(changedStatus.model == "gpt-5.6-sol", "Organizer model setting was not saved")
    let preservedSettings = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any]
    try check((preservedSettings?["automationDevice"] as? [String: Any])?["name"] as? String == "Office Mac", "Automation owner was lost while saving settings")

    print("Core checks passed (CSV, validation, safe paths, HTML sync, Finder PDF move, remote organizer status).")
} catch {
    fputs("Core check failed: \(error)\n", stderr)
    exit(1)
}
