import Foundation

enum OrganizerRecommendation {
    static let model = "gpt-6-luna"
    static let reasoning = "xhigh"
}

struct CodexModel: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
    let reasoningEfforts: [String]
    let defaultReasoningEffort: String

    func compatibleReasoning(preferred: String) -> String {
        reasoningEfforts.contains(preferred) ? preferred : defaultReasoningEffort
    }

    static func isValidID(_ value: String) -> Bool {
        value.range(of: #"\A[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}\z"#, options: .regularExpression) != nil
    }

    static func isValidReasoning(_ value: String) -> Bool {
        value.range(of: #"\A[a-z][a-z0-9_-]{0,31}\z"#, options: .regularExpression) != nil
    }

    static func name(for id: String) -> String {
        guard id.hasPrefix("gpt-") else { return id }
        let parts = id.dropFirst(4).split(separator: "-", maxSplits: 1)
        return "GPT-" + parts.enumerated().map { $0.offset == 0 ? String($0.element) : $0.element.capitalized }.joined(separator: " ")
    }
}

struct CodexModelCatalog: Codable, Equatable, Sendable {
    let version: Int
    let codexPath: String
    let fetchedAt: String
    let models: [CodexModel]

    private static let cachePath = "Catalog/codex-models.json"

    func model(withID id: String) -> CodexModel? {
        models.first { $0.id == id }
    }

    static func decode(_ data: Data) throws -> CodexModelCatalog {
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        guard catalog.version == 1, !catalog.codexPath.isEmpty, !catalog.models.isEmpty,
              Set(catalog.models.map(\.id)).count == catalog.models.count,
              catalog.models.allSatisfy({ model in
                  CodexModel.isValidID(model.id) && !model.displayName.isEmpty
                      && !model.reasoningEfforts.isEmpty
                      && model.reasoningEfforts.allSatisfy(CodexModel.isValidReasoning)
                      && model.reasoningEfforts.contains(model.defaultReasoningEffort)
              })
        else { throw CocoaError(.fileReadCorruptFile) }
        return catalog
    }

    static func read(from root: URL) -> CodexModelCatalog? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent(cachePath)) else { return nil }
        return try? decode(data)
    }

    func save(in root: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: root.appendingPathComponent(Self.cachePath), options: .atomic)
    }
}
