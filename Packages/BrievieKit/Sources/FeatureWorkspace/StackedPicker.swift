#if os(iOS)
import SwiftUI

/// A menu picker whose label goes above its value at the accessibility text sizes. Side by side, the label was cut
/// ("Eerste mel…" at the largest size, seen in the simulator, 21-11-2026).
struct StackedPicker<Value: Hashable, Options: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let title: String
    private let selection: Binding<Value>
    private let options: Options

    init(_ title: String, selection: Binding<Value>, @ViewBuilder options: () -> Options) {
        self.title = title
        self.selection = selection
        self.options = options()
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
                Picker(title, selection: selection) { options }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityLabel(title)
            }
        } else {
            Picker(title, selection: selection) { options }
        }
    }
}
#endif
