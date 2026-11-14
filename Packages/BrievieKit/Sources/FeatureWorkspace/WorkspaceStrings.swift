import Foundation

/// Visible text of this target. The String Catalog (`Resources/Localizable.xcstrings`) is the source of
/// truth in the app; `defaultValue` repeats the Dutch text so that `swift test`, which does not compile
/// catalogs, sees the same words. `WorkspacesModelTests` keeps the two equal.
enum WorkspaceStrings {
    static let kindHome = String(localized: "workspaces.kind.home", defaultValue: "Thuis", bundle: .module)
    static let kindBusiness = String(localized: "workspaces.kind.business", defaultValue: "Zakelijk", bundle: .module)
    static let kindUnknown = String(localized: "workspaces.kind.unknown", defaultValue: "Werkruimte", bundle: .module)
    static let roleAdmin = String(localized: "workspaces.role.admin", defaultValue: "Beheerder", bundle: .module)
    static let roleMember = String(localized: "workspaces.role.member", defaultValue: "Lid", bundle: .module)
    static let roleViewer = String(localized: "workspaces.role.viewer", defaultValue: "Kijker", bundle: .module)
    static let unreachable = String(
        localized: "workspaces.error.unreachable",
        defaultValue: "We kunnen je Brievie-server niet bereiken. Zit je op hetzelfde netwerk?",
        bundle: .module
    )
    static let notVerified = String(
        localized: "workspaces.error.notVerified",
        defaultValue: """
            We konden niet controleren of dit jouw Brievie-server is. \
            Koppel de app opnieuw als dit blijft gebeuren.
            """,
        bundle: .module
    )
    static let generic = String(
        localized: "error.generic",
        defaultValue: "Er ging iets mis. Probeer het opnieuw.",
        bundle: .module
    )

    /// Every string above by catalog key, for the parity test.
    static let all: [String: String] = [
        "workspaces.kind.home": kindHome,
        "workspaces.kind.business": kindBusiness,
        "workspaces.kind.unknown": kindUnknown,
        "workspaces.role.admin": roleAdmin,
        "workspaces.role.member": roleMember,
        "workspaces.role.viewer": roleViewer,
        "workspaces.error.unreachable": unreachable,
        "workspaces.error.notVerified": notVerified,
        "error.generic": generic
    ]
}
