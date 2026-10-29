import AppKit
import SwiftUI

enum LibraryStyle { static let accent = Color.green }

@MainActor
final class LibraryStore {
    static let shared = LibraryStore()
    var isSettingUpAutomation = false
    var isRunningLibraryCommand = false
    var isLoading = false
}

@main
struct UpdatePreferencesChecks {
    @MainActor
    static func main() async {
        guard let identifier = Bundle.main.bundleIdentifier,
              identifier.hasPrefix("com.hoonably.PaperLibrary.UpdateChecks.") else {
            fatalError("The check must use an isolated bundle ID")
        }
        let defaults = UserDefaults.standard
        let updates = UpdateController.shared
        updates.start()
        switch CommandLine.arguments.last {
        case "disable":
            precondition(updates.automaticallyChecksForUpdates, "The fresh app must offer automatic notifications")
            updates.setAutomaticChecks(false)
            precondition(!updates.automaticallyChecksForUpdates, "The UI state did not follow disabling checks")
            precondition(!defaults.bool(forKey: "SUEnableAutomaticChecks"), "Sparkle did not persist the disabled choice")
        case "relaunch":
            precondition(!updates.automaticallyChecksForUpdates, "Relaunch reset the saved user preference")
            updates.setAutomaticChecks(true)
            precondition(updates.automaticallyChecksForUpdates, "The UI state did not follow enabling checks")
            precondition(defaults.bool(forKey: "SUEnableAutomaticChecks"), "Sparkle did not persist the enabled choice")
            precondition(!defaults.bool(forKey: "SUAutomaticallyUpdate"), "Enabling notifications also enabled downloads")
            var installations = 0
            precondition(!updates.postponeInstallationIfBusy { installations += 1 },
                         "Idle updates should use Sparkle’s normal installation flow")
            LibraryStore.shared.isRunningLibraryCommand = true
            precondition(updates.postponeInstallationIfBusy { installations += 1 },
                         "An active catalog edit was interrupted by an update")
            try? await Task.sleep(for: .milliseconds(50))
            precondition(installations == 0, "Installation began during an active catalog edit")
            LibraryStore.shared.isRunningLibraryCommand = false
            try? await Task.sleep(for: .milliseconds(1200))
            precondition(installations == 1, "Installation did not resume after the edit completed")
            defaults.removePersistentDomain(forName: identifier)
        default: fatalError("Expected disable or relaunch")
        }
        defaults.synchronize()
        print("Update preference check passed: \(CommandLine.arguments.last!)")
    }
}
