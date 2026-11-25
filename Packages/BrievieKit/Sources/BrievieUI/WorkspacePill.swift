#if os(iOS)
import SwiftUI

/// The current workspace at the top left of every tab: its initial in a brand-coloured circle, its name and, when
/// there is another workspace to switch to, a chevron. With one workspace it is a label, never a button that does
/// nothing (the web's "dead switch"). One VoiceOver element ("Werkruimte: Thuis, kies een andere").
public struct WorkspacePill: View {
    @ScaledMetric(relativeTo: .subheadline) private var initialSize: CGFloat = 26
    private let name: String
    private let accessibilityText: String
    private let action: (() -> Void)?

    /// - Parameter action: opens the workspace picker; `nil` with one workspace.
    public init(name: String, accessibilityLabel: String, action: (() -> Void)?) {
        self.name = name
        accessibilityText = accessibilityLabel
        self.action = action
    }

    /// The first letter of the name, upper case; a dot for an empty name.
    public static func initial(of name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "·"
    }

    public var body: some View {
        if let action {
            Button(action: action) { pill(showsChevron: true) }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText)
                .accessibilityAddTraits(.isButton)
        } else {
            pill(showsChevron: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityText)
        }
    }

    private func pill(showsChevron: Bool) -> some View {
        HStack(spacing: 6) {
            Text(Self.initial(of: name))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(BrievieColor.onBrand)
                .frame(width: initialSize, height: initialSize)
                .background(BrievieColor.brand, in: Circle())
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                // In a navigation bar the item is offered almost no width: without this the name shrank to nothing
                // and only the initial showed.
                .fixedSize()
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, showsChevron ? 10 : 12)
        .padding(.vertical, 4)
        .background(BrievieColor.card, in: Capsule())
    }
}

#if DEBUG
private struct WorkspacePillPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkspacePill(name: "Thuis", accessibilityLabel: "Werkruimte: Thuis, kies een andere", action: {})
            WorkspacePill(name: "Bedrijf", accessibilityLabel: "Werkruimte: Bedrijf", action: nil)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrievieColor.surface)
    }
}

#Preview("Light") { WorkspacePillPreview() }
#Preview("Dark") { WorkspacePillPreview().preferredColorScheme(.dark) }
#Preview("AX5") { WorkspacePillPreview().dynamicTypeSize(.accessibility5) }
#endif
#endif
