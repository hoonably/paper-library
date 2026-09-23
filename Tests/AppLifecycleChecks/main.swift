import AppKit

// Exercise the real delegate without opening windows, running Codex, or touching
// the user's library. These stand-ins cover only its non-window dependencies.
@MainActor
final class LibraryStore {
    static let shared = LibraryStore()
    var foregroundSetupCount = 0
    var modelRefreshCount = 0
    func prepareManagedLibraryIfNeeded() {}
    func migrateLegacyAutomationIfNeeded() {}
    func presentAutomationSetupIfNeeded() { foregroundSetupCount += 1 }
    var isAutomationConfigured: Bool { true }
    func refreshModels() { modelRefreshCount += 1 }
    func moveIncomingPDFs(_ urls: [URL]) -> (failureSummary: String, moved: [URL]) {
        ("", [])
    }
    func startOrganizerInBackground() -> String? { nil }
}

@MainActor
final class UpdateController {
    static let shared = UpdateController()
    func start() {}
}

@MainActor
final class TestApplication: NSApplication {
    var terminationCount = 0
    private var simulatedActivationPolicy: NSApplication.ActivationPolicy = .prohibited

    func prepareHeadless() {
        _ = super.setActivationPolicy(.prohibited)
    }

    // Keep the lifecycle assertions without registering this command-line test
    // as a regular Dock app on the developer's Mac.
    override func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        simulatedActivationPolicy = activationPolicy
        return true
    }

    override func activationPolicy() -> NSApplication.ActivationPolicy {
        simulatedActivationPolicy
    }

    override func terminate(_ sender: Any?) { terminationCount += 1 }
}

@MainActor
final class TestWindow: NSWindow {
    var hideCount = 0
    var showCount = 0
    override func orderOut(_ sender: Any?) { hideCount += 1 }
    override func makeKeyAndOrderFront(_ sender: Any?) { showCount += 1 }
}

@MainActor
enum LibraryWindowFactory {
    static func make(store: LibraryStore) -> NSWindow {
        TestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
    }
}

@main
struct AppLifecycleChecks {
    @MainActor
    static func main() {
        let app = TestApplication.shared as! TestApplication
        app.prepareHeadless()
        let window = TestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
            styleMask: [.titled, .closable], backing: .buffered, defer: true
        )
        window.isReleasedWhenClosed = false

        for launchValue: Bool? in [false, true, nil] {
            let delegate = AppDelegate()
            var info: [AnyHashable: Any] = [:]
            if let launchValue {
                info[NSApplication.launchIsDefaultUserInfoKey] = NSNumber(value: launchValue)
            }
            let previousHideCount = window.hideCount
            delegate.applicationDidFinishLaunching(Notification(
                name: NSApplication.didFinishLaunchingNotification, object: app, userInfo: info
            ))
            for _ in 0..<3 {
                NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)
            }
            precondition(window.hideCount == previousHideCount, "Focusing a restored window hid it")

            let previousSetups = LibraryStore.shared.foregroundSetupCount
            let previousRefreshes = LibraryStore.shared.modelRefreshCount
            delegate.applicationDidBecomeActive(Notification(
                name: NSApplication.didBecomeActiveNotification, object: app
            ))
            delegate.applicationDidBecomeActive(Notification(
                name: NSApplication.didBecomeActiveNotification, object: app
            ))
            precondition(LibraryStore.shared.foregroundSetupCount == previousSetups + 1,
                         "Foreground setup must run once per session")
            precondition(LibraryStore.shared.modelRefreshCount == previousRefreshes + 1,
                         "Model catalog must refresh once per foreground app launch")
            NotificationCenter.default.removeObserver(delegate)
        }

        // A service can finish just as the user opens the app. Reopening must
        // restore normal presentation and cancel its pending automatic exit.
        let serviceDelegate = AppDelegate()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        var serviceError: NSString?
        let previousHideCount = window.hideCount
        serviceDelegate.moveToPaperLibrary(pasteboard, userData: nil, error: &serviceError)
        precondition(serviceError != nil, "Empty Finder input must report an error")
        precondition(window.hideCount > previousHideCount, "A background service did not hide its window")
        precondition(app.activationPolicy() == .accessory, "A background service appeared as a regular app")
        let previousShowCount = window.showCount
        let shouldUseDefaultReopen = serviceDelegate.applicationShouldHandleReopen(app, hasVisibleWindows: false)
        precondition(!shouldUseDefaultReopen && window.showCount == previousShowCount + 1,
                     "Reopening did not show the existing window")
        precondition(app.activationPolicy() == .regular, "Reopening left the app in background mode")
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        precondition(app.terminationCount == 0, "The service terminated an explicitly reopened app")

        let backgroundDelegate = AppDelegate()
        backgroundDelegate.moveToPaperLibrary(pasteboard, userData: nil, error: &serviceError)
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        precondition(app.terminationCount == 1, "A completed background service did not exit")
        print("App lifecycle checks passed (restored-window focus, foreground setup, service exit, reopen recovery).")
    }
}
