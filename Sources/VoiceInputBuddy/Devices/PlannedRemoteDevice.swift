/// Product scope, separate from the catalog admitting validated hardware connections.
/// Planned devices remain unavailable until their public adapters are implemented and tested.
enum PlannedRemoteDevice: String, CaseIterable, Identifiable {
    case xiaomi
    case chromecastG9N9N
    case googleStreamerGY3LE
    case siriRemote

    var id: String { rawValue }
    var titleKey: String { "remote.catalog.\(rawValue).title" }

    var isAvailable: Bool { self == .xiaomi }

    var icon: String {
        self == .siriRemote ? "appletvremote.gen4.fill" : "antenna.radiowaves.left.and.right"
    }

    /// Google manufacturer model numbers, not player models or seller compatibility labels.
    var googleHardwareModelNumber: String? {
        switch self {
        case .chromecastG9N9N: return "G9N9N"
        case .googleStreamerGY3LE: return "GY3LE"
        case .xiaomi, .siriRemote: return nil
        }
    }
}
