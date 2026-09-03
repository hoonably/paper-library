import SwiftUI

struct PaperRowView: View {
    let paper: Paper

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(paper.title)
                .font(.headline)
                .lineLimit(3)

            Text(paper.authors)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 7) {
                Text(paper.venueLine)
                Spacer(minLength: 4)
                PresentationBadge(presentation: paper.presentation)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct PresentationBadge: View {
    let presentation: String

    var body: some View {
        Text(presentation)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.13), in: Capsule())
    }

    private var color: Color {
        switch presentation {
        case "Oral": .orange
        case "Spotlight": .purple
        case "Poster": .blue
        default: .secondary
        }
    }
}
