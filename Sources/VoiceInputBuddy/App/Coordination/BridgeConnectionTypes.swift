import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation

struct LocalTestRemoteSessionResponse: Decodable {
    let relayMode: String
    let sessionID: String
    let creatorToken: String
    let joinURL: String
    let webSocketURL: String
    let pairingCode: String
    let expiresAt: String

    private enum CodingKeys: String, CodingKey {
        case relayMode
        case sessionID = "sessionId"
        case creatorToken
        case joinURL
        case webSocketURL
        case pairingCode
        case expiresAt
    }
}

enum VoiceKeyCompatibilityWarning: Equatable {
    case karabiner
    case otherInputTool

    var messageKey: String {
        switch self {
        case .karabiner:
            return "connection.voice_key_compatibility.karabiner_detail"
        case .otherInputTool:
            return "connection.voice_key_compatibility.other_detail"
        }
    }
}
