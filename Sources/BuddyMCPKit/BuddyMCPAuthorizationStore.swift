import CryptoKit
import Foundation
import Security

private let accessStateSchemaVersion = 1
private let maximumClientNameLength = 100
private let maximumIntegrationIdentifierLength = 50

public struct BuddyMCPAuthorizationRecord: Codable, Identifiable, Equatable, Sendable {
    public let clientId: UUID
    public let displayName: String
    public let integrationIdentifier: String?
    public let scope: String
    public let tokenHash: String
    public let helperExecutablePathHash: String?
    public let createdAt: Date
    public var revokedAt: Date?

    public var id: UUID { clientId }
}

public struct BuddyMCPCreatedAuthorization: Equatable, Sendable {
    public let clientId: UUID
    public let displayName: String
    public let integrationIdentifier: String?
    public let scope: String
    public let token: String
    public let createdAt: Date

    public init(
        clientId: UUID,
        displayName: String,
        integrationIdentifier: String? = nil,
        scope: String,
        token: String,
        createdAt: Date
    ) {
        self.clientId = clientId
        self.displayName = displayName
        self.integrationIdentifier = integrationIdentifier
        self.scope = scope
        self.token = token
        self.createdAt = createdAt
    }
}

public struct BuddyMCPAccessDeniedError: Error, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

public final class BuddyMCPAuthorizationStore: @unchecked Sendable {
    private let accessRoot: URL
    private let stateFile: URL
    private let queue = DispatchQueue(label: "BuddyMCP.authorization")

    public init(accessRoot: URL) {
        self.accessRoot = accessRoot
        stateFile = accessRoot.appendingPathComponent("access.json")
    }

    public convenience init(paths: BuddyMCPPaths = .defaults()) {
        self.init(accessRoot: paths.accessRoot)
    }

    public func isEnabled() throws -> Bool {
        try queue.sync { try loadState().enabled }
    }

    public func setEnabled(_ enabled: Bool) throws {
        try queue.sync {
            var state = try loadState()
            state.enabled = enabled
            try saveState(state)
        }
    }

    public func createAuthorization(
        displayName: String,
        integrationIdentifier: String? = nil,
        helperExecutablePath: String? = nil
    ) throws -> BuddyMCPCreatedAuthorization {
        try queue.sync {
            var state = try loadState()
            guard state.enabled else {
                throw BuddyMCPAccessDeniedError(
                    code: "access_disabled",
                    message: "Local Agent access is disabled."
                )
            }
            let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedName.isEmpty, normalizedName.count <= maximumClientNameLength else {
                throw BuddyMCPAuthorizationError.invalidClientName
            }
            if let integrationIdentifier {
                guard !integrationIdentifier.isEmpty,
                      integrationIdentifier.count <= maximumIntegrationIdentifierLength,
                      integrationIdentifier.range(
                          of: #"^[a-z0-9-]+$"#,
                          options: .regularExpression
                      ) != nil
                else {
                    throw BuddyMCPAuthorizationError.invalidIntegrationIdentifier
                }
                guard !state.authorizations.contains(where: {
                    $0.integrationIdentifier == integrationIdentifier && $0.revokedAt == nil
                }) else {
                    throw BuddyMCPAuthorizationError.activeIntegrationExists
                }
            }
            guard !state.authorizations.contains(where: {
                $0.revokedAt == nil
                    && $0.displayName.compare(
                        normalizedName,
                        options: [.caseInsensitive, .diacriticInsensitive]
                    ) == .orderedSame
            }) else {
                throw BuddyMCPAuthorizationError.activeClientNameExists
            }

            let clientId = UUID()
            let token = try Self.randomToken()
            let createdAt = Date()
            state.authorizations.append(
                BuddyMCPAuthorizationRecord(
                    clientId: clientId,
                    displayName: normalizedName,
                    integrationIdentifier: integrationIdentifier,
                    scope: "transcripts.read.all",
                    tokenHash: Self.hashToken(token),
                    helperExecutablePathHash: helperExecutablePath.map(Self.helperExecutablePathHash),
                    createdAt: createdAt,
                    revokedAt: nil
                )
            )
            try saveState(state)
            return BuddyMCPCreatedAuthorization(
                clientId: clientId,
                displayName: normalizedName,
                integrationIdentifier: integrationIdentifier,
                scope: "transcripts.read.all",
                token: token,
                createdAt: createdAt
            )
        }
    }

    public func revokeAuthorization(clientId: UUID) throws {
        try queue.sync {
            var state = try loadState()
            guard let index = state.authorizations.firstIndex(where: {
                $0.clientId == clientId
            }) else {
                throw BuddyMCPAuthorizationError.authorizationNotFound
            }
            guard state.authorizations[index].revokedAt == nil else { return }
            // Persisted millisecond rounding and wall-clock changes must not prevent revocation.
            state.authorizations[index].revokedAt = max(Date(), state.authorizations[index].createdAt)
            try saveState(state)
        }
    }

