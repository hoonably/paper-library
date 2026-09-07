import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var mainWindow: NSWindow?
    private var launchedForBackgroundAction = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isDefaultLaunch = (notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? NSNumber)?.boolValue
        launchedForBackgroundAction = isDefaultLaunch == false
        if launchedForBackgroundAction {
            NSApp.setActivationPolicy(.accessory)
            hideWindowsForBackgroundAction()
        }

        let store = LibraryStore.shared
        store.prepareManagedLibraryIfNeeded()
        if !launchedForBackgroundAction {
            store.migrateLegacyAutomationIfNeeded()
            UpdateController.shared.start()
            store.presentAutomationSetupIfNeeded()
        }
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.launchedForBackgroundAction {
                self.hideWindowsForBackgroundAction()
            } else {
                NSApp.windows.forEach { self.configureTitleBar(of: $0) }
            }
        }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if launchedForBackgroundAction {
            window.orderOut(nil)
            return
        }
        configureTitleBar(of: window)
    }

    private func hideWindowsForBackgroundAction() {
        NSApp.windows.forEach { $0.orderOut(nil) }
    }

    private func finishBackgroundAction(if needed: Bool) {
        guard needed else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSApp.terminate(nil)
        }
    }

    private func configureTitleBar(of window: NSWindow) {
        if mainWindow == nil {
            guard window.level == .normal, window.styleMask.contains(.titled) else { return }
            mainWindow = window
        }
        guard window === mainWindow else { return }
        window.toolbar = nil
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
    }

    @objc(moveToPaperLibrary:userData:error:)
    func moveToPaperLibrary(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let hasVisibleWindow = NSApp.windows.contains { $0.isVisible }
        let shouldTerminateAfterService = launchedForBackgroundAction || !hasVisibleWindow
        if shouldTerminateAfterService {
            launchedForBackgroundAction = true
            NSApp.setActivationPolicy(.accessory)
            hideWindowsForBackgroundAction()
        }
        defer { finishBackgroundAction(if: shouldTerminateAfterService) }

        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) ?? []
        let urls = objects.compactMap { ($0 as? NSURL).map { $0 as URL } }
        guard !urls.isEmpty else {
            errorPointer.pointee = "Select one or more PDF files in Finder." as NSString
            return
        }

        let store = LibraryStore.shared
        let result = store.moveIncomingPDFs(urls)
        var errors = result.failureSummary
        if !result.moved.isEmpty, let launchError = store.startOrganizerInBackground() {
            errors = [errors, launchError].filter { !$0.isEmpty }.joined(separator: "\n")
        }
        if !errors.isEmpty {
            errorPointer.pointee = errors as NSString
        }
    }
}
