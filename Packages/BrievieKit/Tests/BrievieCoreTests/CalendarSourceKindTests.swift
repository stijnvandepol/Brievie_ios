@testable import BrievieCore
import Testing

/// Which of the phone's accounts is iCloud. EventKit has no "iCloud" type: it is the CalDAV account the phone
/// calls "iCloud". When more than one CalDAV account has that title, none is trusted as iCloud.
@Suite struct CalendarSourceKindTests {
    @Test func theOneCalDAVAccountCallediCloudIsICloud() {
        let sources = CalendarSource.classify([
            .init(id: "a", title: "iCloud", type: .calDAV),
            .init(id: "b", title: "Gmail", type: .calDAV),
            .init(id: "c", title: "Werk", type: .exchange),
            .init(id: "d", title: "Op mijn iPhone", type: .local),
            .init(id: "e", title: "Verjaardagen", type: .readOnly)
        ])

        #expect(sources == [
            CalendarSource(id: "a", title: "iCloud", kind: .iCloud),
            CalendarSource(id: "b", title: "Gmail", kind: .other),
            CalendarSource(id: "c", title: "Werk", kind: .other),
            CalendarSource(id: "d", title: "Op mijn iPhone", kind: .local)
        ])
    }

    @Test func twoCalDAVAccountsCallediCloudAreBothAskedAbout() {
        let sources = CalendarSource.classify([
            .init(id: "a", title: "iCloud", type: .calDAV),
            .init(id: "b", title: "iCloud", type: .calDAV)
        ])

        #expect(sources.map(\.kind) == [.other, .other])
        #expect(CalendarSourceChoice(sources: sources, defaultSourceID: "a") == .needsConsent(sources[0]))
    }
}
