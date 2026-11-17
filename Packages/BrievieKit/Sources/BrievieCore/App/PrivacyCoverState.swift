import Foundation

/// When the privacy cover is up. The app switcher takes its snapshot after the scene entered the background,
/// whatever is presented (sheets, the scanner, the photo picker): the cover is a window above all of them, up from
/// the moment the scene stops being active until it is active again. Pure, so a test covers it; the app target
/// owns the window (`PrivacyCoverWindow`).
public struct PrivacyCoverState: Equatable, Sendable {
    public enum Change: Equatable, Sendable {
        case show
        case hide
    }

    public private(set) var isShown = false

    public init() {}

    /// The scene is about to stop being active (app switcher, Control Center, a call, Face ID's own prompt).
    /// - Parameter covers: the app is paired, so its screens may show a letter (pairing shows no personal data).
    public mutating func sceneWillDeactivate(covers: Bool) -> Change? {
        show(if: covers)
    }

    /// The scene entered the background; the snapshot follows. Covers also when the app became paired since it
    /// stopped being active.
    public mutating func sceneDidEnterBackground(covers: Bool) -> Change? {
        show(if: covers)
    }

    /// The scene is active again: the user is looking at the app.
    public mutating func sceneDidActivate() -> Change? {
        guard isShown else { return nil }
        isShown = false
        return .hide
    }

    private mutating func show(if covers: Bool) -> Change? {
        guard covers, !isShown else { return nil }
        isShown = true
        return .show
    }
}
