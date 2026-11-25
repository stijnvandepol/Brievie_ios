#if os(iOS)
import BrievieUI
import SwiftUI

/// One letter in the post list: sender, date and pages, the persons it is addressed to, its labels, and
/// where it stands. An unread letter has a dot in the brand colour and a bold title (VoiceOver says "Ongelezen").
/// The letter status badge (host PR #50) will stand on the title line, after the dot and the title.
struct DocumentRowView: View {
    let row: DocumentsModel.Row
    @ScaledMetric(relativeTo: .headline) private var dotSize: CGFloat = 9

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if row.isUnread {
                    Circle()
                        .fill(BrievieColor.unread)
                        .frame(width: dotSize, height: dotSize)
                        .accessibilityHidden(true)
                }
                title
            }
            Text(row.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let addresseeLine = row.addresseeLine {
                Text(addresseeLine)
                    .font(.subheadline)
            }
            if !row.labels.isEmpty || row.isPossibleDuplicate {
                ChipFlow {
                    // As in the web: "Dubbel?" as a chip of its own colour, before the labels.
                    if row.isPossibleDuplicate {
                        LabelChip(name: DocumentStrings.duplicateChip, colorKey: LabelColor.orange.rawValue)
                    }
                    ForEach(row.labels) { label in
                        LabelChip(name: label.name, colorKey: label.colorKey)
                    }
                }
                .padding(.vertical, 2)
            }
            status
            if row.hasSuggestions {
                AdaptiveLabel(DocumentStrings.suggestion, systemImage: "lightbulb")
                    .font(.subheadline)
                    .foregroundStyle(BrievieColor.brand)
            }
            if row.isAutomatic {
                AdaptiveLabel(DocumentStrings.automaticByAI, systemImage: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One element, read in a fixed order: sender, date, status and its note, names, labels, proposal, "Dubbel?".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityValue(progressValue)
    }

    @ViewBuilder private var title: some View {
        let weight: Font.Weight = row.isUnread ? .bold : .semibold
        if row.titleIsProposal {
            // As in the web: italic, and "(voorstel)" in words, so it is never read as a fact.
            (Text(row.title).italic() + Text(verbatim: " ") + Text(DocumentStrings.proposedMark)
                .foregroundStyle(.secondary))
                .font(.headline.weight(weight))
        } else {
            Text(row.title)
                .font(.headline.weight(weight))
        }
    }

    private var progressValue: String {
        guard case let .uploading(progress) = row.status else { return "" }
        return progress.formatted(.percent.precision(.fractionLength(0)))
    }

    /// The status in words with its symbol, and its note under it (why, or that there is nothing to do).
    @ViewBuilder private var status: some View {
        switch row.status {
        case let .uploading(progress):
            ProgressView(value: progress) {
                Text(row.status.label)
                    .font(.subheadline)
            }
        case .uploadFailed, .failed:
            statusLabel(color: .red)
        case .needsReview, .needsName:
            statusLabel(color: .orange)
        case .done:
            statusLabel(color: .green)
        case .waitingForUpload, .processing:
            statusLabel(color: .secondary)
        }
        if let note = row.status.note {
            Text(note)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statusLabel(color: Color) -> some View {
        AdaptiveLabel {
            Text(row.status.label)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: row.status.iconName)
                .foregroundStyle(color)
        }
        .font(.subheadline)
    }
}
#endif
