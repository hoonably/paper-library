import AppKit

extension Notification.Name {
    static let togglePaperLibrarySidebar = Notification.Name("TogglePaperLibrarySidebar")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let titlebarAccessoryID = NSUserInterfaceItemIdentifier("PaperLibraryFixedTitlebarControls")
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

        guard let closeButton = window.standardWindowButton(.closeButton),
              let zoomButton = window.standardWindowButton(.zoomButton),
              let titlebarView = closeButton.superview,
              !titlebarView.subviews.contains(where: { $0.identifier == titlebarAccessoryID })
        else { return }

        let sidebarButton = NSButton(
            image: NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle Sidebar") ?? NSImage(),
            target: self,
            action: #selector(toggleSidebar(_:))
        )
        sidebarButton.bezelStyle = .texturedRounded
        sidebarButton.controlSize = .regular
        sidebarButton.imagePosition = .imageOnly
        sidebarButton.imageScaling = .scaleProportionallyDown
        sidebarButton.toolTip = "Show or hide the sidebar"
        sidebarButton.setAccessibilityLabel("Toggle Sidebar")
        sidebarButton.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Paper Library")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .labelColor
        title.setContentHuggingPriority(.required, for: .horizontal)
        title.setContentCompressionResistancePriority(.required, for: .horizontal)

        let controls = NSStackView(views: [sidebarButton, title])
        controls.identifier = titlebarAccessoryID
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 9
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.setContentHuggingPriority(.required, for: .horizontal)
        titlebarView.addSubview(controls)
        NSLayoutConstraint.activate([
            sidebarButton.widthAnchor.constraint(equalToConstant: 30),
            sidebarButton.heightAnchor.constraint(equalToConstant: 24),
            controls.leadingAnchor.constraint(equalTo: zoomButton.trailingAnchor, constant: 10),
            controls.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            controls.widthAnchor.constraint(equalToConstant: 148),
            controls.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    @objc private func toggleSidebar(_ sender: Any?) {
        NotificationCenter.default.post(name: .togglePaperLibrarySidebar, object: nil)
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
        if !result.failures.isEmpty {
            errorPointer.pointee = result.failureSummary as NSString
        }
    }
}
