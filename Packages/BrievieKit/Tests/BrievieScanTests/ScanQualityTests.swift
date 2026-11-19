import BrievieScan
import Foundation
import Testing

/// The scan-quality set: every made-up letter, spoiled like a phone scan and turned each quarter, through the
/// real pipeline (`PageProcessor` with Apple Vision, encoder included).
///
/// Vision reads differently per machine (the CI runner lost other facts than a Mac or the simulator), so the
/// test has two levels. Hard, on every page: it is put upright, the uploaded pixels are portrait, the text is
/// not empty and its lines are in the letter's order. Measured, over the whole set: the share of facts found
/// (`FactMatcher`) is at least `minimumShare`, and no letter loses all its facts. What was lost is always
/// printed; `BRIEVIE_SCAN_REPORT=1` prints every page. `BRIEVIE_SKIP_VISION=1` leaves the set out.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["BRIEVIE_SKIP_VISION"] != "1"))
struct ScanQualityTests {
    static let reports = ProcessInfo.processInfo.environment["BRIEVIE_SCAN_REPORT"] == "1"

    /// Facts found over the set, measured 2026-11-19 with 224 facts per run: macOS 26.6 on Apple silicon 95.5%,
    /// iOS 26.4 simulator 95.5%, GitHub's macOS runner 92.9% (before the tolerant matching). A few points under
    /// the worst.
    static let minimumShare = 0.88
    /// Of the recognised lines that match the letter, the share in the letter's order. Measured on macOS: 0.83
    /// to 1 for the upright pages; 0.19 to 0.36 for the same pages read turned without putting them upright.
    static let minimumOrder = 0.6

    private struct Loss {
        let fixture: String
        let turn: QuarterTurn
        let fact: LetterFixture.Fact
        let read: String
    }

    @Test func everyScannedLetterIsUprightAndKeepsEnoughOfItsFacts() async throws {
        var found = 0
        var total = 0
        var losses: [Loss] = []
        for fixture in LetterFixture.all {
            var foundInFixture = 0
            for turn in QuarterTurn.allCases {
                for page in 1...fixture.pageCount {
                    let source = try fixture.text(ofPage: page)
                    let text = try await scanAndCheck(source, fixture: fixture, page: page, turn: turn)
                    for fact in fixture.facts where fact.page == page {
                        total += 1
                        if FactMatcher.found(fact, in: text) {
                            found += 1
                            foundInFixture += 1
                        } else {
                            let read = FactMatcher.closestLine(to: fact, in: text)
                            losses.append(Loss(fixture: fixture.key, turn: turn, fact: fact, read: read))
                        }
                    }
                }
            }
            #expect(foundInFixture > 0, "\(fixture.key) lost every fact in every turn")
        }
        let share = Double(found) / Double(max(total, 1))
        print(Self.report(found: found, total: total, losses: losses))
        #expect(share >= Self.minimumShare, "facts found: \(found) of \(total)")
    }

    /// The hard part, for one page: upright, portrait, text, order. Returns the text.
    private func scanAndCheck(
        _ source: String, fixture: LetterFixture, page: Int, turn: QuarterTurn
    ) async throws -> String {
        let jpeg = try LetterScanRenderer.scan(source, style: fixture.style, turn: turn)
        let started = ContinuousClock.now
        let result = try await PageProcessor().process(.encodedData(jpeg))
        let elapsed = ContinuousClock.now - started
        let place = "\(fixture.key) page \(page), came in turned \(turn)"

        #expect(turn.adding(result.turn) == .upright, "\(place): not put upright")
        let size = try #require(TestImages.size(ofJPEG: result.page.jpeg))
        #expect(size.height > size.width, "\(place): the upload is not portrait")
        #expect(!result.page.text.isEmpty, "\(place): no text")
        let order = Self.orderShare(of: result.page.text, against: source)
        #expect(order >= Self.minimumOrder, "\(place): lines out of order (\(order))")
        if Self.reports {
            print("SCANQ \(fixture.key) p\(page) in:\(turn) turn:\(result.turn) order:\(order) \(elapsed)")
        }
        return result.page.text
    }

    /// Where each recognised line of ten characters or more sits in the letter (best approximate match, a
    /// fifth of its characters may differ; of equal matches the first after the previous line), and the share
    /// of those lines in the longest run that keeps the letter's order. Lines Vision merged or garbled match
    /// nothing and do not count; the letter's own line breaks do not matter.
    static func orderShare(of text: String, against source: String) -> Double {
        let letter = Array(FactMatcher.normalized(source))
        var previous = -1
        var positions: [Int] = []
        for line in text.split(separator: "\n") {
            let read = Array(FactMatcher.normalized(String(line)))
            guard read.count >= 10 else { continue }
            let costs = FactMatcher.costs(of: read, endingIn: letter)
            guard let best = costs.min(), best <= read.count / 5 else { continue }
            let ends = costs.indices.filter { costs[$0] == best }
            let position = ends.first { $0 > previous } ?? ends[0]
            positions.append(position)
            previous = position
        }
        guard !positions.isEmpty else { return 0 }
        var tails: [Int] = []
        for position in positions {
            let place = tails.firstIndex { $0 >= position } ?? tails.count
            if place == tails.count { tails.append(position) } else { tails[place] = position }
        }
        return Double(tails.count) / Double(positions.count)
    }

    private static func report(found: Int, total: Int, losses: [Loss]) -> String {
        let share = String(format: "%.1f", Double(found) / Double(max(total, 1)) * 100)
        let floor = Int(minimumShare * 100)
        var lines = ["SCAN QUALITY: \(found) of \(total) facts found (\(share)%), floor \(floor)%"]
        for loss in losses {
            let fact = "\(loss.fact.kind.rawValue) \"\(loss.fact.text)\""
            lines.append("  lost \(loss.fixture) \(loss.turn) \(fact): read \"\(loss.read)\"")
        }
        return lines.joined(separator: "\n")
    }

    @Test func aBlankBackSideStaysAsItIs() async throws {
        let blank = try PageImageEncoder.jpeg(from: TestImages.page(width: 1240, height: 1754))

        let result = try await PageProcessor().process(.encodedData(blank))

        #expect(result.turn == .upright)
        #expect(result.page.text.isEmpty)
    }

    @Test func aPageWithOneWordIsNotTurnedOnAGuess() async throws {
        // "Bijlage" is 7 letters: below the 12 the automatic turn needs, so the user decides with "Draai".
        let page = try LetterScanRenderer.scan("Bijlage", style: ScanStyle(), turn: .upsideDown)

        let result = try await PageProcessor().process(.encodedData(page))

        #expect(result.turn == .upright)
        #expect(!result.turnedAutomatically)
    }

    /// Time per page, one page at a time. Only with the report.
    @Test(.enabled(if: reports))
    func timePerPage() async throws {
        let text = try LetterFixture.all[0].text(ofPage: 1)
        for turn in [QuarterTurn.upright, .clockwise, .upright, .upsideDown] {
            let jpeg = try LetterScanRenderer.scan(text, style: ScanStyle(), turn: turn)
            let started = ContinuousClock.now
            _ = try await PageProcessor().process(.encodedData(jpeg))
            print("SCANTIME in:\(turn) \(ContinuousClock.now - started)")
        }
    }
}
