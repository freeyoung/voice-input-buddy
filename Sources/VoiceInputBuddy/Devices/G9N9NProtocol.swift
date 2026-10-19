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
        return ["chromecast", "chromecast remote", "chromecast voice remote", "chromecast 遥控器", "g9n9n"].contains(name)
    }

    static let consumerButtons: [UInt16: RemoteButton] = [
        0x0042: .up, 0x0043: .down, 0x0044: .left, 0x0045: .right,
        0x0041: .ok, 0x0224: .back, 0x0223: .home,
        0x00E9: .volumeUp, 0x00EA: .volumeDown, 0x00E2: .mute,
        0x0077: .youtube, 0x0078: .netflix,
        // Captured G9N9N Consumer Control reports: vibe-mote/keys.py.
        0x0189: .input, 0x019E: .power,
    ]

    /// Known Consumer Control interface, with or without its report-ID byte.
    /// Malformed or unrelated reports are ignored; unknown usages in a valid
    /// Consumer Control snapshot do not discard known key edges.
    static func usages(reportID: UInt32, data: Data) -> Set<UInt16>? {
        guard reportID == 2 else { return nil }
        var bytes = Array(data)
        if bytes.count % 2 == 1, bytes.first == 2 { bytes.removeFirst() }
        guard !bytes.isEmpty, bytes.count % 2 == 0 else { return nil }
        var usages = Set<UInt16>()
        for offset in stride(from: 0, to: bytes.count, by: 2) {
            let usage = UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
            if usage == 0 { continue }
            guard let button = consumerButtons[usage] else { continue }
            usages.insert(button.hidUsage)
        }
        return usages
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
            caps.selectedCodec == 0x02 && ATVVProtocol.supportsFrameSize(caps.frameSize)
    }
}

/// Both asynchronous discovery results are mandatory; neither alone grants audio readiness.
struct G9N9NReadiness {
    private(set) var identityConfirmed = false
    private(set) var audioConfirmed = false
    var isReady: Bool { identityConfirmed && audioConfirmed }

    // Retail model and DIS model strings differ (the tested G9N9N reports A3).
    // Validate the same peripheral's PnP identity, never gate on its model string.
    @discardableResult mutating func acceptIdentity(_ identity: RemoteHIDIdentity?) -> Bool {
        identityConfirmed = identity == .chromecast
        return identityConfirmed
    }

    @discardableResult mutating func acceptCapabilities(_ caps: ATVVCapabilities) -> Bool {
        audioConfirmed = G9N9NProtocol.acceptsCapabilities(caps)
        return audioConfirmed
    }
}
