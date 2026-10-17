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
}
