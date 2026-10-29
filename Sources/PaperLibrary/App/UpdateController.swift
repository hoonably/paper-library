import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdateController()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = true
    @Published private(set) var isChecking = false
    @Published private(set) var updateAvailable = false
    @Published private(set) var status = "Check for a newer version of Paper Library."

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil
    )
    private var observers: Set<AnyCancellable> = []
    private var hasStarted = false
    private var pendingCheck = false
    private var manualCheck = false
    private var updateWindow: NSWindow?
    private var installationTask: Task<Void, Never>?

    var isPackagedApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
            && Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") is String
    }

    var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version.map { "Current version · \($0)" } ?? "Development build"
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                guard let self else { return }
                self.canCheckForUpdates = value
                if value && self.pendingCheck { self.refreshUpdateInformation() }
            }
            .store(in: &observers)
        updaterController.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.automaticallyChecksForUpdates = $0 }
            .store(in: &observers)
        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates
        guard isPackagedApp else {
            status = "Update checks are available in the packaged app."
            return
        }
        updaterController.startUpdater()
    }

    func setAutomaticChecks(_ enabled: Bool) {
        // Sparkle persists this choice. It does not opt into automatic downloads.
        updaterController.updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates
    }

    func checkForUpdates() {
        start()
        if updateWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Updates"
            window.isReleasedWhenClosed = false
            let content = NSHostingView(rootView: UpdateSettingsView(updates: self).padding(28))
            window.contentView = content
            window.setContentSize(content.fittingSize)
            window.center()
            updateWindow = window
        }
        updateWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshUpdateInformation()
    }

    func refreshUpdateInformation() {
        guard isPackagedApp, !isChecking else { return }
        guard canCheckForUpdates, !updaterController.updater.sessionInProgress else {
            pendingCheck = true
            status = "Preparing to check for updates…"
            return
        }
        pendingCheck = false
        manualCheck = true
        isChecking = true
        updateAvailable = false
        status = "Checking for updates…"
        updaterController.updater.checkForUpdateInformation()
    }

    func showAvailableUpdate() {
        guard canCheckForUpdates else { return }
        updateWindow?.orderOut(nil)
        updaterController.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        guard manualCheck else { return }
        updateAvailable = true
        status = "Version \(item.displayVersionString) is available."
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        guard manualCheck else {
            if pendingCheck { DispatchQueue.main.async { [weak self] in self?.refreshUpdateInformation() } }
            return
        }
        manualCheck = false
        isChecking = false
        if let error = error as NSError?,
           !(error.domain == SUSparkleErrorDomain && error.code == Int(SUError.noUpdateError.rawValue)) {
            updateAvailable = false
            status = "Could not check for updates. Check your connection and try again."
        } else if !updateAvailable {
            status = "You’re using the latest version."
        }
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        postponeInstallationIfBusy(installHandler)
    }

    func postponeInstallationIfBusy(_ installHandler: @escaping () -> Void) -> Bool {
        // Finish in-app edits/setup before Sparkle replaces the running app.
        guard hasActiveLibraryTask else { return false }
        installationTask?.cancel()
        installationTask = Task { [weak self] in
            while let self, self.hasActiveLibraryTask, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            installHandler()
        }
        return true
    }

    private var hasActiveLibraryTask: Bool {
        let library = LibraryStore.shared
        return library.isSettingUpAutomation || library.isRunningLibraryCommand || library.isLoading
    }
}

struct UpdateSettingsView: View {
    @ObservedObject var updates: UpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(LibraryStyle.accent)
                    .frame(width: 48, height: 48)
                    .background(LibraryStyle.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Paper Library updates").font(.title2.weight(.semibold))
                    Text(updates.versionDescription).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 9) {
                if updates.isChecking { ProgressView().controlSize(.small) }
                Text(updates.status).font(.callout).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("update-status")
            }
            .frame(minHeight: 32, alignment: .leading)
            Divider()
            VStack(alignment: .leading, spacing: 7) {
                Toggle("Notify me about updates automatically", isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates },
                    set: { updates.setAutomaticChecks($0) }
                ))
                .toggleStyle(.checkbox)
                .accessibilityIdentifier("automatic-update-checks")
                Text("Checks while the app is open. This setting does not enable automatic downloads or installation.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Link("Version history", destination: URL(string: "https://github.com/hoonably/paper-library/releases")!)
                    .font(.callout)
                Spacer()
                Button(updates.updateAvailable ? "Review Update…" : "Check Now") {
                    if updates.updateAvailable { updates.showAvailableUpdate() }
                    else { updates.refreshUpdateInformation() }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!updates.canCheckForUpdates || updates.isChecking)
            }
        }
        .tint(LibraryStyle.accent)
        .frame(width: 404)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { updates.start() }
    }
}
