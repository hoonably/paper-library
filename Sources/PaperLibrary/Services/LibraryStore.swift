import AppKit
import Foundation

private enum AutomationSetupResult {
    case success
    case failure(String)
}

enum CodexCLIReadiness: Equatable, Sendable {
    case notChecked
    case checking
    case signingIn
    case ready(path: String)
    case missing
    case signedOut(path: String)
    case runtimeMissing
    case failed(String)

    var readyPath: String? {
        if case .ready(let path) = self { return path }
        return nil
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var papers: [Paper] = []
    @Published private(set) var libraryURL: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var isSettingUpAutomation = false
    @Published private(set) var organizerStatus = OrganizerStatus.unavailable
    @Published private(set) var codexCLIReadiness = CodexCLIReadiness.notChecked
    @Published var isShowingAutomationSetup = false
    @Published var setupLanguage = "korean"
    @Published var errorMessage: String?
    @Published var noticeMessage: String?

    private var didPrepareLibrary = false
    private var catalogRefreshTask: Task<Void, Never>?

    var hasLibrary: Bool { libraryURL != nil }
    var isAutomationConfigured: Bool {
        organizerStatus.automationDeviceName != OrganizerStatus.unavailable.automationDeviceName
    }

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

    func prepareManagedLibraryIfNeeded() {
        guard !didPrepareLibrary else { return }
        didPrepareLibrary = true
        do {
            isLoading = true
            defer { isLoading = false }
            let root = try LibraryLayout.prepareManagedLibrary()
            libraryURL = root
            papers = try readCatalog(at: root)
            organizerStatus = OrganizerStatusFile.read(from: root)
            setupLanguage = organizerStatus.language
        } catch {
            libraryURL = nil
            papers = []
            organizerStatus = .unavailable
            errorMessage = error.localizedDescription
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
            if setting == .language { setupLanguage = value }
            refreshOrganizerStatus()
            noticeMessage = setting == .language
                ? "Language saved for newly processed papers. Existing summaries were left unchanged."
                : "Automation \(setting.rawValue) saved. The assigned device will use it for the next paper."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func presentAutomationSetupIfNeeded() {
        guard hasLibrary, !isAutomationConfigured else { return }
        presentAutomationSetup()
    }

    func presentAutomationSetup() {
        isShowingAutomationSetup = true
        checkCodexCLI()
    }

    func checkCodexCLI() {
        guard codexCLIReadiness != .checking, codexCLIReadiness != .signingIn else { return }
        codexCLIReadiness = .checking
        Task { @MainActor [weak self] in
            let readiness = await Task.detached {
                Self.inspectCodexCLI()
            }.value
            self?.codexCLIReadiness = readiness
        }
    }

    func signInToCodex() {
        guard case .signedOut(let codexPath) = codexCLIReadiness else { return }
        codexCLIReadiness = .signingIn
        Task { @MainActor [weak self] in
            let readiness = await Task.detached {
                Self.runCodexLogin(at: codexPath)
            }.value
            self?.codexCLIReadiness = readiness
        }
    }

    func setUpAutomation() {
        guard !isSettingUpAutomation,
              let libraryURL,
              let codexPath = codexCLIReadiness.readyPath
        else { return }
        let model = organizerStatus.model
        let reasoning = organizerStatus.reasoning
        let language = setupLanguage
        isSettingUpAutomation = true
        Task { @MainActor [weak self] in
            let result = await Task.detached {
                Self.runAutomationSetup(
                    in: libraryURL,
                    codexPath: codexPath,
                    model: model,
                    reasoning: reasoning,
                    language: language
                )
            }.value
            guard let self else { return }
            self.isSettingUpAutomation = false
            switch result {
            case .success:
                self.refreshOrganizerStatus()
                self.isShowingAutomationSetup = false
                self.noticeMessage = "Paper Organizer is ready. PDFs added from Finder will now be processed automatically."
            case .failure(let message):
                self.errorMessage = message
            }
        }
    }

    @discardableResult
    func moveIncomingPDFs(_ sourceURLs: [URL]) -> PDFMoveResult {
        guard let libraryURL else {
            let failures = sourceURLs.map {
                PDFMoveFailure(source: $0, message: "Paper Library storage is unavailable.")
            }
            errorMessage = failures.map(\.message).first
            return PDFMoveResult(moved: [], failures: failures)
        }

        let result = IncomingPDFMover.move(
            sourceURLs,
            to: LibraryLayout.waitingURL(in: libraryURL),
            excluding: libraryURL
        )
        if !result.moved.isEmpty {
            let count = result.moved.count
            noticeMessage = "Added \(count) PDF\(count == 1 ? "" : "s"). The organizer will process \(count == 1 ? "it" : "them") next."
        }
        if !result.failures.isEmpty {
            errorMessage = result.failureSummary
        }
        return result
    }

    func save(_ editedPaper: Paper) -> Bool {
        guard let libraryURL else {
            errorMessage = "Paper Library storage is unavailable."
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
            try writeCatalog(updated, at: libraryURL)
            papers = updated
            noticeMessage = "Saved “\(cleaned.title)”."
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
            try writeCatalog(updated, at: libraryURL)

            do {
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: pdfURL, resultingItemURL: &resultingURL)
            } catch {
                _ = try? writeCatalog(current, at: libraryURL)
                throw error
            }

            papers = updated
            noticeMessage = "Moved “\(paper.title)” to the Trash and removed its catalog entry."
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

    func revealStorage() {
        guard let libraryURL else {
            errorMessage = "Paper Library storage is unavailable."
            return
        }
        NSWorkspace.shared.open(libraryURL)
    }

    func openSite(_ paper: Paper) {
        guard let url = URL(string: paper.site), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            errorMessage = "The paper site URL is invalid."
            return
        }
        NSWorkspace.shared.open(url)
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
        let url = LibraryLayout.catalogCSVURL(in: root)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "The app catalog could not be found.",
            ])
        }
        return try CSVCodec.decode(String(contentsOf: url, encoding: .utf8))
    }

