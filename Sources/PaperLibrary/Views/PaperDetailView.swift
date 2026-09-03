import SwiftUI

struct PaperDetailView: View {
    @EnvironmentObject private var store: LibraryStore
    let paper: Paper
    let edit: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 9) {
                        Text(paper.categoryPath)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                        PresentationBadge(presentation: paper.presentation)
                    }

                    Text(paper.title)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .textSelection(.enabled)

                    Text(paper.authors)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

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

                        Button("Edit", systemImage: "pencil", action: edit)
                    }
                }

                Divider()

                DetailSection(title: "Summary", systemImage: "text.alignleft") {
                    Text(paper.summary)
                        .font(.body)
                        .textSelection(.enabled)
                }

                DetailSection(title: "What’s new", systemImage: "sparkles") {
                    Text(paper.novelty)
                        .font(.body)
                        .textSelection(.enabled)
                }

                DetailSection(title: "Publication", systemImage: "building.columns") {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                        metadataRow("Venue", paper.venue)
                        metadataRow("Year", paper.year)
                        metadataRow("Track", paper.track.isEmpty ? "—" : paper.track)
                        if !paper.workshop.isEmpty { metadataRow("Workshop", paper.workshop) }
                        metadataRow("Presentation", paper.presentation)
                    }
                }

                DetailSection(title: "Affiliations", systemImage: "person.3") {
                    Text(paper.affiliation)
                        .textSelection(.enabled)
                }

                DetailSection(title: "Library", systemImage: "archivebox") {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                        metadataRow("Added", paper.addedAt)
                        metadataRow("File", paper.file)
                    }
                }
            }
            .frame(maxWidth: 780, alignment: .leading)
            .padding(34)
        }
    }

    @ViewBuilder
    private func metadataRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

private struct DetailSection<Content: View>: View {
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
