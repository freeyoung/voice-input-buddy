import ApplicationServices

/// The system-wide AX object's timeout applies only to this process, not other apps.
/// Swift initializes this once; ordinary attribute reads do not repeatedly reconfigure AX.
enum AccessibilityMessaging {
    private static let setupResult = AXUIElementSetMessagingTimeout(
        AXUIElementCreateSystemWide(), 0.25
    )

    static func prepareQueries() {
        _ = setupResult
    }
}
