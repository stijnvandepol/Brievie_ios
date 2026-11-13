import SwiftUI

/// Placeholder root; switches on `AppModel.state` once the app model exists (Task 6).
struct RootView: View {
    var body: some View {
        Text("app.name")
            .font(.largeTitle)
    }
}

#Preview {
    RootView()
}
