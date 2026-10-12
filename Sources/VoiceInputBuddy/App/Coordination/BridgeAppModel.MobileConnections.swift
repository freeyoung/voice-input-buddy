import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation
import BuddyRemoteCore

extension BridgeAppModel {
    func enablePhoneRemoteConnection() {
        guard started, !isPhoneRemoteConnectionEnabled else { return }
        guard membershipFeature.canStartCompanionConnection else {
            objectWillChange.send()
            return
        }
        isPhoneRemoteConnectionEnabled = true
        phoneRemoteServer.start()
        watchBluetoothServer.start()
        AppLogger.shared.write("PHONE REMOTE enabled_by_user")
    }

    func disablePhoneRemoteConnection() {
        guard isPhoneRemoteConnectionEnabled else { return }
        isPhoneRemoteConnectionEnabled = false
        isPhoneRemoteConnected = false
        isWatchRemoteConnected = false
        cancelPhoneApproval()
        phoneRemoteServer.stop()
        watchBluetoothServer.stop()
        AppLogger.shared.write("PHONE REMOTE disabled_by_user")
    }

    func togglePhoneRemoteConnection() {
        if isPhoneRemoteConnectionEnabled {
            disablePhoneRemoteConnection()
        } else {
            enablePhoneRemoteConnection()
        }
    }

    var isWatchRemoteConnectionEnabled: Bool {
        isPhoneRemoteConnectionEnabled
    }

    func enableWatchRemoteConnection() {
        enablePhoneRemoteConnection()
    }

    func toggleWatchRemoteConnection() {
        togglePhoneRemoteConnection()
    }

    func enableWebRemoteConnection() {
        guard started else { return }
        guard membershipFeature.canStartCompanionConnection else {
            webRemoteState = .membershipRequired
            return
        }
        switch webRemoteState {
        case .failed:
            webRemoteSessionIdempotencyKey = nil
        case let .waitingForPhone(_, _, expiresAt),
             let .plusRequired(_, _, expiresAt):
            if let expiresAt, expiresAt <= Date() {
                webRemoteSessionIdempotencyKey = nil
            }
        default:
            break
        }
        webRemoteSessionGeneration &+= 1
        webRemoteSessionOperationCounter &+= 1
        let generation = webRemoteSessionGeneration
        let operationID = "web_remote_\(webRemoteSessionOperationCounter)"
        webRemoteState = .connecting
        AppLogger.shared.write(
            "WEB REMOTE SESSION operation_id=\(operationID) " +
                "phase=requested result=unknown"
        )
        Task { @MainActor [weak self] in
            await self?.startWebRemoteConnection(
                generation: generation,
                operationID: operationID
            )
        }
    }

    func disableWebRemoteConnection() {
        webRemoteSessionGeneration &+= 1
        webRemoteSessionIdempotencyKey = nil
        webRemoteClient.stop()
        AppLogger.shared.write(
            "WEB REMOTE SESSION phase=cancelled result=cancelled " +
                "reason=cancelled_by_user"
        )
    }

