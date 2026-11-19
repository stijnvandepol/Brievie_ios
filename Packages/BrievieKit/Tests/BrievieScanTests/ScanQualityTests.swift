import BrievieScan
import Foundation
import Testing

/// The scan-quality set: every made-up letter, spoiled like a phone scan and turned each quarter, through the
/// real pipeline (`PageProcessor` with Apple Vision, encoder included). Per page: the upright turn is found,
/// the uploaded pixels are upright, and the facts that matter can be read from the text in order.
///
/// Needs Apple Vision: runs in `make test` and CI on macOS (and on an iOS simulator). Set
/// `BRIEVIE_SKIP_VISION=1` to leave it out; `BRIEVIE_SCAN_REPORT=1` prints what was found per page.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["BRIEVIE_SKIP_VISION"] != "1"))
struct ScanQualityTests {
    static let reports = ProcessInfo.processInfo.environment["BRIEVIE_SCAN_REPORT"] == "1"

    static let cases: [(LetterFixture, QuarterTurn)] = LetterFixture.all.flatMap { fixture in
        QuarterTurn.allCases.map { (fixture, $0) }
    }

    /// Facts the recogniser loses, measured on 2026-11-19, by "<key>/<kind>" or, when it depends on the turn,
    /// "<key>/<kind>/<turn>". Kept visible instead of tuned away. Vision differs per platform (the simulator
    /// runs other models than macOS), so each has its own list; marked intermittent because other hardware or
    /// OS versions may read differently. `BRIEVIE_SCAN_REPORT=1` shows what is lost now.
    #if os(macOS)
    // macOS 26.6, Apple silicon (what `make test` and CI run).
    static let knownLosses: [String: String] = [
        // Skewed 3° and blurred: Vision merges the skewed paragraph lines into nonsense
        // ("WVl 7220 per madi beant láura ember 2026"), so "vóór 3 december 2026" is gone.
        "energie/deadline": "3° skew plus blur: paragraph lines merged",
        "energie/amount/clockwise": "3° skew plus blur, read after a quarter turn: amount line merged",
        "energie/amount/counterClockwise": "3° skew plus blur, read after a quarter turn: amount line merged",
        // Times with noise: "CZ. Zorgverzekcringen"; language correction does not fix a brand name.
        "zorgpolis/sender": "Times with noise: sender read as \"CZ. Zorgverzekcringen\""
    ]
    #else
    // iOS 26.4 simulator.
    static let knownLosses: [String: String] = [
        // Courier, blurred, shadowed: the first letter of the top lines is lost ("'landerijn", "'ostbus").
        "incasso/sender": "Courier with blur and shadow: \"'landerijn Incasso\"",
        "incasso/addressee/clockwise": "Courier with blur and shadow: \"van de Po1\"",
        "incasso/addressee/upsideDown": "Courier with blur and shadow: \"van de Po1\"",
        "zorgpolis/sender": "Times with noise: sender misread"
    ]
    #endif

    static func knownLoss(_ fixture: LetterFixture, _ fact: LetterFixture.Fact, _ turn: QuarterTurn) -> String? {
        knownLosses["\(fixture.key)/\(fact.kind.rawValue)"]
            ?? knownLosses["\(fixture.key)/\(fact.kind.rawValue)/\(turn)"]
    }

    @Test(arguments: cases)
    func theScannedLetterIsUprightAndKeepsItsFacts(fixture: LetterFixture, turn: QuarterTurn) async throws {
        for page in 1...fixture.pageCount {
            let jpeg = try LetterScanRenderer.scan(try fixture.text(ofPage: page), style: fixture.style, turn: turn)

            let started = ContinuousClock.now
            let result = try await PageProcessor().process(.encodedData(jpeg))
            let elapsed = ContinuousClock.now - started

            #expect(turn.adding(result.turn) == .upright, "page \(page) came in turned \(turn)")
            let size = try #require(TestImages.size(ofJPEG: result.page.jpeg))
            #expect(size.height > size.width, "the uploaded page \(page) is portrait")
            let text = Self.normalized(result.page.text)
            var report: [String] = []
            for fact in fixture.facts where fact.page == page {
                let found = text.contains(Self.normalized(fact.text))
                report.append("\(fact.kind.rawValue): \(found ? "ok" : "LOST")")
                if !found, Self.reports { print("SCANT \(fixture.key) \(turn) \(fact.kind)\n\(result.page.text)") }
                if let reason = Self.knownLoss(fixture, fact, turn) {
                    withKnownIssue(Comment(rawValue: reason), isIntermittent: true) { #expect(found) }
                } else {
                    #expect(found, "\(fact.kind.rawValue) \"\(fact.text)\" on page \(page)")
                }
            }
            if page == 1, let sender = fixture.facts.first(where: { $0.kind == .sender }),
               let date = fixture.facts.first(where: { $0.kind == .date }),
               let senderAt = text.range(of: Self.normalized(sender.text)),
               let dateAt = text.range(of: Self.normalized(date.text)) {
                #expect(senderAt.lowerBound < dateAt.lowerBound, "the sender is read before the date")
            }
            if Self.reports {
                let found = report.joined(separator: ", ")
                print("SCANQ \(fixture.key) p\(page) in:\(turn) turn:\(result.turn) \(elapsed) \(found)")
            }
        }
    }

    /// Time per page, one page at a time (the parameterised test runs pages in parallel). Only with the report.
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

    /// Case, accents and line breaks do not count: "Vóór 3 December" matches "voor 3 december".
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "nl_NL"))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
