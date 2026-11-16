#if os(iOS)
import BrievieCore
import BrievieUI
import SwiftUI

/// "Op naam van" and "Labels" in the review: what is chosen (with where a proposal came from), the proposals
/// still open, and a row that opens the full list.
struct OrganiseSection: View {
    @Binding var draft: OrganiseDraft
    let persons: [Person]
    let labels: [DocumentLabel]
    let onPickPersons: () -> Void
    let onPickLabels: () -> Void
    let onShowQuote: (String) -> Void

    var body: some View {
        Section {
            if chosenPersons.isEmpty, openPersons.isEmpty {
                Text(DocumentStrings.noAddressee)
                    .foregroundStyle(.secondary)
            }
            ForEach(chosenPersons) { person in
                let origin = draft.origin(ofAddressee: person.id)
                ChoiceRow(origin: origin, name: person.displayName, onShowQuote: onShowQuote) {
                    Button {
                        draft.setAddressees(draft.addresseeIDs.subtracting([person.id]))
                    } label: {
                        PersonChip(name: person.displayName, isChosen: true)
                    }
                    .accessibilityLabel(String(format: DocumentStrings.chosenPersonFormat, person.displayName))
                }
            }
            ForEach(openPersons, id: \.0.id) { suggestion, person in
                ChoiceRow(origin: suggestion, name: person.displayName, onShowQuote: onShowQuote) {
                    Button {
                        draft.toggle(suggestion)
                    } label: {
                        PersonChip(name: person.displayName, isChosen: false)
                    }
                    .accessibilityLabel(String(format: DocumentStrings.addFormat, person.displayName))
                }
            }
            Button(DocumentStrings.pickPersons, action: onPickPersons)
        } header: {
            Text(DocumentStrings.addressees)
        }
        Section {
            ForEach(chosenLabels) { label in
                ChoiceRow(origin: draft.origin(ofLabel: label.id), name: label.name, onShowQuote: onShowQuote) {
                    Button {
                        draft.setLabels(draft.labelIDs.subtracting([label.id]))
                    } label: {
                        HStack(spacing: 6) {
                            LabelChip(name: label.name, colorKey: label.colorKey)
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel(String(format: DocumentStrings.chosenLabelFormat, label.name))
                }
            }
            ForEach(openLabels, id: \.0.id) { suggestion, label in
                ChoiceRow(origin: suggestion, name: label.name, onShowQuote: onShowQuote) {
                    Button {
                        draft.toggle(suggestion)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                            LabelChip(name: label.name, colorKey: label.colorKey)
                                .opacity(0.7)
                        }
                    }
                    .accessibilityLabel(String(format: DocumentStrings.addFormat, label.name))
                }
            }
            Button(DocumentStrings.pickLabels, action: onPickLabels)
        } header: {
            Text(DocumentStrings.labels)
        }
    }

    // Chosen ones in the order of the workspace's lists; a proposal whose person or label is gone is not shown.
    private var chosenPersons: [Person] { persons.filter { draft.addresseeIDs.contains($0.id) } }
    private var chosenLabels: [DocumentLabel] { labels.filter { draft.labelIDs.contains($0.id) } }

    private var openPersons: [(Suggestion, Person)] {
        draft.openSuggestions(for: .addAddressee).compactMap { suggestion in
            persons.first { $0.id == suggestion.targetID }.map { (suggestion, $0) }
        }
    }

    private var openLabels: [(Suggestion, DocumentLabel)] {
        draft.openSuggestions(for: .addLabel).compactMap { suggestion in
            labels.first { $0.id == suggestion.targetID }.map { (suggestion, $0) }
        }
    }
}

/// One person or label: its chip, then where a proposal came from and "Waar staat dit?" when it has a quote.
private struct ChoiceRow<Chip: View>: View {
    let origin: Suggestion?
    /// The person's or label's name, so VoiceOver says which proposal a source belongs to.
    let name: String
    let onShowQuote: (String) -> Void
    @ViewBuilder let chip: () -> Chip

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            chip()
                .buttonStyle(.borderless)
            if let origin {
                Label(Self.text(of: origin), systemImage: Self.icon(of: origin.origin))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(name). \(Self.text(of: origin))")
                if !origin.quote.isEmpty {
                    Button {
                        onShowQuote(origin.quote)
                    } label: {
                        Label(DocumentStrings.whereIsThis, systemImage: "text.magnifyingglass")
                    }
                    .font(.footnote)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("\(name). \(DocumentStrings.whereIsThis)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func text(of suggestion: Suggestion) -> String {
        switch suggestion.origin {
        case .ai: DocumentStrings.originAI
        case .nameMatch: DocumentStrings.originNameMatch
        case .rule: String(format: DocumentStrings.originRuleFormat, suggestion.ruleName)
        case .unknown: DocumentStrings.suggestion
        }
    }

    private static func icon(of origin: SuggestionOrigin) -> String {
        switch origin {
        case .ai: "sparkles"
        case .nameMatch: "text.magnifyingglass"
        case .rule: "gearshape"
        case .unknown: "lightbulb"
        }
    }
}

/// A person as a rounded chip: filled with a remove mark when chosen, outlined with a plus when proposed.
private struct PersonChip: View {
    let name: String
    let isChosen: Bool

    var body: some View {
        HStack(spacing: 4) {
            if isChosen {
                Image(systemName: "person.fill")
            } else {
                Image(systemName: "plus")
            }
            Text(name)
                .fixedSize(horizontal: false, vertical: true)
            if isChosen {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(isChosen ? Color.primary : Color.accentColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(isChosen ? Color.secondary.opacity(0.15) : Color.clear)
        }
        .overlay {
            Capsule()
                .strokeBorder(isChosen ? Color.clear : Color.accentColor, lineWidth: 1)
        }
    }
}
#endif