    @MainActor
    private func startWebRemoteConnection(
        generation: UInt64,
        operationID: String
    ) async {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String

        if isWebRemoteMembershipBypassEnabled,
           let relayURL = WebRemoteConfiguration.relayURL(),
           Self.isLoopbackRelayURL(relayURL)
        {
            do {
                let idempotencyKey = webRemoteSessionIdempotencyKey
                    ?? UUID().uuidString.lowercased()
                webRemoteSessionIdempotencyKey = idempotencyKey
                let relayAuthorization = try await localTestWebRemoteAuthorization(
                    relayURL: relayURL,
                    idempotencyKey: idempotencyKey
                )
                guard generation == webRemoteSessionGeneration else { return }
                webRemoteClient.start(
                    authorization: relayAuthorization,
                    macName: Host.current().localizedName ?? "Mac",
                    appVersion: version,
                    buttonTitles: remoteButtonTitles
                )
                AppLogger.shared.write(
                    "WEB REMOTE SESSION operation_id=\(operationID) " +
                        "phase=authorized result=accepted relay_mode=cloudflare_v1 " +
                        "membership_check=bypassed"
                )
            } catch {
                guard generation == webRemoteSessionGeneration else { return }
                webRemoteState = .failed(webRemoteFailureMessage(.invalidResponse))
                AppLogger.shared.write(
                    "WEB REMOTE SESSION operation_id=\(operationID) " +
                        "phase=failed result=failed reason=local_test_session_unavailable"
                )
            }
            return
        }

        if membershipFeature.supportsRemoteSessionAuthorization {
            do {
                let idempotencyKey = webRemoteSessionIdempotencyKey
                    ?? UUID().uuidString.lowercased()
                webRemoteSessionIdempotencyKey = idempotencyKey
                let authorization = try await membershipFeature
                    .createRemoteSessionAuthorization(
                        idempotencyKey: idempotencyKey,
                        clientContractVersion: 1,
                        testMembershipBypass: isWebRemoteMembershipBypassEnabled
                    )
                guard generation == webRemoteSessionGeneration else {
                    AppLogger.shared.write(
                        "WEB REMOTE SESSION operation_id=\(operationID) " +
                            "phase=cancelled result=cancelled reason=stale_generation"
                    )
                    return
                }
                guard let sessionID = authorization.sessionID,
                      let joinURL = authorization.joinURL,
                      let pairingCode = authorization.pairingCode
                else {
                    throw HostRemoteSessionFailure.invalidResponse
                }
                if authorization.access == .plusRequired {
                    webRemoteState = .membershipRequired
                    AppLogger.shared.write(
                        "WEB REMOTE SESSION operation_id=\(operationID) " +
                            "phase=previewed result=rejected reason=plus_required " +
                            "relay_mode=cloudflare_v1"
                    )
                    return
                }
                guard let creatorToken = authorization.creatorToken else {
                    throw HostRemoteSessionFailure.invalidResponse
                }
                let relayAuthorization = WebRemoteSessionAuthorization.cloudflareV1(
                    webSocketURL: authorization.webSocketURL,
                    sessionID: sessionID,
                    creatorToken: creatorToken,
                    joinURL: joinURL,
                    pairingCode: pairingCode,
                    expiresAt: authorization.expiresAt
                )
                webRemoteClient.start(
                    authorization: relayAuthorization,
                    macName: Host.current().localizedName ?? "Mac",
                    appVersion: version,
                    buttonTitles: remoteButtonTitles
                )
                AppLogger.shared.write(
                    "WEB REMOTE SESSION operation_id=\(operationID) " +
                        "phase=authorized result=accepted relay_mode=cloudflare_v1 " +
                        "membership_check=\(isWebRemoteMembershipBypassEnabled ? "bypassed" : "required")"
                )
                return
            } catch let failure as HostRemoteSessionFailure {
                guard generation == webRemoteSessionGeneration else { return }
                if failure == .signInRequired || failure == .plusRequired {
                    webRemoteState = .membershipRequired
                } else {
                    webRemoteState = .failed(webRemoteFailureMessage(failure))
                }
                AppLogger.shared.write(
                    "WEB REMOTE SESSION operation_id=\(operationID) " +
                        "phase=failed result=failed reason=\(webRemoteFailureReason(failure))"
                )
                return
            } catch {
                guard generation == webRemoteSessionGeneration else { return }
                webRemoteState = .failed(
                    webRemoteFailureMessage(.invalidResponse)
                )
                AppLogger.shared.write(
                    "WEB REMOTE SESSION operation_id=\(operationID) " +
                        "phase=failed result=failed reason=invalid_response"
                )
                return
            }
        }

        guard generation == webRemoteSessionGeneration else { return }
        webRemoteState = .unavailable
        AppLogger.shared.write(
            "WEB REMOTE SESSION operation_id=\(operationID) " +
                "phase=failed result=failed reason=membership_component_unavailable"
        )
    }

    var webRemoteServiceEnvironment: String {
        membershipFeature.serviceEnvironmentForDiagnostics
    }

    var isWebRemoteMembershipBypassEnabled: Bool {
        membershipFeature.remoteSessionMembershipBypassEnabled
    }

    // 兼容现有固定镜像的旧 UI 合同；不显示或恢复独立免检开关。
    var isWebRemoteMembershipBypassAvailable: Bool { false }

    func setWebRemoteMembershipBypassEnabled(_ enabled: Bool) {}

