import SwiftUI

struct OrganizerStatusHeader: View {
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        HStack(spacing: 8) {
            Label("Paper Library", systemImage: "books.vertical.fill")
                .font(.title3.weight(.semibold))
                .lineLimit(1)

            if store.isAutomationConfigured {
                statusBadge
            } else {
                Button {
                    store.presentAutomationSetup()
                } label: {
                    HStack(spacing: 8) {
                        if store.isSettingUpAutomation {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "bolt.fill")
                                .foregroundStyle(.tint)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(store.isSettingUpAutomation ? "Setting Up…" : "Set Up Automation")
                                .font(.callout.weight(.semibold))
                            Text("Required once")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(store.isSettingUpAutomation)
                .help("Configure the organizer that runs when PDFs are added from Finder.")
            }

            Spacer(minLength: 8)

            SettingMenu(
                title: "MODEL",
                value: store.organizerStatus.model,
                choices: OrganizerSetting.model.allowedValues,
                displayName: modelName,
                recommendedValue: "gpt-5.6-terra"
            ) { store.updateOrganizerSetting(.model, to: $0) }
            .disabled(!store.isAutomationConfigured || store.isSettingUpAutomation)

            SettingMenu(
                title: "REASONING",
                value: store.organizerStatus.reasoning,
                choices: OrganizerSetting.reasoning.allowedValues,
                displayName: reasoningName,
                recommendedValue: "medium"
            ) { store.updateOrganizerSetting(.reasoning, to: $0) }
            .disabled(!store.isAutomationConfigured || store.isSettingUpAutomation)

            SettingMenu(
                title: "LANGUAGE",
                value: store.organizerStatus.language,
                choices: OrganizerSetting.language.allowedValues,
                displayName: languageName,
                recommendedValue: nil
            ) { store.updateOrganizerSetting(.language, to: $0) }
            .disabled(!store.isAutomationConfigured || store.isSettingUpAutomation)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .shadow(color: statusColor.opacity(0.45), radius: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(store.organizerStatus.automationDeviceName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(store.organizerStatus.phaseLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .help(store.organizerStatus.detailText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Automation device \(store.organizerStatus.automationDeviceName), \(store.organizerStatus.phaseLabel)")
    }

    private var statusColor: Color {
        guard store.organizerStatus.hasRuntimeStatus else { return .gray }
        switch store.organizerStatus.phase {
        case "error": return .red
        case "starting", "checking", "queued": return .orange
        case "processing": return .blue
        default: return .green
        }
    }

    private func modelName(_ value: String) -> String {
        switch value {
        case "gpt-5.6-sol": "GPT-5.6 Sol"
        case "gpt-5.6-terra": "GPT-5.6 Terra"
        case "gpt-5.6-luna": "GPT-5.6 Luna"
        default: value
        }
    }

    private func reasoningName(_ value: String) -> String {
        value == "xhigh" ? "XHigh" : value.capitalized
    }

    private func languageName(_ value: String) -> String {
        switch value {
        case "korean": "Korean"
        case "chinese": "Chinese"
        case "english": "English"
        default: value.capitalized
        }
    }
}

private struct SettingMenu: View {
    let title: String
    let value: String
    let choices: [String]
    let displayName: (String) -> String
    let recommendedValue: String?
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(choices, id: \.self) { choice in
                Button {
                    onSelect(choice)
                } label: {
                    if choice == value {
                        Label(optionName(choice), systemImage: "checkmark")
                    } else {
                        Text(optionName(choice))
                    }
                }
            }
        } label: {
            HStack(spacing: 9) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(optionName(value))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.separator.opacity(0.55), lineWidth: 1)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .layoutPriority(1)
        .help("Applies to papers processed after this setting is synchronized to the automation device.")
    }

    private func optionName(_ choice: String) -> String {
        displayName(choice) + (choice == recommendedValue ? " ★" : "")
    }
}
