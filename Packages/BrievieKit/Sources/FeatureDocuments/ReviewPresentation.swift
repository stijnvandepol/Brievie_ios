import Foundation

/// The list a sheet shows to choose persons or labels from.
public enum OrganisePicker: Identifiable, Sendable {
    case persons, labels
    public var id: Self { self }
}

/// The quote whose place in the letter is being shown.
public struct SourceQuote: Identifiable, Equatable, Sendable {
    public let text: String
    public var id: String { text }
}
