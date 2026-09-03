import AppKit
import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var papers: [Paper] = []
    @Published private(set) var libraryURL: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var organizerStatus = OrganizerStatus.unavailable
    @Published var errorMessage: String?
    @Published var noticeMessage: String?

    private let bookmarkKey = "PaperLibraryRootBookmark"
    private var isAccessingSecurityScopedResource = false
    private var didAttemptRestore = false
    private var catalogRefreshTask: Task<Void, Never>?

    var hasLibrary: Bool { libraryURL != nil }
    var libraryName: String { libraryURL?.lastPathComponent ?? "No Library" }

    var categories: [(name: String, count: Int)] {
        Dictionary(grouping: papers, by: \Paper.category)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    func subcategories(in category: String) -> [(name: String, count: Int)] {
        Dictionary(grouping: papers.filter {
            $0.category == category && !$0.subcategory.isEmpty
        }, by: \Paper.subcategory)
            .map { ($0.key, $0.value.count) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    func restoreLibraryIfPossible() {
        guard !didAttemptRestore else { return }
        didAttemptRestore = true
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }

        do {
            var stale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            try connect(to: url, saveBookmark: stale)
        } catch {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            errorMessage = "The saved library could not be reopened. Choose the folder again.\n\n\(error.localizedDescription)"
        }
    }

    @discardableResult
    func chooseLibrary() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Choose Paper Library"
        panel.message = "Select the folder that contains .catalog/papers.csv."
        panel.prompt = "Choose Library"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        if let libraryURL { panel.directoryURL = libraryURL }

        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try connect(to: url, saveBookmark: true)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func reload() {
        guard let libraryURL else { return }
        do {
            try loadCatalog(from: libraryURL)
            refreshOrganizerStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshOrganizerStatus() {
        guard let libraryURL else {
            organizerStatus = .unavailable
            return
        }
        let previousCompletion = organizerStatus.lastCompletedAt
        let refreshedStatus = OrganizerStatusFile.read(from: libraryURL)
        organizerStatus = refreshedStatus
        if let completion = refreshedStatus.lastCompletedAt,
           completion != previousCompletion {
            refreshCatalogAfterOrganizerCompletion(in: libraryURL)
        }
    }

    func updateOrganizerSetting(_ setting: OrganizerSetting, to value: String) {
        guard let libraryURL else { return }
        do {
            try OrganizerStatusFile.update(setting, value: value, in: libraryURL)
            refreshOrganizerStatus()
            noticeMessage = setting == .language
                ? "Language saved for newly processed papers. Existing summaries were left unchanged."
                : "Automation \(setting.rawValue) saved. The assigned device will use it for the next paper."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func moveIncomingPDFs(_ sourceURLs: [URL]) -> PDFMoveResult {
        guard let libraryURL else {
            let failures = sourceURLs.map {
                PDFMoveFailure(source: $0, message: "Choose a Paper Library folder first.")
            }
            errorMessage = failures.map(\.message).first
            return PDFMoveResult(moved: [], failures: failures)
        }

        let result = IncomingPDFMover.move(sourceURLs, to: libraryURL)
        if !result.moved.isEmpty {
            let count = result.moved.count
            noticeMessage = "Moved \(count) PDF\(count == 1 ? "" : "s") into \(libraryName). The organizer will process \(count == 1 ? "it" : "them") next."
        }
        if !result.failures.isEmpty {
            errorMessage = result.failureSummary
        }
        return result
    }

    func save(_ editedPaper: Paper) -> Bool {
        guard let libraryURL else {
            errorMessage = "Choose a paper library first."
            return false
        }
        var cleaned = editedPaper
        cleaned.cleanEditableValues()
        if let validationError = cleaned.validationError() {
            errorMessage = validationError
            return false
        }

        do {
            let current = try readCatalog(at: libraryURL)
            guard let index = current.firstIndex(where: { $0.file == cleaned.file }) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [
                    NSLocalizedDescriptionKey: "The paper was no longer present in the CSV when saving began.",
                ])
            }
            var updated = current
            updated[index] = cleaned
            let htmlWarning = try writeCatalog(updated, at: libraryURL)
            papers = updated
            noticeMessage = htmlWarning ?? "Saved “\(cleaned.title)”."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(_ paper: Paper) -> Bool {
        guard let libraryURL, let pdfURL = paper.pdfURL(in: libraryURL) else {
            errorMessage = "The PDF path is not safe or the library is unavailable."
            return false
        }

        do {
            let current = try readCatalog(at: libraryURL)
            guard let index = current.firstIndex(where: { $0.file == paper.file }) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [
                    NSLocalizedDescriptionKey: "The paper was no longer present in the CSV when deletion began.",
                ])
            }
            guard FileManager.default.fileExists(atPath: pdfURL.path) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [
                    NSLocalizedDescriptionKey: "The PDF could not be found at \(paper.file).",
                ])
            }

            let updated = current.enumerated().compactMap { offset, item in
                offset == index ? nil : item
            }
            let htmlWarning = try writeCatalog(updated, at: libraryURL)

            do {
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: pdfURL, resultingItemURL: &resultingURL)
            } catch {
                _ = try? writeCatalog(current, at: libraryURL)
                throw error
            }

            papers = updated
            noticeMessage = htmlWarning ?? "Moved “\(paper.title)” to the Trash and removed its catalog entry."
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func openPDF(_ paper: Paper) {
        guard let libraryURL, let url = paper.pdfURL(in: libraryURL) else {
            errorMessage = "The PDF path is invalid."
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "The PDF could not be found at \(paper.file)."
            return
        }
        NSWorkspace.shared.open(url)
    }

    func revealPDF(_ paper: Paper) {
        guard let libraryURL, let url = paper.pdfURL(in: libraryURL) else {
            errorMessage = "The PDF path is invalid."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openSite(_ paper: Paper) {
        guard let url = URL(string: paper.site), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            errorMessage = "The paper site URL is invalid."
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func connect(to url: URL, saveBookmark: Bool) throws {
        let previousURL = libraryURL
        let previousAccess = isAccessingSecurityScopedResource
        let accessStarted = url.startAccessingSecurityScopedResource()
        do {
            isLoading = true
            defer { isLoading = false }
            let newPapers = try readCatalog(at: url)
            let bookmark = saveBookmark
                ? try url.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                : nil

            if previousAccess, let previousURL {
                previousURL.stopAccessingSecurityScopedResource()
            }
            libraryURL = url
            papers = newPapers
            organizerStatus = OrganizerStatusFile.read(from: url)
            isAccessingSecurityScopedResource = accessStarted
            if let bookmark {
                UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            }
        } catch {
            if accessStarted { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    private func loadCatalog(from root: URL) throws {
        isLoading = true
        defer { isLoading = false }
        papers = try readCatalog(at: root)
    }

    private func refreshCatalogAfterOrganizerCompletion(in root: URL) {
        catalogRefreshTask?.cancel()
        catalogRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for delay in [0, 2, 5, 10] {
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
                guard !Task.isCancelled, self.libraryURL == root else { return }
                guard let refreshedPapers = try? self.readCatalog(at: root) else { continue }
                if refreshedPapers != self.papers {
                    self.papers = refreshedPapers
                    self.noticeMessage = "Catalog updated after paper processing completed."
                    return
                }
            }
        }
    }

    private func readCatalog(at root: URL) throws -> [Paper] {
        let url = root.appendingPathComponent(".catalog/papers.csv")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "This folder does not contain .catalog/papers.csv.",
            ])
        }
        return try CSVCodec.decode(String(contentsOf: url, encoding: .utf8))
    }

    @discardableResult
    private func writeCatalog(_ updated: [Paper], at root: URL) throws -> String? {
        let csvURL = root.appendingPathComponent(".catalog/papers.csv")
        let htmlURL = root.appendingPathComponent("papers.html")
        let csv = try CSVCodec.encode(updated)
        try csv.write(to: csvURL, atomically: true, encoding: .utf8)

        do {
            let htmlUpdated = try HTMLCatalogUpdater.update(papers: updated, at: htmlURL)
            if !htmlUpdated {
                return "The CSV was saved. The optional papers.html viewer was not present, so only the native app was updated."
            }
        } catch {
            return "The CSV was saved, but the optional papers.html viewer could not be refreshed: \(error.localizedDescription)"
        }
        return nil
    }

    private func stopSecurityScopedAccess() {
        if isAccessingSecurityScopedResource, let libraryURL {
            libraryURL.stopAccessingSecurityScopedResource()
        }
        isAccessingSecurityScopedResource = false
    }
}
