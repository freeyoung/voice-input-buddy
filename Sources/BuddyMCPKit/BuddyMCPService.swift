import Foundation

public final class BuddyMCPService: @unchecked Sendable {
    public let clientId: String
    private let token: String
    private let authorizationStore: BuddyMCPAuthorizationStore
    private let historyStore: BuddyMCPHistoryStore
    private let auditLog: BuddyMCPAuditLog

    public init(
        paths: BuddyMCPPaths = .defaults(),
        clientId: String,
        token: String
    ) {
        self.clientId = clientId
        self.token = token
        authorizationStore = BuddyMCPAuthorizationStore(paths: paths)
        historyStore = BuddyMCPHistoryStore(paths: paths)
        auditLog = BuddyMCPAuditLog(paths: paths)
    }

    public func validateServerStart() throws {
        do {
            try authorizationStore.requireAuthorized(clientId: clientId, token: token)
            try auditLog.append(
                BuddyMCPAuditEvent(
                    clientId: clientId,
                    tool: "server_start",
                    result: "allowed"
                )
            )
        } catch {
            try? auditLog.append(
                BuddyMCPAuditEvent(
                    clientId: clientId,
                    tool: "server_start",
                    result: "denied",
                    reasonCode: Self.errorCode(error)
                )
            )
            throw error
        }
    }

    public func listApplications() throws -> BuddyMCPApplicationPage {
        let occurredAt = Date()
        do {
            try authorizationStore.requireAuthorized(clientId: clientId, token: token)
            let result = try historyStore.listApplications()
            try auditLog.append(
                BuddyMCPAuditEvent(
                    clientId: clientId,
                    tool: "list_transcript_apps",
                    occurredAt: occurredAt,
                    result: "allowed",
                    returnedRecordCount: result.applications.reduce(0) { $0 + $1.recordCount }
                )
            )
            return result
        } catch {
            try? auditLog.append(
                BuddyMCPAuditEvent(
                    clientId: clientId,
                    tool: "list_transcript_apps",
                    occurredAt: occurredAt,
                    result: error is BuddyMCPAccessDeniedError ? "denied" : "error",
                    reasonCode: Self.errorCode(error)
                )
            )
            throw error
        }
    }

    public func query(_ query: BuddyMCPTranscriptQuery) throws -> BuddyMCPTranscriptPage {
        let occurredAt = Date()
        do {
            try authorizationStore.requireAuthorized(clientId: clientId, token: token)
            let result = try historyStore.query(query)
            try auditLog.append(
                BuddyMCPAuditEvent(
                    clientId: clientId,
                    tool: "query_transcripts",
                    occurredAt: occurredAt,
                    result: "allowed",
                    returnedRecordCount: result.records.count,
                    startedAtOrAfter: query.startedAtOrAfter,
                    endedAtBefore: query.endedAtBefore,
                    bundleIdentifierCount: query.bundleIdentifiers?.count ?? 0
                )
            )
            return result
        } catch {
            try? auditLog.append(
                BuddyMCPAuditEvent(
                    clientId: clientId,
                    tool: "query_transcripts",
                    occurredAt: occurredAt,
                    result: error is BuddyMCPAccessDeniedError ? "denied" : "error",
                    startedAtOrAfter: query.startedAtOrAfter,
                    endedAtBefore: query.endedAtBefore,
                    bundleIdentifierCount: query.bundleIdentifiers?.count ?? 0,
                    reasonCode: Self.errorCode(error)
                )
            )
            throw error
        }
    }

    public static func errorCode(_ error: Error) -> String {
        if let accessError = error as? BuddyMCPAccessDeniedError {
            return accessError.code
        }
        return "request_failed"
    }
}
