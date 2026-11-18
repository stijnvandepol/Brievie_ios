#if os(iOS)
import BrievieUI
import SwiftUI

/// The sheet behind a `brievie://server` link: the address the app will contact and a field for the pairing code,
/// or one sentence when the link cannot be used. Renders `ServerLinkModel`; nothing is sent until "Koppel".
public struct ServerLinkView: View {
    @Bindable private var model: ServerLinkModel
    @FocusState private var codeIsFocused: Bool

    public init(model: ServerLinkModel) {
        self.model = model
    }

    private var isPairing: Bool {
        if case .offer(_, _, isPairing: true) = model.presentation { true } else { false }
    }

    private var failure: String? {
        if case let .offer(_, failure, _) = model.presentation { failure } else { nil }
    }

    public var body: some View {
        NavigationStack {
            List {
                header
                switch model.presentation {
                case let .notice(message):
                    notice(message)
                case let .offer(address, failure, isPairing):
                    offer(address: address, failure: failure, isPairing: isPairing)
                case nil:
                    EmptyView()
                }
            }
            .listStyle(.insetGrouped)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { model.dismiss() } label: {
                        Text("pairing.link.close", bundle: .module)
                    }
                    .disabled(isPairing)
                }
            }
        }
        .interactiveDismissDisabled(isPairing)
        .onAppear { focusCodeIfOffered() }
        .onChange(of: model.presentation) { old, new in
            if case .offer = new, !isOffer(old) { focusCodeIfOffered() }
        }
        .onChange(of: failure) { _, message in
            if let message { AccessibilityNotification.Announcement(message).post() }
        }
    }

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                BrandMark(name: String(localized: "pairing.brand", bundle: .module))
                Text("pairing.link.title", bundle: .module)
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
        }
    }

    @ViewBuilder private func notice(_ message: String) -> some View {
        Section {
            ErrorBanner(message, style: message == PairingStrings.linkAlreadyPaired ? .warning : .error)
        } footer: {
            PrimaryButton(String(localized: "pairing.link.close", bundle: .module)) {
                model.dismiss()
            }
            .padding(.horizontal, -16)
            .padding(.top, 12)
        }
    }

    @ViewBuilder private func offer(address: String, failure: String?, isPairing: Bool) -> some View {
        Section {
            Text("pairing.link.intro", bundle: .module)
                .fixedSize(horizontal: false, vertical: true)
        }
        addressSection(address)
        codeSection(isPairing: isPairing)
        if failure != nil || isPairing {
            Section {
                if let failure {
                    ErrorBanner(failure)
                }
                if isPairing {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("pairing.progress", bundle: .module)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        // The button sits in a section footer: a list row would clip it with its own rounded corners.
        Section {
        } footer: {
            PrimaryButton(String(localized: "pairing.link.submit", bundle: .module)) {
                model.submit()
            }
            .disabled(!model.canSubmit)
            .padding(.horizontal, -16)
        }
    }

    /// What the app will contact, in full and wrapping: the user checks it before typing the code.
    private func addressSection(_ address: String) -> some View {
        Section {
            Text(verbatim: address)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        } header: {
            Text("pairing.link.address.label", bundle: .module)
        } footer: {
            Text("pairing.link.address.check", bundle: .module)
        }
    }

    private func codeSection(isPairing: Bool) -> some View {
        Section {
            TextField(text: $model.code, prompt: Text("pairing.link.code.prompt", bundle: .module)) {
                Text("pairing.link.code.label", bundle: .module)
            }
            .focused($codeIsFocused)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            .textContentType(nil)
            .submitLabel(.go)
            .onSubmit { model.submit() }
            .monospaced()
            .disabled(isPairing)
            .accessibilityLabel(Text("pairing.link.code.label", bundle: .module))
            .accessibilityHint(Text("pairing.link.code.hint", bundle: .module))
        } header: {
            Text("pairing.link.code.label", bundle: .module)
        } footer: {
            Text("pairing.link.code.footer", bundle: .module)
        }
    }

    private func isOffer(_ presentation: ServerLinkModel.Presentation?) -> Bool {
        if case .offer = presentation { true } else { false }
    }

    private func focusCodeIfOffered() {
        if isOffer(model.presentation) { codeIsFocused = true }
    }
}
#endif
