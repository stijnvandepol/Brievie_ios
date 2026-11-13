import BrievieCore
import FeaturePairing
import FeatureWorkspace
import SwiftUI

/// Switches on `AppModel.state`; hides everything but the app name while the app is not in the foreground.
struct RootView: View {
    let appModel: AppModel
    let environment: AppEnvironment

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .overlay {
                if hidesContent {
                    PrivacyCover()
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                switch phase {
                case .background:
                    appModel.didEnterBackground()
                case .active:
                    Task { await appModel.didBecomeActive() }
                default:
                    break
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch appModel.state {
        case .unpaired(let notice):
            PairingScreen(appModel: appModel, environment: environment, notice: notice)
        case .locked:
            LockView(unlock: { Task { await appModel.unlock() } })
        case .ready(let connection):
            WorkspacesScreen(appModel: appModel, environment: environment, connection: connection)
        }
    }

    /// The app switcher takes its snapshot when the scene leaves the foreground: nothing from a paired app
    /// may be on screen by then. Pairing shows no personal data.
    private var hidesContent: Bool {
        if case .unpaired = appModel.state { return false }
        return scenePhase != .active
    }
}

private struct PairingScreen: View {
    @State private var model: PairingModel
    private let notice: String?

    init(appModel: AppModel, environment: AppEnvironment, notice: String?) {
        _model = State(initialValue: PairingModel(
            service: PairingService(server: environment.server, store: environment.store),
            deviceName: { UIDevice.current.name },
            onPaired: { appModel.didPair($0) }
        ))
        self.notice = notice
    }

    var body: some View {
        PairingView(model: model, notice: notice)
    }
}

private struct WorkspacesScreen: View {
    @State private var model: WorkspacesModel
    private let showsNoPasscodeWarning: Bool

    init(appModel: AppModel, environment: AppEnvironment, connection: ServerConnection) {
        _model = State(initialValue: WorkspacesModel(
            connection: connection,
            store: environment.store,
            server: environment.server,
            appModel: appModel
        ))
        showsNoPasscodeWarning = appModel.showsNoPasscodeWarning
    }

    var body: some View {
        WorkspacesView(model: model, showsNoPasscodeWarning: showsNoPasscodeWarning)
    }
}
