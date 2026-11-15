#if os(iOS)
import SwiftUI

/// A plain inline message with an SF Symbol and an optional action, for errors and warnings.
/// The symbol differs per style, so the meaning never rests on colour alone. The message is read as one
/// VoiceOver element.
public struct ErrorBanner: View {
    public enum Style {
        case error
        case warning
    }

    private let message: String
    private let style: Style
    private let actionTitle: String?
    private let action: () -> Void

    public init(
        _ message: String,
        style: Style = .error,
        actionTitle: String? = nil,
        action: @escaping () -> Void = {}
    ) {
        self.message = message
        self.style = style
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(message)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: style == .error ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(style == .error ? Color.red : Color.orange)
            }
            .accessibilityElement(children: .combine)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    List {
        ErrorBanner("We kunnen je server niet bereiken.", actionTitle: "Opnieuw proberen") {}
        ErrorBanner("Dit apparaat heeft geen toegangscode.", style: .warning)
    }
}
#endif
