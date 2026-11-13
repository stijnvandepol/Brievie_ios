import Foundation

enum SessionConfiguration {
    /// How long to wait for a server before calling it unreachable and trying the next URL.
    static let requestTimeout: TimeInterval = 15

    /// `configuration` with everything that could carry state between requests switched off: no cookies,
    /// no stored credentials, no response cache, no extra headers. The device token is sent explicitly
    /// per request, never through the session.
    static func hardened(_ configuration: URLSessionConfiguration) -> URLSessionConfiguration {
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpAdditionalHeaders = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = requestTimeout
        return configuration
    }
}
