import SwiftUI

/// Shown while the app is locked: one button that asks for Face ID or the device passcode.
struct LockView: View {
    let unlock: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("lock.title")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Button(action: unlock) {
                    Text("lock.unlock")
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityHint(Text("lock.unlock.hint"))
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
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
