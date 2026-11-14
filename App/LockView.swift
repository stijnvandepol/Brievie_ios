import BrievieUI
import SwiftUI

/// Shown while the app is locked: the brand, one short line and one button that asks for Face ID or the
/// device passcode.
struct LockView: View {
    let unlock: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                BrandMark(name: String(localized: "app.name"))
                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                    .foregroundStyle(BrievieColor.brand)
                    .accessibilityHidden(true)
                Text("lock.title")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text("lock.subtitle")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                PrimaryButton(String(localized: "lock.unlock"), action: unlock)
                    .padding(.top, 8)
                    .accessibilityHint(Text("lock.unlock.hint"))
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(.systemGroupedBackground))
    }
}

/// Covers the screen so the app switcher snapshot shows no content.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.background)
            Text("app.name")
                .font(.largeTitle.bold())
        }
        .ignoresSafeArea()
    }
}

#Preview {
    LockView {}
}
