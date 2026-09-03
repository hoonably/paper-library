import Foundation

enum CatalogCSVError: LocalizedError, Equatable {
    case empty
    case unclosedQuote
    case invalidHeader(String)
    case invalidColumnCount(row: Int, expected: Int, actual: Int)
    case emptyFile(row: Int)
    case invalidFile(row: Int, path: String)
    case duplicateFile(String)
    case invalidYear(row: Int)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "The catalog CSV is empty."
        case .unclosedQuote:
            return "The catalog CSV contains an unclosed quote."
        case .invalidHeader(let header):
            return "The catalog CSV header is not supported: \(header)"
        case .invalidColumnCount(let row, let expected, let actual):
            return "CSV row \(row) has \(actual) columns; expected \(expected)."
        case .emptyFile(let row):
            return "CSV row \(row) has an empty PDF path."
        case .invalidFile(let row, let path):
            return "CSV row \(row) has a PDF path outside paper/: \(path)"
        case .duplicateFile(let path):
            return "The catalog contains a duplicate PDF path: \(path)"
        case .invalidYear(let row):
            return "The year in CSV row \(row) must contain four digits."
        }
    }
}

enum CSVCodec {
    static let headers = [
        "category", "subcategory", "venue", "year", "track", "workshop", "presentation",
        "title", "authors", "affiliation", "summary", "novelty", "site", "added_at", "file",
    ]

    private static let legacyHeaders: [[String]] = {
        func withStatus(_ source: [String]) -> [String] {
            var copy = source
            copy.insert("status", at: copy.firstIndex(of: "presentation")! + 1)
            return copy
        }
        return [
            withStatus(headers),
            withStatus(headers.filter { $0 != "added_at" }),
            withStatus(headers.filter { !["novelty", "added_at"].contains($0) }),
            withStatus(headers.filter { !["subcategory", "novelty", "added_at"].contains($0) }),
        ]
    }()

    static func decode(_ text: String) throws -> [Paper] {
        var rows = try parse(text)
        guard !rows.isEmpty else { throw CatalogCSVError.empty }
        rows[0][0] = rows[0][0].replacingOccurrences(of: "\u{FEFF}", with: "")
        let actualHeaders = rows.removeFirst()
        guard let sourceHeaders = ([headers] + legacyHeaders).first(where: { $0 == actualHeaders }) else {
            throw CatalogCSVError.invalidHeader(actualHeaders.joined(separator: ","))
        }

        var seenFiles = Set<String>()
        return try rows.enumerated().map { index, values in
            let rowNumber = index + 2
            guard values.count == sourceHeaders.count else {
                throw CatalogCSVError.invalidColumnCount(
                    row: rowNumber,
                    expected: sourceHeaders.count,
                    actual: values.count
                )
            }
            let record = Dictionary(uniqueKeysWithValues: zip(sourceHeaders, values))
            let file = record["file"] ?? ""
            guard !file.isEmpty else { throw CatalogCSVError.emptyFile(row: rowNumber) }
            guard seenFiles.insert(file).inserted else { throw CatalogCSVError.duplicateFile(file) }

            let rawPresentation = record["presentation"] ?? ""
            let presentation: String
            if ["Preprint", "Poster", "Spotlight", "Oral"].contains(rawPresentation) {
                presentation = rawPresentation
            } else if (record["status"] ?? "").contains("Preprint") || record["venue"] == "Technical Report" {
                presentation = "Preprint"
            } else if record["venue"] == "OSDI" {
                presentation = "Oral"
            } else {
                presentation = "Poster"
            }

            let paper = Paper(
                category: record["category"] ?? "",
                subcategory: record["subcategory"] ?? "",
                venue: record["venue"] ?? "",
                year: record["year"] ?? "",
                track: record["track"] ?? "",
                workshop: record["workshop"] ?? "",
                presentation: presentation,
                title: record["title"] ?? "",
                authors: record["authors"] ?? "",
                affiliation: record["affiliation"] ?? "",
                summary: record["summary"] ?? "",
                novelty: record["novelty"] ?? "",
                site: record["site"] ?? "",
                addedAt: record["added_at"] ?? "",
                file: file
            )
            guard paper.hasValidCatalogFilePath else {
                throw CatalogCSVError.invalidFile(row: rowNumber, path: file)
            }
            return paper
        }
    }

    static func encode(_ papers: [Paper]) throws -> String {
        var lines = [headers.joined(separator: ",")]
        for (index, paper) in papers.enumerated() {
            let row = index + 2
            guard paper.hasValidCatalogFilePath else {
                throw CatalogCSVError.invalidFile(row: row, path: paper.file)
            }
            guard paper.year.range(of: #"^\d{4}$"#, options: .regularExpression) != nil else {
                throw CatalogCSVError.invalidYear(row: row)
            }
            let values: [String: String] = [
                "category": paper.category, "subcategory": paper.subcategory,
                "venue": paper.venue, "year": paper.year, "track": paper.track,
                "workshop": paper.workshop, "presentation": paper.presentation,
                "title": paper.title, "authors": paper.authors,
                "affiliation": paper.affiliation, "summary": paper.summary,
                "novelty": paper.novelty, "site": paper.site,
                "added_at": paper.addedAt, "file": paper.file,
            ]
            lines.append(headers.map { header in
                let value = values[header] ?? ""
                return header == "year" ? value : quote(value)
            }.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func quote(_ value: String) -> String {
        let flattened = value.replacingOccurrences(of: #"\s*\r?\n\s*"#, with: " ", options: .regularExpression)
        return "\"\(flattened.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func parse(_ text: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if quoted {
                if character == "\"", index + 1 < characters.count, characters[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else if character == "\"" {
                    quoted = false
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                quoted = true
            } else if character == "," {
                row.append(field)
                field = ""
            } else if character == "\n" || character == "\r\n" || character == "\r" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(character)
            }
            index += 1
        }

        guard !quoted else { throw CatalogCSVError.unclosedQuote }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows.filter { $0.contains(where: { !$0.isEmpty }) }
    }
}
