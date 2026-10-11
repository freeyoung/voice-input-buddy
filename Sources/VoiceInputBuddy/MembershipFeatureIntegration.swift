import Combine
import Foundation
import SwiftUI


enum HostButtonProfilesAccessDecision: Equatable {
    case allowed(validUntil: Date)
    case temporarilyOffline(validUntil: Date)
    case requiresPlus
    case unavailable
}

enum HostRemoteSessionAccess: Equatable {
    case authorized
    case plusRequired
}

struct HostRemoteSessionAuthorization: Equatable {
    let access: HostRemoteSessionAccess
    let webSocketURL: URL
    let sessionID: String?
    let creatorToken: String?
    let joinURL: URL?
    let pairingCode: String?
    let expiresAt: Date?
}

enum HostRemoteSessionFailure: Error, Equatable {
    case signInRequired
    case deviceBindingRequired
    case plusRequired
    case upgradeRequired
    case unavailable
    case networkUnavailable
    case invalidResponse
}

struct MembershipFeatureConfiguration: Equatable {
    let appVersion: String

    static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) -> MembershipFeatureConfiguration? {
        nil
    }
}

final class MembershipFeatureIntegration: ObservableObject, @unchecked Sendable {
    @Published private(set) var isFeatureVisible = false
    @Published private(set) var isEnvironmentSettingsVisible = false
    @Published private(set) var buttonProfilesAccessDecision: HostButtonProfilesAccessDecision = .unavailable
    @Published private(set) var canUseCompanionConnections = false
    @Published private(set) var accountDisplayName: String? = nil
    @Published private(set) var serviceEnvironmentForDiagnostics = "unavailable"

    private var localeIdentifier: String

    var supportsRemoteSessionAuthorization: Bool {
        false
    }

    init(localeIdentifier: String = Locale.current.identifier,
         configuration: MembershipFeatureConfiguration? = .current()) {
        self.localeIdentifier = localeIdentifier
    }

    @MainActor var sectionTitle: String {
        ""
    }

    var sectionSystemImage: String { "crown.fill" }

    @MainActor func updateLocaleIdentifier(_ identifier: String) {
        localeIdentifier = identifier
        objectWillChange.send()
    }

    @MainActor
    func refreshIfNeeded() {
    }

    @MainActor
    func settingsView() -> AnyView {
        AnyView(EmptyView())
    }

    @MainActor
    func membershipRequiredView(forButtonProfiles: Bool = false, remoteAuthorizationDenied: Bool = false, onOpenMembership: @escaping () -> Void) -> AnyView {
        AnyView(EmptyView())
    }

    var canStartCompanionConnection: Bool {
        false
    }

    var remoteSessionMembershipBypassEnabled: Bool {
        false
    }

    @MainActor
    func serviceEnvironmentSettingsView() -> AnyView {
        AnyView(EmptyView())
    }

    @MainActor
    func createRemoteSessionAuthorization(
        idempotencyKey: String,
        clientContractVersion: Int = 1,
        testMembershipBypass: Bool = false
    ) async throws -> HostRemoteSessionAuthorization {
        throw HostRemoteSessionFailure.unavailable
    }

}
extension MembershipFeatureIntegration: PrivateDiagnosticUploadProvider {
    func pendingPrivateDiagnosticRecords() async -> [PrivateDiagnosticUploadRecord] {
        return []
    }

    func markPrivateDiagnosticRecordsUploaded(_ recordIDs: Set<String>) async {
    }
}
