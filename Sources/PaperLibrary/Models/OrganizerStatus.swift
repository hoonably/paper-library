import Foundation

enum OrganizerStatusError: LocalizedError {
    case unsupportedValue(setting: String, value: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedValue(let setting, let value):
            "\(value) is not a supported \(setting) value."
        }
    }
}

struct AutomationDevice: Codable, Equatable {
    let id: String?
    let name: String
    let platform: String?
    let configuredAt: String?
}

private struct OrganizerSettingsDocument: Decodable {
    let automationDevice: AutomationDevice?
    let model: String?
    let reasoning: String?
    let language: String?
}

private struct RuntimeStatusDocument: Decodable {
    let mode: String?
    let phase: String?
    let model: String?
    let reasoning: String?
    let language: String?
    let configuredModel: String?
    let configuredReasoning: String?
    let configuredLanguage: String?
    let automationDevice: AutomationDevice?
    let machine: String?
    let currentFiles: [String]?
    let currentDisplayFiles: [String]?
    let queuedFiles: [String]?
    let lastCompletedAt: String?
    let lastError: String?
    let updatedAt: String?
}

private struct ProcessingPapersDocument: Decodable {
    let items: [ProcessingPaperStatus]
}

struct ProcessingPaperStatus: Codable, Equatable, Identifiable {
    let file: String
    let title: String?

    var id: String { file }

    var filename: String {
        (file as NSString).lastPathComponent
    }

    var displayTitle: String {
        let cleanedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cleanedTitle.isEmpty ? filename : cleanedTitle
    }

