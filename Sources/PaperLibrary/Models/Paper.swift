import Foundation

struct Paper: Identifiable, Codable, Hashable {
    var category: String
    var subcategory: String
    var venue: String
    var year: String
    var track: String
    var workshop: String
    var presentation: String
    var title: String
    var authors: String
    var affiliation: String
    var summary: String
    var novelty: String
    var site: String
    var addedAt: String
    var file: String

    var id: String { file }

    enum CodingKeys: String, CodingKey {
        case category, subcategory, venue, year, track, workshop, presentation
        case title, authors, affiliation, summary, novelty, site, file
        case addedAt = "added_at"
    }

    var categoryPath: String {
        subcategory.isEmpty ? category : "\(category) / \(subcategory)"
    }

    var venueLine: String {
        [venue, year, track.isEmpty || track == "Main" ? nil : track]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var searchableText: String {
        [category, subcategory, venue, year, track, workshop, presentation, title,
         authors, affiliation, summary, novelty]
            .joined(separator: " ")
            .foldedForSearch
    }

    var hasValidCatalogFilePath: Bool {
        guard !file.isEmpty,
              !file.hasPrefix("/"),
              file.lowercased().hasSuffix(".pdf") else { return false }

        let components = file.split(separator: "/", omittingEmptySubsequences: false)
        return [3, 4].contains(components.count) &&
            components.first.map(String.init) == LibraryLayout.papersDirectoryName &&
            components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    func pdfURL(in libraryURL: URL) -> URL? {
        guard hasValidCatalogFilePath else { return nil }

        let root = libraryURL.standardizedFileURL
        let candidate = root.appendingPathComponent(file).standardizedFileURL
        let papersRoot = LibraryLayout.papersURL(in: root).standardizedFileURL
        guard candidate.path.hasPrefix(papersRoot.path + "/") else { return nil }
        return candidate
    }

    func validationError() -> String? {
        let required: [(String, String)] = [
            ("Category", category), ("Venue", venue), ("Year", year),
            ("Presentation", presentation), ("Title", title), ("Authors", authors),
            ("Summary", summary), ("Novelty", novelty),
            ("Date added", addedAt), ("PDF path", file),
        ]
        if let missing = required.first(where: { $0.1.trimmed.isEmpty }) {
            return "\(missing.0) is required."
        }
        guard hasValidCatalogFilePath else {
            return "PDF path must use Papers/Field/Title.pdf or Papers/Field/Subfolder/Title.pdf."
        }
        guard year.range(of: #"^\d{4}$"#, options: .regularExpression) != nil else {
            return "Year must contain four digits."
        }
        guard ["Preprint", "Poster", "Spotlight", "Oral"].contains(presentation) else {
            return "Presentation must be Preprint, Poster, Spotlight, or Oral."
        }
        if presentation != "Preprint" && track.trimmed.isEmpty {
            return "A published paper needs a track."
        }
        if track == "Workshop" && workshop.trimmed.isEmpty {
            return "The Workshop track needs a workshop name."
        }
        if track != "Workshop" && !workshop.trimmed.isEmpty {
            return "A workshop name can only be used with the Workshop track."
        }
        if !site.trimmed.isEmpty {
            guard let url = URL(string: site), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                return "Paper site must be a valid HTTP or HTTPS URL."
            }
        }
        guard addedAt.range(
            of: #"^\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}(?::\d{2})?)?$"#,
            options: .regularExpression
        ) != nil else {
            return "Date added must use YYYY-MM-DD or YYYY-MM-DD HH:MM:SS."
        }
        return nil
    }

    mutating func cleanEditableValues() {
        category = category.cleanedCell
        subcategory = subcategory.cleanedCell
        venue = venue.cleanedCell
        year = year.cleanedCell
        track = track.cleanedCell
        workshop = workshop.cleanedCell
        presentation = presentation.cleanedCell
        title = title.cleanedCell
        authors = authors.cleanedCell
        affiliation = affiliation.cleanedCell
        summary = summary.cleanedCell
        novelty = novelty.cleanedCell
        site = site.cleanedCell
        addedAt = addedAt.cleanedCell
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var cleanedCell: String {
        components(separatedBy: .newlines)
            .map(\.trimmed)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmed
    }

    var foldedForSearch: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }
}
