#if os(iOS)
import SwiftUI

/// A message with an optional action, for errors and warnings. The message is read as one VoiceOver element.
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
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: style == .error ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(style == .error ? Color.red : Color.orange)
            }
            .accessibilityElement(children: .combine)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    VStack {
        ErrorBanner("We kunnen je server niet bereiken.", actionTitle: "Opnieuw proberen") {}
        ErrorBanner("Dit apparaat heeft geen toegangscode.", style: .warning)
    }
    .padding()
}
#endif