    private func writeCatalog(_ updated: [Paper], at root: URL) throws {
        let csvURL = LibraryLayout.catalogCSVURL(in: root)
        let csv = try CSVCodec.encode(updated)
        try csv.write(to: csvURL, atomically: true, encoding: .utf8)
    }

    nonisolated private static func runAutomationSetup(
        in root: URL,
        codexPath: String,
        model: String,
        reasoning: String,
        language: String
    ) -> AutomationSetupResult {
        let script = root
            .appendingPathComponent(LibraryLayout.automationDirectoryName, isDirectory: true)
            .appendingPathComponent("paper-organizer.mjs", isDirectory: false)
        guard FileManager.default.fileExists(atPath: script.path) else {
            return .failure("The app's automation files are missing. Reinstall Paper Library and try again.")
        }
        guard let node = findNodeExecutable() else {
            return .failure("Paper Organizer needs Node.js 18 or newer. Install Node.js, then click Set Up Automation again.")
        }

        let process = Process()
        process.executableURL = node
        process.arguments = [
            script.path,
            "install",
            "--root", root.path,
            "--codex", codexPath,
            "--model", model,
            "--reasoning", reasoning,
            "--language", language,
        ]
        var environment = ProcessInfo.processInfo.environment
        let commonPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        environment["PATH"] = (commonPaths + [environment["PATH"] ?? ""])
            .joined(separator: ":")
        process.environment = environment

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(decoding: data, as: UTF8.self).trimmed
            guard process.terminationStatus == 0 else {
                return .failure(text.isEmpty ? "Paper Organizer setup failed." : text)
            }
            return .success
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    nonisolated private static func findNodeExecutable() -> URL? {
        let fileManager = FileManager.default
        let userApplications = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
        let systemApplications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let applicationNames = ["ChatGPT.app", "Codex.app"]
        let bundledNodes = [systemApplications, userApplications].flatMap { applications in
            applicationNames.map { applicationName in
                applications
                    .appendingPathComponent(applicationName, isDirectory: true)
                    .appendingPathComponent("Contents/Resources/cua_node/bin/node", isDirectory: false)
                    .path
            }
        }
        let candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
        ] + bundledNodes
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for directory in path.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(directory), isDirectory: true)
                    .appendingPathComponent("node", isDirectory: false)
                if fileManager.isExecutableFile(atPath: candidate.path) { return candidate }
            }
        }
        return candidates
            .map { URL(fileURLWithPath: $0, isDirectory: false) }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    nonisolated private static func inspectCodexCLI() -> CodexCLIReadiness {
        guard let codex = findCodexExecutable() else { return .missing }
        guard findNodeExecutable() != nil else { return .runtimeMissing }

        let process = Process()
        process.executableURL = codex
        process.arguments = ["login", "status"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return .ready(path: codex.path)
            }
            _ = data
            return .signedOut(path: codex.path)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    nonisolated private static func runCodexLogin(at path: String) -> CodexCLIReadiness {
        let executable = URL(fileURLWithPath: path, isDirectory: false)
        let process = Process()
        process.executableURL = executable
        process.arguments = ["login"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(decoding: data, as: UTF8.self).trimmed
                return .failed(message.isEmpty ? "Codex sign-in did not complete." : message)
            }
            return inspectCodexCLI()
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    nonisolated private static func findCodexExecutable() -> URL? {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let applicationRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true),
        ]
        let bundledCandidates = applicationRoots.flatMap { applications in
            ["ChatGPT.app", "Codex.app"].flatMap { applicationName in
                let contents = applications
                    .appendingPathComponent(applicationName, isDirectory: true)
                    .appendingPathComponent("Contents", isDirectory: true)
                return [
                    contents.appendingPathComponent("Resources/codex", isDirectory: false),
                    contents.appendingPathComponent("MacOS/codex", isDirectory: false),
                ]
            }
        }
        var candidates = [
            home.appendingPathComponent(".local/bin/codex", isDirectory: false),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex", isDirectory: false),
            URL(fileURLWithPath: "/usr/local/bin/codex", isDirectory: false),
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.insert(contentsOf: path.split(separator: ":").map {
                URL(fileURLWithPath: String($0), isDirectory: true)
                    .appendingPathComponent("codex", isDirectory: false)
            }, at: 0)
        }
        candidates.append(contentsOf: bundledCandidates)
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}
