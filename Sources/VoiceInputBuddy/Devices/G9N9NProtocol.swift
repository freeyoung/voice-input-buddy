import Foundation
import CoreBluetooth

/// Public G9N9N transport facts. Names and USB IDs identify candidates, not authenticity.
/// References: ATVVoice (ATVV v1.0), vibe-mote (Consumer Control reports).
enum G9N9NProtocol {
    static let vendorID = 0x18D1
    static let productID = 0x9450

    static func isCandidateName(_ raw: String?) -> Bool {
        guard let raw else { return false }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return ["chromecast", "chromecast remote", "chromecast voice remote", "g9n9n"].contains(name)
    }

    static func isModelNumber(_ raw: String) -> Bool {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "G9N9N"
    }

    static let consumerButtons: [UInt16: RemoteButton] = [
        0x0042: .up, 0x0043: .down, 0x0044: .left, 0x0045: .right,
        0x0041: .ok, 0x0224: .back, 0x0223: .home,
        0x00E9: .volumeUp, 0x00EA: .volumeDown, 0x00E2: .mute,
        0x0077: .youtube, 0x0078: .netflix,
    ]

    /// Known Consumer Control interface, with or without its report-ID byte.
    /// Unknown reports are ignored, never interpreted as an all-keys release.
    static func usages(reportID: UInt32, data: Data) -> Set<UInt16>? {
        guard reportID == 2 else { return nil }
        var bytes = Array(data)
        if bytes.count == 3, bytes[0] == 2 { bytes.removeFirst() }
        guard bytes.count == 2 else { return nil }
        let usage = UInt16(bytes[0]) | UInt16(bytes[1]) << 8
        if usage == 0 { return [] }
        guard let button = consumerButtons[usage] else { return nil }
        // The common mapping engine operates on canonical button IDs.
        return [button.hidUsage]
    }

    static func requiresPairing(_ error: Error) -> Bool {
        let value = error as NSError
        return value.domain == CBATTErrorDomain && [
            CBATTError.insufficientAuthentication.rawValue,
            CBATTError.insufficientEncryption.rawValue,
        ].contains(value.code)
    }

    static func acceptsCapabilities(_ caps: ATVVCapabilities) -> Bool {
        caps.version == 0x0100 && caps.codecs & 0x02 != 0 &&
            caps.selectedCodec == 0x02 && (1...512).contains(caps.frameSize)
    }
}

/// Both asynchronous discovery results are mandatory; neither alone grants audio readiness.
struct G9N9NReadiness {
    private(set) var modelConfirmed = false
    private(set) var audioConfirmed = false
    var isReady: Bool { modelConfirmed && audioConfirmed }

    @discardableResult mutating func acceptModel(_ modelNumber: String) -> Bool {
        modelConfirmed = G9N9NProtocol.isModelNumber(modelNumber)
        return modelConfirmed
    }

    @discardableResult mutating func acceptCapabilities(_ caps: ATVVCapabilities) -> Bool {
        audioConfirmed = G9N9NProtocol.acceptsCapabilities(caps)
        return audioConfirmed
    }
}