    private static func isLoopbackRelayURL(_ url: URL) -> Bool {
        guard url.scheme == "ws", let host = url.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private func localTestWebRemoteAuthorization(
        relayURL: URL,
        idempotencyKey: String
    ) async throws -> WebRemoteSessionAuthorization {
        guard var components = URLComponents(url: relayURL, resolvingAgainstBaseURL: false),
              Self.isLoopbackRelayURL(relayURL)
        else { throw HostRemoteSessionFailure.invalidResponse }
        components.scheme = relayURL.scheme == "wss" ? "https" : "http"
        components.path = "/__local-test/remote-session"
        components.query = nil
        components.fragment = nil
        guard let endpoint = components.url else {
            throw HostRemoteSessionFailure.invalidResponse
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 201
        else { throw HostRemoteSessionFailure.invalidResponse }
        let payload = try JSONDecoder().decode(LocalTestRemoteSessionResponse.self, from: data)
        guard payload.relayMode == "cloudflare_v1",
              let webSocketURL = URL(string: payload.webSocketURL),
              let joinURL = URL(string: payload.joinURL),
              Self.isLoopbackRelayURL(webSocketURL),
              webSocketURL.host?.lowercased() == relayURL.host?.lowercased(),
              webSocketURL.port == relayURL.port,
              payload.sessionID.count == 22,
              payload.creatorToken.count == 43,
              payload.pairingCode.count == 4
        else { throw HostRemoteSessionFailure.invalidResponse }
        return .cloudflareV1(
            webSocketURL: webSocketURL,
            sessionID: payload.sessionID,
            creatorToken: payload.creatorToken,
            joinURL: joinURL,
            pairingCode: payload.pairingCode,
            expiresAt: Self.webRemoteISO8601Date(payload.expiresAt)
        )
    }

    private static func webRemoteISO8601Date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private func webRemoteFailureMessage(
        _ failure: HostRemoteSessionFailure
    ) -> String {
        let key: String
        switch failure {
        case .signInRequired:
            key = "connection.web.failure.sign_in_required"
        case .deviceBindingRequired:
            key = "connection.web.failure.device_binding_required"
        case .plusRequired:
            key = "connection.web.failure.plus_required"
        case .upgradeRequired:
            key = "connection.web.failure.upgrade_required"
        case .unavailable:
            key = "connection.web.failure.unavailable"
        case .networkUnavailable:
            key = "connection.web.failure.network_unavailable"
        case .invalidResponse:
            key = "connection.web.failure.invalid_response"
        }
        return LocalizedMessage(key).text(
            using: LocalizationStore(
                settings: settings,
                resourceBundle: VoiceInputBuddyResourceBundle.mainOrDevelopment
            )
        )
    }

    private func webRemoteFailureReason(
        _ failure: HostRemoteSessionFailure
    ) -> String {
        switch failure {
        case .signInRequired: return "sign_in_required"
        case .deviceBindingRequired: return "device_binding_required"
        case .plusRequired: return "plus_required"
        case .upgradeRequired: return "upgrade_required"
        case .unavailable: return "remote_session_unavailable"
        case .networkUnavailable: return "network_unavailable"
        case .invalidResponse: return "invalid_response"
        }
    }

    func updatePhoneRemoteButtonTitles(
        bindings: [RemoteButton: ButtonAction],
        shortcuts: [RemoteButton: CustomKeyboardShortcut],
        applicationProfileIDs: [RemoteButton: UUID] = [:],
        customApplicationProfiles: [CustomApplicationProfile] = [],
        localization: LocalizationStore
    ) {
        var titles: [String: String] = [:]
        for button in RemoteButton.allCases {
            let action = bindings[button] ?? .disabled
            guard action != AppSettings.defaultBindings[button] else { continue }
            let fullTitle: String
            if action == .customShortcut {
                fullTitle = shortcuts[button]?.displayName(using: localization)
                    ?? action.displayName(using: localization)
            } else if action == .openCustomApplication,
                      let profileID = applicationProfileIDs[button],
                      let profile = customApplicationProfiles.first(where: { $0.id == profileID })
            {
                fullTitle = profile.displayName
            } else {
                fullTitle = action.displayName(using: localization)
            }
            titles[button.rawValue] = String(fullTitle.prefix(10))
        }
        remoteButtonTitles = titles
        phoneRemoteServer.updateButtonTitles(titles)
        watchBluetoothServer.updateButtonTitles(titles)
        webRemoteClient.updateButtonTitles(titles)
    }
}
