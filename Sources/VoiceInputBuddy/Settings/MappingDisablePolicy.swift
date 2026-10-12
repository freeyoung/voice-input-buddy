import Foundation

enum MappingDisablePolicy {
    static func configuration(disabling: Bool, current: ConfiguredButtonAction,
                              backup: ConfiguredButtonAction?, button: RemoteButton,
                              trigger: ButtonTrigger) -> ConfiguredButtonAction {
        if disabling { return .disabled }
        if let backup, backup.action != .disabled { return backup }
        // A previously disabled slot has no action to restore. Use the device default
        // for a click, or an unconfigured shortcut (no key injection) for other gestures.
        return ConfiguredButtonAction(action: trigger == .singleClick
            ? AppSettings.defaultBindings[button] ?? .customShortcut : .customShortcut, shortcut: nil)
    }
}