    var hasResolvedTitle: Bool {
        !(title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

enum OrganizerSetting: String {
    case model
    case reasoning
    case language

    var allowedValues: [String] {
        switch self {
        case .model: ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna"]
        case .reasoning: ["low", "medium", "high", "xhigh"]
        case .language: ["english", "korean", "chinese"]
        }
    }
}

struct OrganizerStatus: Equatable {
    var hasRuntimeStatus: Bool
    var phase: String
    var automationDeviceName: String
    var model: String
    var reasoning: String
    var language: String
    var activeFiles: [String]
    var queuedFiles: [String]
    var processingPapers: [ProcessingPaperStatus]
    var lastCompletedAt: String?
    var lastError: String
    var updatedAt: String?

    static let unavailable = OrganizerStatus(
        hasRuntimeStatus: false,
        phase: "offline",
        automationDeviceName: "Automation not configured",
        model: "gpt-5.6-terra",
        reasoning: "medium",
        language: "korean",
        activeFiles: [],
        queuedFiles: [],
        processingPapers: [],
        lastCompletedAt: nil,
        lastError: "",
        updatedAt: nil
    )

    var phaseLabel: String {
        switch phase {
        case "starting": "Starting organizer"
        case "checking": "Checking for new PDFs"
        case "queued": "Waiting to process"
        case "processing": "Processing with Codex"
        case "idle": "Ready for Finder"
        case "error": "Processing error"
        case "remote": "Using remote automation"
        case "offline": "Organizer unavailable"
        default: "Organizer unavailable"
        }
    }

    var detailText: String {
        var lines = [phaseLabel]
        if !activeFiles.isEmpty {
            lines.append("Processing: \(activeFiles.joined(separator: ", "))")
        }
        if !queuedFiles.isEmpty {
            lines.append("Queued: \(queuedFiles.joined(separator: ", "))")
        }
        if !lastError.isEmpty {
            lines.append(lastError)
        }
        if let updatedAt {
            lines.append("Last status update: \(updatedAt)")
        }
        lines.append("The organizer starts only when PDFs are added from Finder.")
        return lines.joined(separator: "\n")
    }
}

enum OrganizerStatusFile {
    private static let settingsPath = "Catalog/organizer-settings.json"
    private static let runtimePath = "Catalog/runtime-status.json"
    private static let processingPath = "Catalog/processing-papers.json"
    private static let staleAfter: TimeInterval = 120

    static func read(from root: URL, now: Date = Date()) -> OrganizerStatus {
        let settings: OrganizerSettingsDocument? = decodeJSON(
            at: root.appendingPathComponent(settingsPath)
        )
        let runtime: RuntimeStatusDocument? = decodeJSON(
            at: root.appendingPathComponent(runtimePath)
        )

        let processingDocument: ProcessingPapersDocument? = decodeJSON(
            at: root.appendingPathComponent(processingPath)
        )

        let configuredDevice = settings?.automationDevice ?? runtime?.automationDevice
        let runtimeIsFresh = runtime.flatMap { runtime in
            guard let value = runtime.updatedAt,
                  let updatedAt = try? Date(value, strategy: .iso8601)
            else { return false }
            return now.timeIntervalSince(updatedAt) <= staleAfter
        } ?? false
        let activePhases = ["starting", "checking", "queued", "processing"]
        let runtimeIsCurrent = runtime?.mode == "on-demand" && !activePhases.contains(runtime?.phase ?? "")
            ? runtime != nil
            : runtimeIsFresh
        let currentFiles = runtime?.currentFiles ?? []
        let progressByFile = (processingDocument?.items ?? []).reduce(
            into: [String: ProcessingPaperStatus]()
        ) { result, item in
            result[item.file] = item
        }
        let processingPapers = runtimeIsCurrent && runtime?.phase == "processing"
            ? currentFiles.map { progressByFile[$0] ?? ProcessingPaperStatus(file: $0, title: nil) }
            : []
        let activeFiles: [String]
        if !processingPapers.isEmpty {
            activeFiles = processingPapers.map(\.displayTitle)
        } else if runtime?.currentDisplayFiles?.isEmpty == false {
            activeFiles = runtime?.currentDisplayFiles ?? []
        } else {
            activeFiles = currentFiles
        }
        let connectionError: String
        if runtimeIsCurrent {
            connectionError = runtime?.lastError ?? ""
        } else if configuredDevice == nil {
            connectionError = "Paper Organizer has not been configured for this library."
        } else if runtime == nil {
            connectionError = "No organizer status has been received from the automation device yet."
        } else {
            connectionError = "No recent processing status was received. Run automation setup again if the organizer was interrupted."
        }

        return OrganizerStatus(
            hasRuntimeStatus: runtime != nil && runtimeIsCurrent,
            phase: runtimeIsCurrent ? runtime?.phase ?? "offline" : "offline",
            automationDeviceName: configuredDevice?.name ?? runtime?.machine ?? "Automation not configured",
            model: settings?.model ?? runtime?.configuredModel ?? runtime?.model ?? "gpt-5.6-terra",
            reasoning: settings?.reasoning ?? runtime?.configuredReasoning ?? runtime?.reasoning ?? "medium",
            language: settings?.language ?? runtime?.configuredLanguage ?? runtime?.language ?? "korean",
            activeFiles: runtimeIsCurrent ? activeFiles : [],
            queuedFiles: runtimeIsCurrent ? runtime?.queuedFiles ?? [] : [],
            processingPapers: processingPapers,
            lastCompletedAt: runtime?.lastCompletedAt,
            lastError: connectionError,
            updatedAt: runtime?.updatedAt
        )
    }

    static func update(_ setting: OrganizerSetting, value: String, in root: URL) throws {
        guard setting.allowedValues.contains(value) else {
            throw OrganizerStatusError.unsupportedValue(setting: setting.rawValue, value: value)
        }

        let url = root.appendingPathComponent(settingsPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "Paper Library automation has not been set up yet.",
            ])
        }
        let data = try Data(contentsOf: url)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSLocalizedDescriptionKey: "The organizer settings file is not a JSON object.",
            ])
        }

        object[setting.rawValue] = value
        object["updatedAt"] = ISO8601DateFormatter().string(from: Date())
        if setting == .language {
            // Native-app changes apply only to subsequently processed papers.
            object["catalogTranslation"] = NSNull()
        }

        let updated = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try updated.write(to: url, options: .atomic)
    }

    private static func decodeJSON<T: Decodable>(at url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
