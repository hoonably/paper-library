import SwiftUI

@main
struct PaperLibraryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = LibraryStore.shared
    @StateObject private var updateController = UpdateController.shared

    var body: some Scene {
        WindowGroup("") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 980, minHeight: 640)
                .task {
                    store.prepareManagedLibraryIfNeeded()
                }
        }
        .defaultSize(width: 1280, height: 780)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updateController.checkForUpdates()
                }
                .disabled(!updateController.canCheckForUpdates)
            }

            CommandGroup(after: .newItem) {
                Button("Reload Catalog") {
                    store.reload()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(!store.hasLibrary)

                Button("Set Up Automation…") {
                    store.presentAutomationSetup()
                }
                .disabled(!store.hasLibrary || store.isSettingUpAutomation)

                Divider()

                Button("Show App Storage") {
                    store.revealStorage()
                }
            }
        }
    }
}

@MainActor
enum LibraryWindowFactory {
    static func make(store: LibraryStore) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: ContentView()
            .environmentObject(store)
            .frame(minWidth: 980, minHeight: 640))
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
