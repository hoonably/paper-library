import SwiftUI

struct PaperEditorView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var draft: Paper
    @State private var validationMessage: String?
    @State private var confirmingDelete = false

    let paper: Paper
    let onSave: (Paper) -> Bool
    let onCancel: () -> Void
    let onDelete: () -> Bool

    init(
        paper: Paper,
        onSave: @escaping (Paper) -> Bool,
        onCancel: @escaping () -> Void,
        onDelete: @escaping () -> Bool
    ) {
        self.paper = paper
        _draft = State(initialValue: paper)
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        labeledField("Field") {
                            TextField("Field", text: $draft.category)
                        }
                        labeledField("Subfolder") {
                            TextField("Optional", text: $draft.subcategory)
                        }
                    }

                    labeledField("Title") {
                        TextField("Title", text: $draft.title, axis: .vertical)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .lineLimit(1...3)
                    }

                    labeledField("Authors") {
                        TextField("Authors", text: $draft.authors, axis: .vertical)
                            .font(.title3)
                            .lineLimit(1...4)
                    }

                    HStack(spacing: 10) {
                        Button("Open PDF", systemImage: "doc.richtext") {
                            store.openPDF(paper)
                        }
                        .buttonStyle(.borderedProminent)

                        if !paper.site.isEmpty {
                            Button("Paper Site", systemImage: "safari") {
                                store.openSite(paper)
                            }
                        }

                        Button("Show in Finder", systemImage: "folder") {
                            store.revealPDF(paper)
                        }

                        Spacer()

                        Button("Cancel", action: cancel)
                            .keyboardShortcut(.cancelAction)
                        Button("Save", action: save)
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    }

                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }

                Divider()

                EditorSection(title: "Summary", systemImage: "text.alignleft") {
                    editor(text: $draft.summary)
                }

                EditorSection(title: "What’s new", systemImage: "sparkles") {
                    editor(text: $draft.novelty)
                }

                EditorSection(title: "Publication", systemImage: "building.columns") {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                        editorRow("Venue", text: $draft.venue)
                        editorRow("Year", text: $draft.year)
                        editorRow("Track", text: $draft.track)
                        editorRow("Workshop", text: $draft.workshop)
                        GridRow {
                            rowLabel("Presentation")
                            Picker("Presentation", selection: $draft.presentation) {
                                ForEach(["Preprint", "Poster", "Spotlight", "Oral"], id: \.self) { value in
                                    Text(value).tag(value)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                }

                EditorSection(title: "Affiliations", systemImage: "person.3") {
                    editor(text: $draft.affiliation, minimumHeight: 70)
                }

                EditorSection(title: "Library", systemImage: "archivebox") {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                        editorRow("Paper Site", text: $draft.site)
                        editorRow("Added", text: $draft.addedAt)
                        GridRow {
                            rowLabel("File")
                            Text(draft.file)
                                .textSelection(.enabled)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("Delete Paper…", systemImage: "trash", role: .destructive) {
                        confirmingDelete = true
                    }
                }
            }
            .frame(maxWidth: 780, alignment: .leading)
            .padding(34)
        }
        .confirmationDialog(
            "Move this PDF to the Trash?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Move PDF to Trash and Remove Entry", role: .destructive) {
                _ = onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the catalog entry. The PDF remains recoverable from the Trash.")
        }
    }

    private func save() {
        var cleaned = draft
        cleaned.cleanEditableValues()
        draft = cleaned
        if let error = cleaned.validationError() {
            validationMessage = error
            return
        }
        if onSave(cleaned) {
            validationMessage = nil
        }
    }

    private func cancel() {
        draft = paper
        validationMessage = nil
        onCancel()
    }

    private func editor(text: Binding<String>, minimumHeight: CGFloat = 90) -> some View {
        TextEditor(text: text)
            .font(.body)
            .frame(minHeight: minimumHeight)
            .padding(6)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.separator.opacity(0.65), lineWidth: 1)
            }
    }

    @ViewBuilder
    private func labeledField<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func editorRow(_ label: String, text: Binding<String>) -> some View {
        GridRow {
            rowLabel(label)
            TextField(label, text: text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
        }
    }

    private func rowLabel(_ label: String) -> some View {
        Text(label)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct EditorSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
                .padding(.leading, 26)
        }
    }
}
