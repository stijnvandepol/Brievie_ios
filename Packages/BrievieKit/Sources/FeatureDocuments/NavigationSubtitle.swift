#if os(iOS)
import SwiftUI

extension View {
    /// The workspace's name under the title, from iOS 26 (before it, the title names it:
    /// `DocumentStrings.navigationTitle`).
    @ViewBuilder
    func workspaceSubtitle(_ name: String?) -> some View {
        if #available(iOS 26, *), let name {
            navigationSubtitle(name)
        } else {
            self
        }
    }
}
#endif
