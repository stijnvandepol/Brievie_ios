#if os(iOS)
import BrievieUI
import SwiftUI

/// The pairing screen: a short explanation, then "Scan QR-code" (camera in a sheet) or "Plak koppelgegevens"
/// (paste fallback: simulator, no camera access, VoiceOver). The model decides what the camera does; this
/// view renders it.
public struct PairingView: View {
    private let model: PairingModel
    /// Why the user is here again, for example "this device was disconnected".
    private let notice: String?

    @Environment(\.scenePhase) private var scenePhase
    @State private var showsManualEntry = false
    @State private var showsScanner = false
    @State private var manualText = ""

    public init(model: PairingModel, notice: String?) {
        self.model = model
        self.notice = notice
    }

    private var cameraIsUsable: Bool { model.camera == .scanning }
    private var isManual: Bool {
        showsManualEntry || model.camera == .denied || model.camera == .restricted || model.camera == .unavailable
    }
    private var isPairing: Bool { model.phase == .pairing }

    public var body: some View {
        List {
            header
            messages
            Section {
                LabeledContent {
                    Text("pairing.prerequisite.network.value", bundle: .module)
                } label: {
                    Text("pairing.prerequisite.network", bundle: .module)
                }
                LabeledContent {
                    Text("pairing.prerequisite.code.value", bundle: .module)
                        .monospacedDigit()
                } label: {
                    Text("pairing.prerequisite.code", bundle: .module)
                }
            } header: {
                Text("pairing.prerequisites.header", bundle: .module)
            } footer: {
                Text("pairing.prerequisites.footer", bundle: .module)
            }
            actions
            if isManual {
                manualEntry
            }
        }
        .listStyle(.insetGrouped)
        // Runs when the screen appears and again whenever the app becomes active (the permission may have
        // been changed in Settings). Cancelled with the view; it never touches a pairing.
        .task(id: scenePhase) {
            if scenePhase == .active {
                await model.prepareCamera()
            }
        }
        .sheet(isPresented: $showsScanner) { scannerSheet }
        // The camera can stop being usable while the sheet is open (permission revoked, scanner failed).
        .onChange(of: model.camera) { _, camera in
            if camera != .scanning { showsScanner = false }
        }
    }

    private var header: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                BrandMark(name: String(localized: "pairing.brand", bundle: .module))
                Text("pairing.title", bundle: .module)
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("pairing.instructions", bundle: .module)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
        }
    }

    @ViewBuilder private var messages: some View {
        let showsAny = notice != nil || model.phase != .scanning || model.camera == .denied
            || model.camera == .restricted
        if showsAny {
            Section {
                if let notice {
                    ErrorBanner(notice, style: .warning)
                }
                if case .failed(let message, let canRetry) = model.phase {
                    ErrorBanner(
                        message,
                        actionTitle: canRetry ? String(localized: "pairing.retry", bundle: .module) : nil
                    ) {
                        model.startRetry()
                    }
                }
                if model.camera == .denied {
                    ErrorBanner(
                        String(localized: "pairing.camera.denied", bundle: .module),
                        style: .warning,
                        actionTitle: String(localized: "pairing.camera.openSettings", bundle: .module)
                    ) {
                        model.openSettings()
                    }
                }
                if model.camera == .restricted {
                    ErrorBanner(String(localized: "pairing.camera.restricted", bundle: .module), style: .warning)
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
    }

    private var actions: some View {
        Section {
            PrimaryButton(String(localized: "pairing.scan", bundle: .module)) {
                showsScanner = true
            }
            .disabled(!cameraIsUsable || isPairing)
            if !isManual {
                SecondaryButton(String(localized: "pairing.paste.show", bundle: .module)) {
                    showsManualEntry = true
                }
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    private var scannerSheet: some View {
        NavigationStack {
            QRScannerView(
                onScan: { code in
                    showsScanner = false
                    model.startPairing(scanned: code)
                },
                onFailure: {
                    showsScanner = false
                    model.scannerFailed()
                }
            )
            .ignoresSafeArea(edges: .bottom)
            .accessibilityLabel(Text("pairing.scanner.label", bundle: .module))
            .navigationTitle(Text("pairing.scan", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { showsScanner = false } label: {
                        Text("pairing.scanner.cancel", bundle: .module)
                    }
                }
            }
        }
    }

    private var manualEntry: some View {
        Section {
            TextField(
                String(localized: "pairing.manual.field", bundle: .module),
                text: $manualText,
                axis: .vertical
            )
            .lineLimit(3...8)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .keyboardType(.asciiCapable)
            .accessibilityLabel(Text("pairing.manual.field", bundle: .module))
            PrimaryButton(String(localized: "pairing.manual.submit", bundle: .module)) {
                model.startPairing(pasted: manualText)
            }
            .listRowSeparator(.hidden)
            .disabled(manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPairing)
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                model.startPairing(pasted: text)
            }
            .disabled(isPairing)
        } header: {
            Text("pairing.manual.header", bundle: .module)
        }
    }
}
#endif
