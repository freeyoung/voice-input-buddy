import CoreGraphics

/// Navigation-key decoration is not evidence of an independently held Fn key.
enum KeyboardHardwareModifierPolicy {
    static func normalized(_ flags: CGEventFlags, fnKeyDown: Bool) -> CGEventFlags {
        if fnKeyDown { return flags.union(.maskSecondaryFn) }
        return flags.contains(.maskNumericPad) ? flags.subtracting(.maskSecondaryFn) : flags
    }

    static func current() -> CGEventFlags {
        normalized(CGEventSource.flagsState(.hidSystemState),
            fnKeyDown: CGEventSource.keyState(.hidSystemState, key: 63))
    }

    /// A fresh, read-only observation for intermittent paste failures. Queries
    /// are sequential, so these fields may differ from the flags that blocked paste.
    static func diagnosticSnapshot() -> String {
        let raw = CGEventSource.flagsState(.hidSystemState)
        let combined = CGEventSource.flagsState(.combinedSessionState)
        let fnDown = CGEventSource.keyState(.hidSystemState, key: 63)
        let navigationKeys: [CGKeyCode] = [115, 116, 117, 119, 121, 123, 124, 125, 126]
        let held = navigationKeys.filter {
            CGEventSource.keyState(.hidSystemState, key: $0)
        }.map(String.init).joined(separator: ",")
        return "observed_raw_flags=\(raw.rawValue) observed_combined_flags=\(combined.rawValue) " +
            "observed_fn_key_down=\(fnDown) observed_effective_flags=\(normalized(raw, fnKeyDown: fnDown).rawValue) " +
            "observed_navigation_keys=\(held.isEmpty ? "none" : held)"
    }
}
