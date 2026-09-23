import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?
    private var isPerformingBackgroundService = false
    private var hasStartedForegroundSession = false
    private var backgroundTermination: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A non-default launch also includes restored windows, not just Services.
        // Enter background service mode only when the Finder service is invoked.
        LibraryStore.shared.prepareManagedLibraryIfNeeded()
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
            if self.isPerformingBackgroundService {
                self.hideWindowsForBackgroundAction()
            } else {
                NSApp.windows.forEach { self.configureTitleBar(of: $0) }
                if NSApp.isActive { self.beginForegroundSession() }
            }
        }
        // macOS can launch a SwiftUI WindowGroup without creating its first window.
        // A Finder service must stay windowless, but a normal launch needs a library window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, !self.isPerformingBackgroundService, self.mainWindow == nil,
                  !NSApp.windows.contains(where: { self.isLibraryWindow($0) && $0.isVisible })
            else { return }
            self.ensureLibraryWindowVisible()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        beginForegroundSession()
        ensureLibraryWindowVisible()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        beginForegroundSession()
        ensureLibraryWindowVisible()
        return false
    }

    private func ensureLibraryWindowVisible() {
        guard !isPerformingBackgroundService else { return }
        let window = mainWindow ?? NSApp.windows.first(where: isLibraryWindow)
            ?? LibraryWindowFactory.make(store: LibraryStore.shared)
        mainWindow = window
        configureTitleBar(of: window)
        if window.isMiniaturized { window.deminiaturize(nil) }
        if !window.isVisible { window.makeKeyAndOrderFront(nil) }
    }

    private func beginForegroundSession() {
        backgroundTermination?.cancel()
        backgroundTermination = nil
        isPerformingBackgroundService = false
        NSApp.setActivationPolicy(.regular)
        guard !hasStartedForegroundSession else { return }
        hasStartedForegroundSession = true
        let store = LibraryStore.shared
        store.prepareManagedLibraryIfNeeded()
        store.migrateLegacyAutomationIfNeeded()
        if store.isAutomationConfigured { store.refreshModels() }
        UpdateController.shared.start()
        store.presentAutomationSetupIfNeeded()
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        configureTitleBar(of: window)
    }

    private func hideWindowsForBackgroundAction() {
        NSApp.windows.forEach { $0.orderOut(nil) }
    }

    private func finishBackgroundAction(if needed: Bool) {
        guard needed else { return }
        backgroundTermination?.cancel()
        let termination = DispatchWorkItem { [weak self] in
            guard self?.isPerformingBackgroundService == true, !NSApp.isActive else { return }
            NSApp.terminate(nil)
        }
        backgroundTermination = termination
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: termination)
    }

    private func isLibraryWindow(_ window: NSWindow) -> Bool {
        window.level == .normal && window.styleMask.contains(.titled) && !(window is NSPanel)
    }

    private func configureTitleBar(of window: NSWindow) {
        if mainWindow == nil {
            guard isLibraryWindow(window) else { return }
            mainWindow = window
        }
        guard window === mainWindow else { return }
        window.toolbar = nil
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.isMovable = true
    }

    @objc(moveToPaperLibrary:userData:error:)
    func moveToPaperLibrary(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let hasVisibleWindow = NSApp.windows.contains {
            isLibraryWindow($0) && ($0.isVisible || $0.isMiniaturized)
        }
        let shouldTerminateAfterService = !NSApp.isActive && (!hasStartedForegroundSession || !hasVisibleWindow)
        if shouldTerminateAfterService {
            isPerformingBackgroundService = true
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
