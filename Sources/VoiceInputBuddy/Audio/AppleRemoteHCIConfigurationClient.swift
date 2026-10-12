import AppleRemoteHCIProtocol
import Foundation
import Security

final class AppleRemoteHCIConfigurationClient {
    enum Result: Equatable {
        case ready
        case failed(String)
    }

    private var connection: NSXPCConnection?
    private var prepared = false

    deinit {
        stop()
    }

    private let scheduleTimeout: (@escaping () -> Void) -> Void
    private let requestPreparation: ((NSXPCConnection, @escaping (Bool, String) -> Void) -> Void)?

    init(scheduleTimeout: @escaping (@escaping () -> Void) -> Void = { operation in
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: operation)
    }, requestPreparation: ((NSXPCConnection, @escaping (Bool, String) -> Void) -> Void)? = nil) {
        self.scheduleTimeout = scheduleTimeout
        self.requestPreparation = requestPreparation
    }

    func prepare(completion: @escaping (Result) -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.prepare(completion: completion) }
            return
        }
        guard connection == nil else {
            completion(.failed(prepared ? "configuration_already_prepared" : "configuration_in_progress"))
            return
        }
        let connection = NSXPCConnection(
            machServiceName: AppleRemoteHCIConstants.machServiceName, options: .privileged
        )
        self.connection = connection
        let latch = CompletionLatch()
        let finish: (Bool, String) -> Void = { [weak self, weak connection] succeeded, status in
            let deliver = {
                guard latch.claim() else { return }
                guard let self, let connection, self.connection === connection else {
                    completion(.failed("configuration_cancelled"))
                    return
                }
                self.prepared = succeeded
                if !succeeded { self.stop() }
                completion(succeeded ? .ready : .failed(status))
            }
            if Thread.isMainThread { deliver() }
            else { DispatchQueue.main.async(execute: deliver) }
        }
        connection.remoteObjectInterface = NSXPCInterface(with: AppleRemoteHCIServiceProtocol.self)
        let disconnected: (String) -> Void = { [weak self, weak connection] status in
            DispatchQueue.main.async {
                finish(false, status)
                guard let self, let connection, self.connection === connection else { return }
                self.prepared = false
                self.connection = nil
                connection.invalidate()
            }
        }
        connection.invalidationHandler = { disconnected("hci_helper_invalidated") }
        connection.interruptionHandler = { disconnected("hci_helper_interrupted") }
        scheduleTimeout { finish(false, "hci_helper_timed_out") }
        if let requestPreparation {
            requestPreparation(connection, finish)
            return
        }
        AppLogger.shared.write("APPLE REMOTE HCI XPC phase=connecting " + Self.clientSignatureDiagnostic())
        connection.resume()
        let remote = connection.remoteObjectProxyWithErrorHandler { error in
            finish(false, "hci_helper_unreachable_\((error as NSError).code)")
        }
        guard let helper = remote as? AppleRemoteHCIServiceProtocol else {
            finish(false, "hci_helper_interface_unavailable")
            return
        }
        helper.prepareConfiguration { finish($0, $1) }
    }

    private static func clientSignatureDiagnostic() -> String {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            Bundle.main.bundleURL as CFURL,
            [],
            &staticCode
        ) == errSecSuccess, let staticCode else {
            return "client_signature=unavailable"
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
        let values = information as? [String: Any]
        else {
            return "client_signature=unavailable"
        }
        let identifier = values[kSecCodeInfoIdentifier as String] as? String
        let teamIdentifier = values[kSecCodeInfoTeamIdentifier as String] as? String
        let isAdHoc = teamIdentifier == nil
        return "client_identifier_matches=\(identifier == AppleRemoteHCIConstants.expectedClientIdentifier) " +
            "client_team_matches=\(teamIdentifier == AppleRemoteHCIConstants.expectedTeamIdentifier) " +
            "client_signature_adhoc=\(isAdHoc)"
    }

    func stop() {
        guard let connection else { return }
        if prepared,
           let helper = connection.remoteObjectProxyWithErrorHandler({ _ in })
            as? AppleRemoteHCIServiceProtocol {
            helper.releaseConfiguration { _, _ in }
        }
        prepared = false
        self.connection = nil
        connection.invalidate()
    }

    func sealAuthorizationRight(completion: @escaping (Bool) -> Void) {
        guard let connection else {
            completion(false)
            return
        }
        let latch = CompletionLatch()
        let remote = connection.remoteObjectProxyWithErrorHandler { _ in
            guard latch.claim() else { return }
            completion(false)
        }
        guard let helper = remote as? AppleRemoteHCIServiceProtocol else {
            completion(false)
            return
        }
        helper.sealAuthorizationRight { succeeded, _ in
            guard latch.claim() else { return }
            completion(succeeded)
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 8) {
            guard latch.claim() else { return }
            completion(false)
        }
    }

    private final class CompletionLatch: @unchecked Sendable {
        private let lock = NSLock()
        private var completed = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !completed else { return false }
            completed = true
            return true
        }
    }
}
