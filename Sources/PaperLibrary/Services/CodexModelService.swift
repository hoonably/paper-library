import Darwin
import Foundation

enum CodexModelLookupResult: Sendable {
    case success(CodexModelCatalog)
    case failure(String)
}

enum CodexModelService {
    // Run off the main actor. The helper uses the same installed CLI as the organizer.
    static func fetch(in root: URL, node: URL) -> CodexModelLookupResult {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperLibraryModels-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temporary) }
            let outputURL = temporary.appendingPathComponent("models.json")
            let errorURL = temporary.appendingPathComponent("error.txt")
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            FileManager.default.createFile(atPath: errorURL.path, contents: nil)
            let output = try FileHandle(forWritingTo: outputURL)
            let errors = try FileHandle(forWritingTo: errorURL)
            defer { try? output.close(); try? errors.close() }

            let process = Process()
            process.executableURL = node
            process.arguments = [
                root.appendingPathComponent("Automation/paper-organizer.mjs").path,
                "models", "--root", root.path,
            ]
            process.currentDirectoryURL = root
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = errors
            try process.run()
            let timeout = DispatchWorkItem {
                guard process.isRunning else { return }
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 35, execute: timeout)
            process.waitUntilExit()
            timeout.cancel()

            guard process.terminationStatus == 0 else {
                let diagnostic = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
                let message = diagnostic.split(separator: "\n")
                    .last { $0.hasPrefix("Error: ") }
                    .map { String($0.dropFirst(7)) }
                return .failure(message ?? "Could not refresh Codex models. Check the CLI setup and try again.")
            }
            let data = try Data(contentsOf: outputURL)
            return .success(try CodexModelCatalog.decode(data))
        } catch {
            return .failure("Could not refresh Codex models: \(error.localizedDescription)")
        }
    }
}
