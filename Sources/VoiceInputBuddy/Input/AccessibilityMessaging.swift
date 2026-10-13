import ApplicationServices

/// The system-wide AX object's timeout applies only to this process, not other apps.
/// Swift initializes this once; ordinary attribute reads do not repeatedly reconfigure AX.
enum AccessibilityMessaging {
    private static let setupResult = configureTimeout(
        install: { AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25) },
        reportFailure: AppLogger.shared.write
    )

    @discardableResult
    static func configureTimeout(install: () -> AXError, reportFailure: (String) -> Void) -> AXError {
        let result = install()
        if result != .success {
            reportFailure("AX TIMEOUT configuration_failed code=\(result.rawValue)")
        }
        return result
    }

    static func prepareQueries() {
        _ = setupResult
    }
}
