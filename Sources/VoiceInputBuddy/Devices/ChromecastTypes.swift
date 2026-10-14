import Foundation


/// 语音手势模式。`toggle` 为本产品默认；`hold` 保留给习惯按住说话的用户。
enum ChromecastVoiceMode: String, CaseIterable, Codable, Identifiable {
    case toggle
    case hold

    var id: String { rawValue }

    static let productDefault: ChromecastVoiceMode = .toggle

    var localizationKey: String {
        switch self {
        case .toggle: return "chromecast.mode.toggle"
        case .hold: return "chromecast.mode.hold"
        }
    }

    var detailLocalizationKey: String {
        switch self {
        case .toggle: return "chromecast.mode.toggle.detail"
        case .hold: return "chromecast.mode.hold.detail"
        }
    }
}

/// Shared voice capability vocabulary for the public adapters and Siri UI.
struct ChromecastDeclaredCapabilities: OptionSet, Equatable {
    let rawValue: Int

    static let controlEdges = ChromecastDeclaredCapabilities(rawValue: 1 << 0)
    static let voiceStream = ChromecastDeclaredCapabilities(rawValue: 1 << 1)
    static let touchSurface = ChromecastDeclaredCapabilities(rawValue: 1 << 2)
    static let battery = ChromecastDeclaredCapabilities(rawValue: 1 << 3)
    static let toggleVoiceGesture = ChromecastDeclaredCapabilities(rawValue: 1 << 4)
}

/// Chromecast 遥控器的普通按键。
///
/// 语音键不在这里：该遥控器的语音键不产生可靠 HID 边沿，语音由 ATVV 控制流驱动。
enum ChromecastRemoteControl: String, CaseIterable, Equatable {
    case power
    case up
    case down
    case left
    case right
    case select
    case back
    case home
    case mute
    case youtube
    case netflix
    case input
    case volumeUp = "volume_up"
    case volumeDown = "volume_down"

    /// Canonical mapping button for this physical control.
    var remoteButton: RemoteButton {
        switch self {
        case .power: return .power
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .select: return .ok
        case .back: return .back
        case .home: return .home
        case .mute: return .mute
        case .youtube: return .youtube
        case .netflix: return .netflix
        case .input: return .input
        case .volumeUp: return .volumeUp
        case .volumeDown: return .volumeDown
        }
    }

    /// 画布用的控制 ID。与 `ChromecastMappingCanvas.configurableControlIDs` 同值。
    var canvasControlID: String { rawValue }

    /// 当前产品允许全部普通键配置，包含左、确定、右。
    /// 历史豁免设置继续可读，但不得再次限制这三键。
    static let systemReservedControls: Set<ChromecastRemoteControl> = []

    /// 该键此刻是否仍交给系统。主开关全放开；`exceptions` 逐颗放开（两者相加生效）。
    static func isSystemManaged(
        _ control: ChromecastRemoteControl,
        allowSystemReservedKeys: Bool,
        exceptions: Set<String> = []
    ) -> Bool {
        guard systemReservedControls.contains(control) else { return false }
        return !(allowSystemReservedKeys || exceptions.contains(control.rawValue))
    }

    /// 给画布用的置灰表：从默认表里去掉已放开的键。
    static func canvasReservedControlIDs(
        allowSystemReservedKeys: Bool,
        exceptions: Set<String>
    ) -> Set<String> {
        Set(systemReservedControls
            .filter { isSystemManaged($0, allowSystemReservedKeys: allowSystemReservedKeys, exceptions: exceptions) }
            .map(\.rawValue))
    }
}
