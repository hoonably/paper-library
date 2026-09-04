import SwiftUI

struct AutomationSetupView: View {
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                Image(systemName: "bolt.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 46, height: 46)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Set Up Paper Library")
                        .font(.title2.weight(.semibold))
                    Text("One quick setup enables Finder-triggered paper organization on this Mac.")
                        .foregroundStyle(.secondary)
                }
            }

            setupSection(number: "1", title: "Summary language") {
                Picker("Summary language", selection: $store.setupLanguage) {
                    Text("English").tag("english")
                    Text("Korean").tag("korean")
                    Text("中文").tag("chinese")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            setupSection(number: "2", title: "Codex CLI") {
                cliStatus
            }

            Divider()

            HStack {
                Button("Not Now") {
                    store.isShowingAutomationSetup = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    store.setUpAutomation()
                } label: {
                    HStack(spacing: 7) {
                        if store.isSettingUpAutomation {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(store.isSettingUpAutomation ? "Setting Up…" : "Finish Setup")
                    }
                    .frame(minWidth: 130)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(store.codexCLIReadiness.readyPath == nil || store.isSettingUpAutomation)
            }
        }
        .padding(28)
        .frame(width: 520)
    }

    @ViewBuilder
    private var cliStatus: some View {
        switch store.codexCLIReadiness {
        case .notChecked, .checking:
            statusRow(icon: "arrow.triangle.2.circlepath", color: .secondary) {
                Text("Checking Codex CLI and sign-in…")
                    .foregroundStyle(.secondary)
            } accessory: {
                ProgressView().controlSize(.small)
            }
        case .signingIn:
            statusRow(icon: "person.crop.circle", color: .accentColor) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Signing in to Codex…")
                        .fontWeight(.semibold)
                    Text("Complete the sign-in in your browser.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } accessory: {
                ProgressView().controlSize(.small)
            }
        case .ready:
            statusRow(icon: "checkmark.circle.fill", color: .green) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex CLI is ready")
                        .fontWeight(.semibold)
                    Text("The Codex app does not need to stay open after setup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .missing:
            statusRow(icon: "xmark.circle.fill", color: .red) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex CLI was not found")
                        .fontWeight(.semibold)
                    Link("Install Codex, then check again", destination: URL(string: "https://developers.openai.com/codex/cli")!)
                        .font(.caption)
                }
            } accessory: {
                retryButton
            }
        case .signedOut:
            statusRow(icon: "person.crop.circle.badge.exclamationmark", color: .orange) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex CLI is not signed in")
                        .fontWeight(.semibold)
                    Text("Sign in once to let the on-demand organizer use Codex.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } accessory: {
                Button("Sign In") {
                    store.signInToCodex()
                }
                .controlSize(.small)
            }
        case .runtimeMissing:
            statusRow(icon: "exclamationmark.triangle.fill", color: .orange) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex was found, but its local runtime is unavailable")
                        .fontWeight(.semibold)
                    Text("Install the Codex or ChatGPT desktop app, then check again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } accessory: {
                retryButton
            }
        case .failed(let message):
            statusRow(icon: "exclamationmark.triangle.fill", color: .red) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            } accessory: {
                retryButton
            }
        }
    }

    private var retryButton: some View {
        Button("Check Again") {
            store.checkCodexCLI()
        }
        .controlSize(.small)
    }

    private func setupSection<Content: View>(
        number: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(number)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(.tint, in: Circle())
                Text(title)
                    .font(.headline)
            }
            content()
                .padding(.leading, 30)
        }
    }

    private func statusRow<Content: View, Accessory: View>(
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            content()
            Spacer(minLength: 8)
            accessory()
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}
