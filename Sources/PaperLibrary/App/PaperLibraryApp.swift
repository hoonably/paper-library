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

                Button("Show PDF Folder") {
                    store.revealPapers()
                }

                Button("Show App Storage") {
                    store.revealStorage()
                }
            }
        }

        Settings {
            LibrarySettingsView()
                .environmentObject(store)
                .tint(LibraryStyle.accent)
        }
    }
}

private struct LibrarySettingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @StateObject private var updates = UpdateController.shared

    var body: some View {
        TabView {
            UpdateSettingsView(updates: updates)
                .padding(28)
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
            VStack(alignment: .leading, spacing: 20) {
                Text("Library & access").font(.title2.weight(.semibold))
                Text("PDFs are saved in Documents / Paper Library / Papers. Catalog data and automation settings stay in Application Support on this Mac.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Show PDF Folder") { store.revealPapers() }
                    Button("Show App Storage") { store.revealStorage() }
                }.disabled(!store.hasLibrary)
                Divider()
                Text("Documents access lets Paper Library save and open your PDFs. Full Disk Access is not required.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                Button("Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
                }
                Button("Set Up Automation…") { store.presentAutomationSetup() }
                    .disabled(!store.hasLibrary || store.isSettingUpAutomation)
            }
            .frame(width: 404).padding(28)
            .tabItem { Label("Library", systemImage: "folder") }
        }
        .frame(width: 460, height: 420)
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
