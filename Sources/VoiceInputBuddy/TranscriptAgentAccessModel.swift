import AppKit
import Combine
import Foundation
import BuddyMCPKit

enum TranscriptAgentAccessError: Equatable, Sendable {
    case loadFailed
    case updateFailed
    case invalidClientName
    case authorizationFailed
    case revokeFailed
    case helperMissing
    case clientUnavailable
    case clientCommandUnavailable
    case configurationConflict
    case invalidClientConfiguration
    case unsafeClientConfiguration
    case clientConfigurationWriteFailed
    case clientInstallationRejected
    case integrationFailed
    case configurationRemovalFailed
    case duplicateClient
}

@MainActor
final class TranscriptAgentAccessModel: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var authorizations: [BuddyMCPAuthorizationRecord] = []
    @Published var clientName = ""
    @Published private(set) var generatedConfiguration: BuddyMCPIntegrationConfig?
    @Published private(set) var error: TranscriptAgentAccessError?
    @Published private(set) var copiedConfiguration: ConfigurationKind?
    @Published private(set) var integrationInProgress: MCPClientKind?
    @Published private(set) var failedClient: MCPClientKind?
    @Published private(set) var authorizationsNeedingReconnect: Set<UUID> = []

    enum ConfigurationKind {
        case standardJSON
        case codexTOML
    }

    private let authorizationStore: BuddyMCPAuthorizationStore
    private let helperExecutableURL: () -> URL
    private let integrationService: MCPClientIntegrationService

    init(
        authorizationStore: BuddyMCPAuthorizationStore = BuddyMCPAuthorizationStore(),
        integrationService: MCPClientIntegrationService = MCPClientIntegrationService(),
        helperExecutableURL: @escaping () -> URL = {
            Bundle.main.bundleURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent("BuddyMCP", isDirectory: false)
        }
    ) {
        self.authorizationStore = authorizationStore
        self.integrationService = integrationService
        self.helperExecutableURL = helperExecutableURL
    }

    func refresh() {
        do {
            isEnabled = try authorizationStore.isEnabled()
            authorizations = try authorizationStore.listAuthorizations().filter {
                $0.revokedAt == nil
            }
            refreshReconnectRequirements()
            error = nil
            failedClient = nil
        } catch {
            self.error = .loadFailed
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            try authorizationStore.setEnabled(enabled)
            isEnabled = enabled
            generatedConfiguration = nil
            copiedConfiguration = nil
            error = nil
            failedClient = nil
        } catch {
            if let restoredValue = try? authorizationStore.isEnabled() {
                isEnabled = restoredValue
            }
            self.error = .updateFailed
        }
    }

    func createAuthorization() {
        let normalizedName = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty, normalizedName.count <= 100 else {
            error = .invalidClientName
            return
        }
        let helperURL = helperExecutableURL()
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            error = .helperMissing
            return
        }
        do {
            let authorization = try authorizationStore.createAuthorization(
                displayName: normalizedName,
                helperExecutablePath: helperURL.path
            )
            generatedConfiguration = try BuddyMCPIntegrationConfig(
                authorization: authorization,
                helperExecutableURL: helperURL
            )
            clientName = ""
            authorizations = try authorizationStore.listAuthorizations().filter {
                $0.revokedAt == nil
            }
            refreshReconnectRequirements()
            copiedConfiguration = nil
            error = nil
            failedClient = nil
        } catch BuddyMCPAuthorizationError.activeClientNameExists,
                BuddyMCPAuthorizationError.activeIntegrationExists {
            self.error = .duplicateClient
            failedClient = nil
        } catch {
            self.error = .authorizationFailed
            failedClient = nil
        }
    }

    func isAvailable(_ client: MCPClientKind) -> Bool {
        integrationService.isAvailable(client)
    }

    func applicationIcon(_ client: MCPClientKind) -> NSImage? {
        integrationService.applicationIcon(client)
    }

    func activeAuthorization(for client: MCPClientKind) -> BuddyMCPAuthorizationRecord? {
        authorizations.first {
            $0.integrationIdentifier == client.rawValue && $0.revokedAt == nil
        }
    }

    func needsReconnect(_ authorization: BuddyMCPAuthorizationRecord) -> Bool {
        authorizationsNeedingReconnect.contains(authorization.clientId)
    }

    func needsReconnect(_ client: MCPClientKind) -> Bool {
        activeAuthorization(for: client).map(needsReconnect) ?? false
    }

    func connect(_ client: MCPClientKind) {
        guard integrationInProgress == nil else { return }
        guard activeAuthorization(for: client) == nil else { return }
        guard integrationService.isAvailable(client) else {
            error = .clientUnavailable
            return
        }
        let helperURL = helperExecutableURL()
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            error = .helperMissing
            return
        }
        integrationInProgress = client
        error = nil
        failedClient = nil
        let authorizationStore = authorizationStore
        let integrationService = integrationService
        Task.detached(priority: .userInitiated) { [weak self] in
            let result: (authorizations: [BuddyMCPAuthorizationRecord], error: TranscriptAgentAccessError?)
            do {
                try integrationService.preflight(client)
                let authorization = try authorizationStore.createAuthorization(
                    displayName: client.displayName,
                    integrationIdentifier: client.rawValue,
                    helperExecutablePath: helperURL.path
                )
                do {
                    let configuration = try BuddyMCPIntegrationConfig(
                        authorization: authorization,
                        helperExecutableURL: helperURL
                    )
                    try integrationService.install(client, configuration: configuration)
                } catch {
                    do {
                        try authorizationStore.discardAuthorization(
                            clientId: authorization.clientId
                        )
                    } catch {
                        try? authorizationStore.revokeAuthorization(
                            clientId: authorization.clientId
                        )
                    }
                    throw error
                }
                result = (
                    try authorizationStore.listAuthorizations().filter { $0.revokedAt == nil },
                    nil
                )
            } catch let integrationError as MCPClientIntegrationError {
                result = (
                    ((try? authorizationStore.listAuthorizations()) ?? []).filter {
                        $0.revokedAt == nil
                    },
                    Self.accessError(for: integrationError)
                )
            } catch BuddyMCPAuthorizationError.activeClientNameExists,
                    BuddyMCPAuthorizationError.activeIntegrationExists {
                result = (
                    ((try? authorizationStore.listAuthorizations()) ?? []).filter {
                        $0.revokedAt == nil
                    },
                    .duplicateClient
                )
            } catch {
                result = (
                    ((try? authorizationStore.listAuthorizations()) ?? []).filter {
                        $0.revokedAt == nil
                    },
                    .integrationFailed
                )
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                authorizations = result.authorizations
                refreshReconnectRequirements()
                if result.error == nil {
                    generatedConfiguration = nil
                    copiedConfiguration = nil
                }
                error = result.error
                failedClient = result.error == nil ? nil : client
                integrationInProgress = nil
            }
        }
    }

    func revoke(_ authorization: BuddyMCPAuthorizationRecord) {
        guard let identifier = authorization.integrationIdentifier,
              let client = MCPClientKind(rawValue: identifier),
              authorization.revokedAt == nil
        else {
            revokeManualAuthorization(authorization)
            return
        }

        integrationInProgress = client
        let authorizationStore = authorizationStore
        let integrationService = integrationService
        Task.detached(priority: .userInitiated) { [weak self] in
            var configurationRemovalFailed = false
            do {
                try integrationService.remove(client)
            } catch {
                configurationRemovalFailed = true
            }

            let result: (authorizations: [BuddyMCPAuthorizationRecord], error: TranscriptAgentAccessError?)
            do {
                try authorizationStore.revokeAuthorization(clientId: authorization.clientId)
                result = (
                    try authorizationStore.listAuthorizations(),
                    configurationRemovalFailed ? .configurationRemovalFailed : nil
                )
            } catch {
                result = (
                    ((try? authorizationStore.listAuthorizations()) ?? []).filter {
                        $0.revokedAt == nil
                    },
                    .revokeFailed
                )
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                authorizations = result.authorizations.filter { $0.revokedAt == nil }
                refreshReconnectRequirements()
                if generatedConfiguration?.authorization.clientId == authorization.clientId {
                    generatedConfiguration = nil
                }
                error = result.error
                failedClient = result.error == nil ? nil : client
                integrationInProgress = nil
            }
        }
    }

    private func revokeManualAuthorization(_ authorization: BuddyMCPAuthorizationRecord) {
        do {
            try authorizationStore.revokeAuthorization(clientId: authorization.clientId)
            authorizations = try authorizationStore.listAuthorizations().filter {
                $0.revokedAt == nil
            }
            refreshReconnectRequirements()
            if generatedConfiguration?.authorization.clientId == authorization.clientId {
                generatedConfiguration = nil
            }
            error = nil
            failedClient = nil
        } catch {
            self.error = .revokeFailed
        }
    }

    func removeConnection(_ client: MCPClientKind) {
        guard let authorization = activeAuthorization(for: client) else { return }
        revoke(authorization)
    }

    func copyStandardConfiguration() {
        guard let text = generatedConfiguration?.standardJSON else { return }
        copy(text, kind: .standardJSON)
    }

    func copyCodexConfiguration() {
        guard let text = generatedConfiguration?.codexTOML else { return }
        copy(text, kind: .codexTOML)
    }

    private func copy(_ text: String, kind: ConfigurationKind) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedConfiguration = kind
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if self?.copiedConfiguration == kind {
                self?.copiedConfiguration = nil
            }
        }
    }

    private func refreshReconnectRequirements() {
        let currentHash = BuddyMCPAuthorizationStore.helperExecutablePathHash(
            helperExecutableURL().path
        )
        authorizationsNeedingReconnect = Set(
            authorizations.compactMap { authorization in
                authorization.helperExecutablePathHash == currentHash
                    ? nil
                    : authorization.clientId
            }
        )
    }

    nonisolated private static func accessError(
        for error: MCPClientIntegrationError
    ) -> TranscriptAgentAccessError {
        switch error {
        case .clientUnavailable:
            return .clientUnavailable
        case .clientCommandUnavailable:
            return .clientCommandUnavailable
        case .configurationConflict:
            return .configurationConflict
        case .invalidConfiguration:
            return .invalidClientConfiguration
        case .unsafeConfigurationPath:
            return .unsafeClientConfiguration
        case .writeFailed:
            return .clientConfigurationWriteFailed
        case .commandFailed:
            return .clientInstallationRejected
        }
    }
}
