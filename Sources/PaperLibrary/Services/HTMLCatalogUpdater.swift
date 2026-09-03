import Foundation

enum HTMLCatalogUpdater {
    private static let startMarker = "/* CATALOG_DATA_START */"
    private static let endMarker = "/* CATALOG_DATA_END */"

    /// Returns false when the optional legacy HTML viewer is not present.
    static func update(papers: [Paper], at htmlURL: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: htmlURL.path) else { return false }
        let html = try String(contentsOf: htmlURL, encoding: .utf8)
        guard let start = html.range(of: startMarker),
              let end = html.range(of: endMarker, range: start.upperBound..<html.endIndex) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSLocalizedDescriptionKey: "Catalog markers are missing from papers.html.",
            ])
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        var json = String(decoding: try encoder.encode(papers), as: UTF8.self)
        json = json
            .replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let block = """
        \(startMarker)
            const CATALOG = \(json);
            const GENERATED_AT = "\(timestamp)";
            \(endMarker)
        """
        let updated = html[..<start.lowerBound] + block + html[end.upperBound...]
        try String(updated).write(to: htmlURL, atomically: true, encoding: .utf8)
        return true
    }
}
