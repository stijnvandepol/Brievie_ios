import Foundation

extension DocumentStrings {
    // Search in "Alle post"

    /// The placeholder of the search field in "Alle post".
    static let searchPrompt = String(
        localized: "search.prompt",
        defaultValue: "Zoek in je post",
        bundle: .module
    )
    /// Above the search results before anything is typed.
    static let searchEmptyTitle = String(
        localized: "search.empty.title",
        defaultValue: "Zoek een brief",
        bundle: .module
    )
    /// What can be searched for, before anything is typed.
    static let searchEmptyHint = String(
        localized: "search.empty.hint",
        defaultValue: """
        Zoek op afzender, onderwerp, een woord uit de brief, een label of een naam. \
        Het begin van een woord is genoeg.
        """,
        bundle: .module
    )
    /// The search term has one character.
    static let searchTooShort = String(
        localized: "search.tooShort",
        defaultValue: "Typ minstens twee tekens.",
        bundle: .module
    )
    /// While the server searches.
    static let searchSearching = String(
        localized: "search.searching",
        defaultValue: "Bezig met zoeken…",
        bundle: .module
    )
    /// No letter matched the search term.
    static let searchNoneTitle = String(
        localized: "search.none.title",
        defaultValue: "Niets gevonden",
        bundle: .module
    )
    /// The next step when nothing was found.
    static let searchNoneHint = String(
        localized: "search.none.hint",
        defaultValue: "Gebruik minder woorden, of probeer een andere spelling of het begin van een woord.",
        bundle: .module
    )
    /// Above results that match only approximately.
    static let searchFuzzy = String(
        localized: "search.fuzzy",
        defaultValue: "Geen exacte treffer. Dit lijkt erop.",
        bundle: .module
    )
    /// The server removed a citizen service number (BSN) from the search term.
    static let searchBSNRemoved = String(
        localized: "search.bsnRemoved",
        defaultValue: """
        Zoeken op een BSN kan niet: Brievie bewaart geen BSN's. \
        We hebben het nummer uit je zoekopdracht gehaald.
        """,
        bundle: .module
    )
    /// The server refused the search: too many searches in a minute.
    static let searchTooMany = String(
        localized: "search.error.tooMany",
        defaultValue: "Je hebt veel gezocht in korte tijd. Wacht een minuut en probeer het opnieuw.",
        bundle: .module
    )
    /// The server is older than search.
    static let searchNotSupported = String(
        localized: "search.error.notSupported",
        defaultValue: "Je Brievie-server kan nog niet zoeken. Vraag de beheerder om de server bij te werken.",
        bundle: .module
    )
    /// Button under the search results that loads the next page.
    static let searchMore = String(
        localized: "search.more",
        defaultValue: "Meer laden",
        bundle: .module
    )
    /// Accessibility name of the list of search results.
    static let searchResults = String(
        localized: "search.results",
        defaultValue: "Zoekresultaten",
        bundle: .module
    )

    /// The strings of this part by catalog key, for the parity test (merged into `all`).
    static let search: [String: String] = [
        "search.prompt": searchPrompt,
        "search.empty.title": searchEmptyTitle,
        "search.empty.hint": searchEmptyHint,
        "search.tooShort": searchTooShort,
        "search.searching": searchSearching,
        "search.none.title": searchNoneTitle,
        "search.none.hint": searchNoneHint,
        "search.fuzzy": searchFuzzy,
        "search.bsnRemoved": searchBSNRemoved,
        "search.error.tooMany": searchTooMany,
        "search.error.notSupported": searchNotSupported,
        "search.more": searchMore,
        "search.results": searchResults
    ]
}
