import Foundation

enum MappingDisablePolicy {
    static func configuration(disabling: Bool, current: ConfiguredButtonAction,
                              backup: ConfiguredButtonAction?, button: RemoteButton,
                              trigger: ButtonTrigger) -> ConfiguredButtonAction {
        if disabling { return .disabled }
        if current.action != .disabled { return current }
        if let backup, backup.action != .disabled { return backup }
        // A previously disabled slot has no action to restore. Use the device default
        // for a click, or an unconfigured shortcut (no key injection) for other gestures.
        return ConfiguredButtonAction(action: trigger == .singleClick
            ? AppSettings.defaultBindings[button] ?? .customShortcut : .customShortcut, shortcut: nil)
    }
}

/// A typed editor scope prevents another device, profile, button or gesture from
/// restoring this slot's action. Backups intentionally live only with the view.
struct MappingDisableScope: Hashable {
    let deviceID: UUID?
    let mappingProfileID: UUID?
    let button: RemoteButton
    let trigger: ButtonTrigger
}

struct MappingDisableEditor {
    private var backups: [MappingDisableScope: ConfiguredButtonAction] = [:]

    mutating func configuration(disabling: Bool, current: ConfiguredButtonAction,
                                scope: MappingDisableScope) -> ConfiguredButtonAction {
        if disabling, current.action != .disabled { backups[scope] = current }
        return MappingDisablePolicy.configuration(disabling: disabling, current: current,
            backup: backups[scope], button: scope.button, trigger: scope.trigger)
    }
}
