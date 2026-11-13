import Foundation

/// Keeps the paired server connection and its device token together in a `SecretStore`.
///
/// The app is either fully paired or not paired at all: when only one of the two items is
/// present, or an item cannot be read back, `load()` clears what is left and reports "not paired".
public struct ConnectionStore: Sendable {
    private let secrets: any SecretStore

    public init(secrets: any SecretStore) {
        self.secrets = secrets
    }

    public func load() throws -> (connection: ServerConnection, token: String)? {
        let connectionData = try secrets.read(.serverConnection)
        let tokenData = try secrets.read(.deviceToken)
        if connectionData == nil, tokenData == nil {
            return nil
        }
        guard
            let connectionData,
            let tokenData,
            let connection = try? JSONDecoder().decode(ServerConnection.self, from: connectionData),
            let token = String(data: tokenData, encoding: .utf8)
        else {
            try clear()
            return nil
        }
        return (connection, token)
    }

    public func save(_ connection: ServerConnection, token: String) throws {
        try secrets.write(JSONEncoder().encode(connection), for: .serverConnection)
        try secrets.write(Data(token.utf8), for: .deviceToken)
    }

    public func clear() throws {
        try secrets.delete(.deviceToken)
        try secrets.delete(.serverConnection)
    }
}
