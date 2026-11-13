#if os(iOS)
import BrievieUI
import SwiftUI

/// The pairing screen: camera scanner, with a paste field as fallback (simulator, no camera access, VoiceOver).
public struct PairingView: View {
    private let model: PairingModel
    /// Why the user is here again, for example "this device was disconnected".
    private let notice: String?

    @State private var showsManualEntry = false
    @State private var manualText = ""

    public init(model: PairingModel, notice: String?) {
        self.model = model
        self.notice = notice
    }

    private var scannerIsAvailable: Bool { QRScannerView.isAvailable }
    private var isManual: Bool { showsManualEntry || !scannerIsAvailable }
    private var isPairing: Bool { model.phase == .pairing }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("pairing.title", bundle: .module)
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(isManual ? "pairing.instructions.manual" : "pairing.instructions", bundle: .module)
                    .foregroundStyle(.secondary)
                if let notice {
                    ErrorBanner(notice, style: .warning)
                }
                if case .failed(let message, let canRetry) = model.phase {
                    ErrorBanner(
                        message,
                        actionTitle: canRetry ? String(localized: "pairing.retry", bundle: .module) : nil
                    ) {
                        Task { await model.retry() }
                    }
                }
                if isManual {
                    manualEntry
                } else {
                    scanner
                }
                if isPairing {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("pairing.progress", bundle: .module)
                    }
                    .accessibilityElement(children: .combine)
                }
                if scannerIsAvailable {
                    Button {
                        showsManualEntry.toggle()
                    } label: {
                        Text(showsManualEntry ? "pairing.paste.hide" : "pairing.paste.show", bundle: .module)
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
        }
    }

    private var scanner: some View {
        QRScannerView { text in
            Task { await model.scanned(text) }
        }
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityLabel(Text("pairing.scanner.label", bundle: .module))
    }

    private var manualEntry: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(
                String(localized: "pairing.manual.field", bundle: .module),
                text: $manualText,
                axis: .vertical
            )
            .lineLimit(3...8)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .keyboardType(.asciiCapable)
            .accessibilityLabel(Text("pairing.manual.field", bundle: .module))
            PrimaryButton(String(localized: "pairing.manual.submit", bundle: .module)) {
                Task { await model.submitManual(manualText) }
            }
            .disabled(manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPairing)
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                Task { await model.submitManual(text) }
            }
            .disabled(isPairing)
        }
    }
}
#endif
