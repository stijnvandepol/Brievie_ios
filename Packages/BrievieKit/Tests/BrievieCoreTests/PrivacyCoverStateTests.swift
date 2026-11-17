@testable import BrievieCore
import Testing

/// When the window-level privacy cover goes up and down. The window itself (UIKit) is in the app target; only a
/// device shows what the app switcher's snapshot really holds.
@Suite struct PrivacyCoverStateTests {
    @Test func coversWhenTheSceneStopsBeingActiveAndUncoversWhenItIsBack() {
        var state = PrivacyCoverState()

        #expect(state.sceneWillDeactivate(covers: true) == .show)
        #expect(state.isShown)
        #expect(state.sceneDidEnterBackground(covers: true) == nil)
        #expect(state.sceneDidActivate() == .hide)
        #expect(!state.isShown)
    }

    @Test func pairingShowsNoPersonalDataSoItIsNotCovered() {
        var state = PrivacyCoverState()

        #expect(state.sceneWillDeactivate(covers: false) == nil)
        #expect(state.sceneDidEnterBackground(covers: false) == nil)
        #expect(state.sceneDidActivate() == nil)
    }

    @Test func aPairingMadeWhileInactiveIsCoveredBeforeTheSnapshot() {
        var state = PrivacyCoverState()
        _ = state.sceneWillDeactivate(covers: false)

        // The pairing completed between "inactive" and "background": the snapshot comes after the latter.
        #expect(state.sceneDidEnterBackground(covers: true) == .show)
        #expect(state.isShown)
    }

    @Test func aSecondDeactivationDoesNotShowTwice() {
        var state = PrivacyCoverState()
        _ = state.sceneWillDeactivate(covers: true)

        #expect(state.sceneWillDeactivate(covers: true) == nil)
        #expect(state.sceneDidActivate() == .hide)
        #expect(state.sceneDidActivate() == nil)
    }

    @Test func theCoverStaysUpWhenTheAppIsUnpairedWhileInTheBackground() {
        var state = PrivacyCoverState()
        _ = state.sceneWillDeactivate(covers: true)

        // Whatever the state is by now, what was on screen is covered until the scene is active again.
        #expect(state.sceneWillDeactivate(covers: false) == nil)
        #expect(state.isShown)
    }
}
