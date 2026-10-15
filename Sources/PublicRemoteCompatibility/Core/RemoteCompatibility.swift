import Foundation

public enum RemoteButton: String, CaseIterable, Codable, Identifiable, Sendable {
    case power
    case up
    case left
    case ok
    case right
    case down
    case back
    case volumeUp = "volume_up"
    case home
    case volumeDown = "volume_down"
    case menu
    case tv

    public var id: String { rawValue }
}

public enum RemoteButtonPhase: String, Codable, Sendable {
    case press
    case release
}

public enum RemoteVoiceStartResult: Equatable, Sendable {
    case started
    case busy
    case unavailable
}

public struct PhoneRemoteInvitation: Equatable, Sendable {
    public let listenerID: String
    public let invitationID: String
    public let token: String
    public let hosts: [String]
    public let port: UInt16
    public let expiresAt: Date

    public init(
        listenerID: String,
        invitationID: String,
        token: String,
        hosts: [String],
        port: UInt16,
        expiresAt: Date
    ) {
        self.listenerID = listenerID
        self.invitationID = invitationID
        self.token = token
        self.hosts = hosts
        self.port = port
        self.expiresAt = expiresAt
    }

    public var url: URL? { nil }
}

public struct WatchBluetoothAudioSignalMetrics: Equatable, Sendable {
    public private(set) var sampleCount = 0
    public private(set) var nonZeroSampleCount = 0
    public private(set) var peak = 0
    public private(set) var squaredSampleSum: UInt64 = 0

    public init() {}

    public var rms: Int {
        guard sampleCount > 0 else { return 0 }
        return Int(sqrt(Double(squaredSampleSum) / Double(sampleCount)))
    }

    public mutating func append(_ samples: [Int16]) {
        for sample in samples {
            let magnitude = abs(Int(sample))
            sampleCount += 1
            if sample != 0 { nonZeroSampleCount += 1 }
            peak = max(peak, magnitude)
            squaredSampleSum += UInt64(magnitude * magnitude)
        }
    }
}

public enum WebRemoteConfiguration {
    public static func relayURL(
        environment _: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary _: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> URL? {
        nil
    }
}

public enum WebRemoteSessionState: Equatable, Sendable {
    case disabled
    case unavailable
    case connecting
    case waitingForPhone(joinURL: URL, pairingCode: String, expiresAt: Date?)
    case awaitingApproval(joinURL: URL, pairingCode: String, deviceName: String)
    case connected(deviceName: String)
    case failed(String)

    public var isEnabled: Bool {
        switch self {
        case .disabled, .unavailable, .failed:
            return false
        default:
            return true
        }
    }
}
