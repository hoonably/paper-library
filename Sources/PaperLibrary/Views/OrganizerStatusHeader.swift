import AppKit
import SwiftUI

struct OrganizerStatusHeader: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var isShowingLibraryCommand = false

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

            Button {
                isShowingLibraryCommand.toggle()
            } label: {
                Image(systemName: "message.fill")
                    .font(.callout.weight(.semibold))
                    .frame(width: 34, height: 34)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.separator.opacity(0.55), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(!store.isAutomationConfigured || store.isSettingUpAutomation)
            .help("Ask Codex to correct metadata or reorganize papers.")
            .accessibilityLabel("Edit library with Codex")
            .popover(isPresented: $isShowingLibraryCommand, arrowEdge: .top) {
                LibraryCommandPopover()
                    .environmentObject(store)
            }
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
            Text(store.organizerStatus.phaseLabel)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        .help(store.organizerStatus.detailText)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Organizer status: \(store.organizerStatus.phaseLabel)")
    }

    private var statusColor: Color {
        guard store.organizerStatus.hasRuntimeStatus else { return .gray }
        switch store.organizerStatus.phase {
        case "error": return .red
        case "starting", "checking", "queued": return .orange
        case "processing", "editing": return .blue
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

private struct LibraryCommandPopover: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var instruction = ""
    @State private var hasInteractedWithEditor = false
    @State private var focusRequest = 0

    private var canSend: Bool {
        !instruction.trimmed.isEmpty && !store.isRunningLibraryCommand
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "message.fill")
                    .foregroundStyle(.tint)
                Text("Edit Library with Codex")
                    .font(.headline)
            }

            Text("Describe a metadata correction or how papers should be reorganized. Write in any language.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ZStack(alignment: .topLeading) {
                LibraryCommandTextEditor(text: $instruction, focusRequest: focusRequest) {
                    hasInteractedWithEditor = true
                }
                if instruction.isEmpty && !hasInteractedWithEditor {
                    Text("For example: This paper was published at ICML, not arXiv.\nCreate a Speculative Decoding subcategory and move the relevant papers into it.")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(11)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            hasInteractedWithEditor = true
                            focusRequest += 1
                        }
                }
            }
                .frame(height: 112)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(.separator.opacity(0.55), lineWidth: 1)
                }

            if store.isRunningLibraryCommand {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Codex is reviewing the library…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if let message = store.libraryCommandMessage {
                ScrollView {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxHeight: 120)
            } else if let error = store.libraryCommandError {
                ScrollView {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxHeight: 120)
            }

            HStack {
                Button(store.isRunningLibraryCommand ? "Close" : "Cancel") {
                    dismiss()
                }
                Spacer()
                Button("Send") {
                    store.sendLibraryInstruction(instruction)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSend)
            }
        }
        .padding(16)
        .frame(width: 420)
        .onAppear {
            store.clearLibraryCommandFeedback()
            hasInteractedWithEditor = !instruction.isEmpty
        }
    }
}

private struct LibraryCommandTextEditor: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    let onInteraction: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true

        let textView = InteractionTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = false
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: 7, height: 9)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.onInteraction = onInteraction
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? InteractionTextView else { return }
        textView.onInteraction = onInteraction
        if textView.string != text {
            textView.string = text
        }
        guard context.coordinator.lastFocusRequest != focusRequest else { return }
        context.coordinator.lastFocusRequest = focusRequest
        DispatchQueue.main.async { [weak textView] in
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
            textView.scrollRangeToVisible(textView.selectedRange())
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        var lastFocusRequest = 0

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }

    final class InteractionTextView: NSTextView {
        var onInteraction: (() -> Void)?

        override var undoManager: UndoManager? { nil }

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            DispatchQueue.main.async { [weak self] in
                self?.onInteraction?()
            }
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
        .help("Applies to papers processed after this setting is saved.")
    }

    private func optionName(_ choice: String) -> String {
        displayName(choice) + (choice == recommendedValue ? " ★" : "")
    }
}
