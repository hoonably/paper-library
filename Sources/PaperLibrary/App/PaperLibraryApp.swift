import SwiftUI

@main
struct PaperLibraryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = LibraryStore.shared

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
