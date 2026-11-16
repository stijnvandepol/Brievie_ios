#if os(iOS)
import BrievieUI
import SwiftUI

/// One letter in the post list: sender, date and pages, the persons it is addressed to, its labels, and
/// where it stands.
struct DocumentRowView: View {
    let row: DocumentsModel.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.title)
                .font(.headline)
            Text(row.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let addresseeLine = row.addresseeLine {
                Text(addresseeLine)
                    .font(.subheadline)
            }
            if !row.labels.isEmpty {
                ChipFlow {
                    ForEach(row.labels) { label in
                        LabelChip(name: label.name, colorKey: label.colorKey)
                    }
                }
                .padding(.vertical, 2)
            }
            status
            if row.hasSuggestions {
                Label(DocumentStrings.suggestion, systemImage: "lightbulb")
                    .font(.subheadline)
                    .foregroundStyle(BrievieColor.brand)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One element, read in a fixed order: sender, date, status, names, labels, proposal.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityValue(progressValue)
    }

    private var progressValue: String {
        guard case let .uploading(progress) = row.status else { return "" }
        return progress.formatted(.percent.precision(.fractionLength(0)))
    }

    @ViewBuilder private var status: some View {
        switch row.status {
        case let .uploading(progress):
            ProgressView(value: progress) {
                Text(row.status.label)
                    .font(.subheadline)
            }
        case let .uploadFailed(message, _):
            statusLabel(color: .red)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .failed:
            statusLabel(color: .red)
        case .needsReview:
            statusLabel(color: .orange)
        case .done:
            statusLabel(color: .green)
        case .waitingForUpload, .processing:
            statusLabel(color: .secondary)
        }
    }

    private func statusLabel(color: Color) -> some View {
        Label {
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