    public func discardAuthorization(clientId: UUID) throws {
        try queue.sync {
            var state = try loadState()
            guard let index = state.authorizations.firstIndex(where: {
                $0.clientId == clientId
            }) else {
                throw BuddyMCPAuthorizationError.authorizationNotFound
            }
            state.authorizations.remove(at: index)
            try saveState(state)
        }
    }

    public func listAuthorizations() throws -> [BuddyMCPAuthorizationRecord] {
        try queue.sync {
            try loadState().authorizations.sorted { $0.createdAt > $1.createdAt }
        }
    }

    @discardableResult
    public func requireAuthorized(
        clientId: String,
        token: String
    ) throws -> BuddyMCPAuthorizationRecord {
        try queue.sync {
            let state = try loadState()
            guard state.enabled else {
                throw BuddyMCPAccessDeniedError(
                    code: "access_disabled",
                    message: "Local Agent access is disabled."
                )
            }
            guard let parsedClientId = UUID(uuidString: clientId),
                  (32...256).contains(token.count)
            else {
                throw BuddyMCPAccessDeniedError(
                    code: "invalid_credentials",
                    message: "Client credentials are invalid."
                )
            }
            guard let authorization = state.authorizations.first(where: {
                $0.clientId == parsedClientId
            }), authorization.revokedAt == nil else {
                throw BuddyMCPAccessDeniedError(
                    code: "authorization_unavailable",
                    message: "Authorization is unavailable."
                )
            }
            let providedHash = Data(Self.hashToken(token).utf8)
            let storedHash = Data(authorization.tokenHash.utf8)
            guard Self.constantTimeEqual(providedHash, storedHash) else {
                throw BuddyMCPAccessDeniedError(
                    code: "invalid_credentials",
                    message: "Client credentials are invalid."
                )
            }
            return authorization
        }
    }

    private func loadState() throws -> AccessState {
        guard let data = try BuddyMCPFileSecurity.readPrivateData(from: stateFile) else {
            return AccessState(
                schemaVersion: accessStateSchemaVersion,
                enabled: false,
                authorizations: []
            )
        }
        do {
            let state = try Self.makeDecoder().decode(AccessState.self, from: data)
            try Self.validate(state)
            return state
        } catch let error as BuddyMCPStorageError {
            throw error
        } catch {
            throw BuddyMCPStorageError.invalidAccessState
        }
    }

    private func saveState(_ state: AccessState) throws {
        try Self.validate(state)
        let data = try Self.makeEncoder().encode(state)
        try BuddyMCPFileSecurity.writePrivateData(
            data,
            directory: accessRoot,
            file: stateFile
        )
    }

    private static func validate(_ state: AccessState) throws {
        guard state.schemaVersion == accessStateSchemaVersion else {
            throw BuddyMCPStorageError.invalidAccessState
        }
        var clientIds = Set<UUID>()
        for authorization in state.authorizations {
            guard clientIds.insert(authorization.clientId).inserted,
                  !authorization.displayName.isEmpty,
                  authorization.displayName.count <= maximumClientNameLength,
                  authorization.integrationIdentifier.map({
                      !$0.isEmpty
                          && $0.count <= maximumIntegrationIdentifierLength
                          && $0.range(
                              of: #"^[a-z0-9-]+$"#,
                              options: .regularExpression
                          ) != nil
                  }) ?? true,
                  authorization.scope == "transcripts.read.all",
                  authorization.tokenHash.range(
                      of: #"^[a-f0-9]{64}$"#,
                      options: .regularExpression
                  ) != nil,
                  authorization.helperExecutablePathHash.map({
                      $0.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil
                  }) ?? true,
                  authorization.revokedAt.map({ $0 >= authorization.createdAt }) ?? true
            else {
                throw BuddyMCPStorageError.invalidAccessState
            }
        }
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        BuddyMCPISO8601.configureEncoder(encoder)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        BuddyMCPISO8601.configureDecoder(decoder)
        return decoder
    }

    private static func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw BuddyMCPAuthorizationError.randomGenerationFailed
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func hashToken(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func helperExecutablePathHash(_ path: String) -> String {
        let normalizedPath = URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        return SHA256.hash(data: Data(normalizedPath.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func constantTimeEqual(_ left: Data, _ right: Data) -> Bool {
        guard left.count == right.count else { return false }
        return zip(left, right).reduce(UInt8(0)) { result, pair in
            result | (pair.0 ^ pair.1)
        } == 0
    }
}

public enum BuddyMCPAuthorizationError: Error {
    case invalidClientName
    case invalidIntegrationIdentifier
    case activeIntegrationExists
    case activeClientNameExists
    case authorizationNotFound
    case encodingFailed
    case randomGenerationFailed
}

private struct AccessState: Codable {
    let schemaVersion: Int
    var enabled: Bool
    var authorizations: [BuddyMCPAuthorizationRecord]
}
