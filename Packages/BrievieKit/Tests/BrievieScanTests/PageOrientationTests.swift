import BrievieScan
import CoreGraphics
import Testing

/// The decision which way is up, from the direction the recognised lines read in. Pure logic: runs everywhere.
@Suite struct PageOrientationTests {
    /// A line of `count` characters whose baseline points along (`x`, `y`), y up as in Vision.
    private func line(_ count: Int = 30, x along: Double, y rise: Double, confidence: Double = 1) -> RecognizedLine {
        RecognizedLine(
            text: String(repeating: "a", count: count), confidence: confidence, baselineX: along, baselineY: rise
        )
    }

    @Test func linesReadingLeftToRightNeedNoTurn() {
        #expect(PageOrientation.correction(for: [line(x: 400, y: 2), line(x: 300, y: -3)]) == .upright)
    }

    @Test func linesReadingTopToBottomAreTurnedBackCounterClockwise() {
        // The page lies turned a quarter clockwise: its lines run down the image.
        #expect(PageOrientation.correction(for: [line(x: 1, y: -400), line(x: -2, y: -300)]) == .counterClockwise)
    }

    @Test func linesReadingBottomToTopAreTurnedBackClockwise() {
        #expect(PageOrientation.correction(for: [line(x: 0, y: 400), line(x: 3, y: 350)]) == .clockwise)
    }

    @Test func linesReadingRightToLeftAreTurnedHalfway() {
        #expect(PageOrientation.correction(for: [line(x: -400, y: 0), line(x: -380, y: 5)]) == .upsideDown)
    }

    @Test func aFewDegreesOfSkewDoNotChangeTheAnswer() {
        // 5 degrees: tan(5°) ≈ 0.087
        #expect(PageOrientation.correction(for: [line(x: 400, y: 35), line(x: 400, y: -35)]) == .upright)
        #expect(PageOrientation.correction(for: [line(x: 35, y: -400)]) == .counterClockwise)
    }

    @Test func aPageWithAlmostNoTextStaysAsItIs() {
        #expect(PageOrientation.correction(for: []) == nil)
        #expect(PageOrientation.correction(for: [line(5, x: 0, y: -100)]) == nil)
    }

    @Test func unsureTextDoesNotCount() {
        // Vision's guesses on a photo of a wall: plenty of characters, none of them trusted.
        #expect(PageOrientation.correction(for: [line(80, x: 0, y: 300, confidence: 0.2)]) == nil)
    }

    @Test func mixedDirectionsWithoutAClearWinnerStayAsTheyAre() {
        // A form with a sideways column next to normal text: no clear majority, so no automatic turn.
        let lines = [line(60, x: 400, y: 0), line(40, x: 0, y: -400)]
        #expect(PageOrientation.correction(for: lines) == nil)
    }

    @Test func aSidewaysMarginNoteDoesNotOverruleTheLetter() {
        let lines = [line(300, x: 400, y: 0), line(20, x: 0, y: 300)]
        #expect(PageOrientation.correction(for: lines) == .upright)
    }

    @Test func turnsAddUpClockwise() {
        #expect(QuarterTurn.upright.adding(.clockwise) == .clockwise)
        #expect(QuarterTurn.clockwise.adding(.clockwise) == .upsideDown)
        #expect(QuarterTurn.counterClockwise.adding(.clockwise) == .upright)
        #expect(QuarterTurn.upsideDown.adding(.upsideDown) == .upright)
    }

    @Test(arguments: [
        (QuarterTurn.upright, TestImages.Corner.topLeft), (.clockwise, .topRight),
        (.upsideDown, .bottomRight), (.counterClockwise, .bottomLeft)
    ])
    func rotationTurnsThePixelsTheWayItSays(turn: QuarterTurn, corner: TestImages.Corner) throws {
        let page = TestImages.marked(width: 300, height: 400, corner: .topLeft)

        let turned = try PageImageEncoder.rotated(page, by: turn)

        #expect(TestImages.darkCorner(of: turned) == corner)
        #expect(turned.width == (turn.swapsSides ? 400 : 300))
    }
}
