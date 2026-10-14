import AppKit

/// Inserts at the current caret using public AX metadata and AXSelectedText.
/// Target text and the user's clipboard are never read or replaced.
final class CommonPhraseInserter {
    typealias Writer = (String, pid_t, @escaping (String?) -> Void) -> Void

    private struct Request {
        let operationID: UInt64
        let start: TimeInterval
        let text: String
        let processID: pid_t
        let completion: (String) -> Void
    }
    private let write: Writer
    private let logger: (String) -> Void
    private var queue: [Request] = []
    private var busy = false
    private var operation: UInt64 = 0

    init(write: @escaping Writer = { text, processID, completion in
        AccessibilityMessaging.queryQueue.async {
            let failure = insertAtCaret(text, processID: processID)
            DispatchQueue.main.async { completion(failure) }
        }
    }, logger: @escaping (String) -> Void = AppLogger.shared.write) {
        self.write = write
        self.logger = logger
    }

    func insert(_ text: String, into processID: pid_t, completion: @escaping (String) -> Void) {
        operation &+= 1
        logger("COMMON_PHRASES INSERT operation_id=\(operation) phase=requested")
        queue.append(Request(operationID: operation, start: ProcessInfo.processInfo.systemUptime,
            text: text, processID: processID, completion: completion))
        drain()
    }

    func cancelPending() {
        let pending = queue
        queue.removeAll()
        for request in pending { request.completion("common_phrases.error.cancelled") }
    }

    private func drain() {
        guard !busy, !queue.isEmpty else { return }
        busy = true
        let request = queue.removeFirst()
        write(request.text, request.processID) { [weak self] failure in
            guard let self else { return }
            self.logger("COMMON_PHRASES INSERT operation_id=\(request.operationID) phase=completed " +
                "result=\(failure == nil ? "inserted" : "failed") reason=\(failure ?? "ax_inserted") " +
                "elapsed_ms=\(Int((ProcessInfo.processInfo.systemUptime - request.start) * 1000))")
            self.busy = false
            request.completion(failure.map { "common_phrases.error.\($0)" } ?? "common_phrases.inserted")
            self.drain()
        }
    }

    static func insertAtCaret(_ text: String, processID: pid_t) -> String? {
        guard !SecureInputMonitor.isEnabled() else { return "input_unavailable" }
        guard KeyboardInjector.isAccessibilityTrusted else { return "accessibility_required" }
        guard processID != ProcessInfo.processInfo.processIdentifier,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == processID else { return "target_changed" }
        AccessibilityMessaging.prepareQueries()
        let application = AXUIElementCreateApplication(processID)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return "input_unavailable" }
        let element = unsafeBitCast(focused, to: AXUIElement.self)
        let attributes = AccessibilityMessaging.attributes(element, keys: [kAXRoleAttribute, kAXSubroleAttribute,
            kAXEnabledAttribute, "AXProtectedContent", kAXIdentifierAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
            kAXPlaceholderValueAttribute, kAXHelpAttribute, kAXSelectedTextRangeAttribute])
        guard permitsInsertion(role: attributes[kAXRoleAttribute] as? String ?? "",
            subrole: attributes[kAXSubroleAttribute] as? String ?? "",
            enabled: attributes[kAXEnabledAttribute] as? Bool ?? true,
            protectedContent: attributes["AXProtectedContent"] as? Bool ?? false,
            identifier: [kAXIdentifierAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
                kAXPlaceholderValueAttribute, kAXHelpAttribute].compactMap { attributes[$0] as? String }.joined(separator: " "),
            secureInputEnabled: SecureInputMonitor.isEnabled()) else { return "input_unavailable" }
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
              settable.boolValue,
              let value = attributes[kAXSelectedTextRangeAttribute],
              CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID() else { return "input_unavailable" }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(unsafeBitCast(value as CFTypeRef, to: AXValue.self), .cfRange, &range),
              range.length == 0 else { return "input_unavailable" }
        // Validate focus again after IPC; do not write through a stale element.
        var current: CFTypeRef?
        guard !SecureInputMonitor.isEnabled(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == processID,
              AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &current) == .success,
              let current, CFEqual(current, element) else { return "target_changed" }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
            ? nil : "input_unavailable"
    }

    static func permitsInsertion(role: String, subrole: String, enabled: Bool,
                                 protectedContent: Bool, identifier: String, secureInputEnabled: Bool = false) -> Bool {
        !secureInputEnabled && enabled && !protectedContent && subrole != kAXSecureTextFieldSubrole &&
            [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) &&
            !["password", "passcode", "token", "secret", "apikey", "api_key", "api key",
              "credit card", "密码", "口令", "密钥", "令牌", "信用卡", "银行卡", "借记卡"].contains(where: identifier.lowercased().contains)
    }
}
