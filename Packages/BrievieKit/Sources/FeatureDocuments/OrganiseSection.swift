#if os(iOS)
import BrievieCore
import BrievieUI
import SwiftUI

/// What the user can do in `OrganiseSection`; a screen without it (a viewer) shows everything plain.
struct OrganiseActions {
    /// What tapping an open proposal does.
    enum Proposals {
        /// The review: a tap takes the proposal into the draft.
        case toggle((Suggestion) -> Void)
        /// A confirmed letter: "Toevoegen" and "Negeren", sent at once.
        case acceptOrDismiss(accept: (Suggestion) -> Void, dismiss: (Suggestion) -> Void)
    }

    /// Takes the letter off one name; the receiver works from its own current state, not from this view's.
    let removeAddressee: (UUID) -> Void
    let removeLabel: (UUID) -> Void
    let proposals: Proposals
    let pickPersons: () -> Void
    let pickLabels: () -> Void

    /// The review: every change goes into the draft that "Bevestigen" sends.
    static func review(
        _ draft: Binding<OrganiseDraft>, pickPersons: @escaping () -> Void, pickLabels: @escaping () -> Void
    ) -> Self {
        Self(
            removeAddressee: { id in
                draft.wrappedValue.setAddressees(draft.wrappedValue.addresseeIDs.subtracting([id]))
            },
            removeLabel: { id in draft.wrappedValue.setLabels(draft.wrappedValue.labelIDs.subtracting([id])) },
            proposals: .toggle { draft.wrappedValue.toggle($0) },
            pickPersons: pickPersons,
            pickLabels: pickLabels
        )
    }
}

/// "Op naam van" and "Labels": what is chosen (with where a proposal came from), the proposals still open,
/// and a row that opens the full list. Without `actions` it only shows.
struct OrganiseSection: View {
    let draft: OrganiseDraft
    let persons: [Person]
    let labels: [DocumentLabel]
    let actions: OrganiseActions?
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
                    if let actions {
                        Button {
                            actions.removeAddressee(person.id)
                        } label: {
                            PersonChip(name: person.displayName, isChosen: true, isEditable: true)
                        }
                        .accessibilityLabel(String(format: DocumentStrings.chosenPersonFormat, person.displayName))
                    } else {
                        PersonChip(name: person.displayName, isChosen: true, isEditable: false)
                    }
                }
            }
            ForEach(openPersons, id: \.0.id) { suggestion, person in
                ChoiceRow(origin: suggestion, name: person.displayName, onShowQuote: onShowQuote) {
                    proposal(suggestion, name: person.displayName) { isEditable in
                        PersonChip(name: person.displayName, isChosen: false, isEditable: isEditable)
                    }
                }
            }
            if let actions {
                Button(DocumentStrings.pickPersons, action: actions.pickPersons)
            }
        } header: {
            Text(DocumentStrings.addressees)
        }
        Section {
            ForEach(chosenLabels) { label in
                ChoiceRow(origin: draft.origin(ofLabel: label.id), name: label.name, onShowQuote: onShowQuote) {
                    if let actions {
                        Button {
                            actions.removeLabel(label.id)
                        } label: {
                            HStack(spacing: 6) {
                                LabelChip(name: label.name, colorKey: label.colorKey)
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityLabel(String(format: DocumentStrings.chosenLabelFormat, label.name))
                    } else {
                        LabelChip(name: label.name, colorKey: label.colorKey)
                    }
                }
            }
            ForEach(openLabels, id: \.0.id) { suggestion, label in
                ChoiceRow(origin: suggestion, name: label.name, onShowQuote: onShowQuote) {
                    proposal(suggestion, name: label.name) { isEditable in
                        HStack(spacing: 6) {
                            if isEditable {
                                Image(systemName: "plus.circle")
                            }
                            LabelChip(name: label.name, colorKey: label.colorKey)
                                .opacity(0.7)
                        }
                    }
                }
            }
            if let actions {
                Button(DocumentStrings.pickLabels, action: actions.pickLabels)
            }
        } header: {
            Text(DocumentStrings.labels)
        }
    }

    /// An open proposal: a chip to tap in the review, a chip with "Toevoegen" and "Negeren" on a confirmed
    /// letter, the plain chip for a viewer. Always with the word "Voorstel", so it never differs from a chosen
    /// one by its look alone; VoiceOver says it too.
    @ViewBuilder
    private func proposal<Chip: View>(
        _ suggestion: Suggestion, name: String, @ViewBuilder chip: (_ isEditable: Bool) -> Chip
    ) -> some View {
        switch actions?.proposals {
        case let .toggle(toggle):
            Button {
                toggle(suggestion)
            } label: {
                ProposalMarked(chip: chip(true))
            }
            .accessibilityLabel(String(format: DocumentStrings.addFormat, name))
            .accessibilityValue(DocumentStrings.suggestion)
        case let .acceptOrDismiss(accept, dismiss):
            VStack(alignment: .leading, spacing: 6) {
                ProposalMarked(chip: chip(false))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(name). \(DocumentStrings.suggestion)")
                HStack(spacing: 16) {
                    Button(DocumentStrings.acceptSuggestion) { accept(suggestion) }
                        .accessibilityLabel(String(format: DocumentStrings.addFormat, name))
                    Button(DocumentStrings.dismissSuggestion) { dismiss(suggestion) }
                        .accessibilityLabel(String(format: DocumentStrings.dismissFormat, name))
                }
                .font(.subheadline.weight(.medium))
            }
        case nil:
            ProposalMarked(chip: chip(false))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(name). \(DocumentStrings.suggestion)")
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

/// A proposed person or label: its chip and the word "Voorstel" in a small tag (text, not colour).
private struct ProposalMarked<Chip: View>: View {
    let chip: Chip

    var body: some View {
        HStack(spacing: 8) {
            chip
            Text(DocumentStrings.suggestion)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.secondary, lineWidth: 1)
                }
        }
    }
}

/// A person as a rounded chip: filled when chosen, outlined when proposed. When it can be tapped, a chosen one
/// has a remove mark and a proposed one a plus.
private struct PersonChip: View {
    let name: String
    let isChosen: Bool
    let isEditable: Bool

    var body: some View {
        HStack(spacing: 4) {
            if isChosen {
                Image(systemName: "person.fill")
            } else if isEditable {
                Image(systemName: "plus")
            }
            Text(name)
                .fixedSize(horizontal: false, vertical: true)
            if isChosen, isEditable {
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
