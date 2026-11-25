import Foundation

// Letter status, waiting and snoozing (host PR #50), and the account messages that come with the server's
// security rules.
extension DocumentStrings {
    static let secondFactorRequired = String(
        localized: "error.secondFactorRequired",
        defaultValue: "Stel eerst tweestapsverificatie in op de webinterface.",
        bundle: .module
    )

    static let status: [String: String] = [
        "error.secondFactorRequired": secondFactorRequired
    ]
}
