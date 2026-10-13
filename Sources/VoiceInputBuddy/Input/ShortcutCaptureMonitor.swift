import AppKit
import CoreGraphics
import Foundation

private func shortcutCaptureEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<ShortcutCaptureMonitor>
        .fromOpaque(userInfo)
        .takeUnretainedValue()
    return monitor.handle(type: type, event: event)
        ? nil
        : Unmanaged.passUnretained(event)
}

enum ShortcutCaptureStartFailure: Error, Equatable {
    case accessibilityPermissionRequired
    case eventTapUnavailable
}

final class ShortcutCaptureMonitor {
    typealias CallbackDispatcher = (@escaping () -> Void) -> Void
    static let captureEventMask = CGEventMask(1 << CGEventType.keyDown.rawValue) |
        CGEventMask(1 << CGEventType.flagsChanged.rawValue)

    private let onCapture: (CustomKeyboardShortcut) -> Void
    private let accessibilityTrusted: () -> Bool
    private let dispatchCallback: CallbackDispatcher
    private let modifierIsPressed: (UInt16) -> Bool
    private let lock = NSLock()
    private var captureGeneration: UInt64 = 0
    private var tapRecoveryGeneration = 0
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var didCapture = false
    private var pressedModifierKeyCodes: Set<UInt16> = []
    private var standaloneModifierCandidate: StandaloneKeyboardModifier?
    private var modifierChordDetected = false

    init(
        onCapture: @escaping (CustomKeyboardShortcut) -> Void,
        accessibilityTrusted: @escaping () -> Bool = { KeyboardInjector.isAccessibilityTrusted },
        modifierIsPressed: @escaping (UInt16) -> Bool = {
            CGEventSource.keyState(.hidSystemState, key: $0)
        },
        dispatchCallback: @escaping CallbackDispatcher = {
            DispatchQueue.main.async(execute: $0)
        }
    ) {
        self.onCapture = onCapture
        self.accessibilityTrusted = accessibilityTrusted
        self.dispatchCallback = dispatchCallback
        self.modifierIsPressed = modifierIsPressed
    }

    func start() -> Result<Void, ShortcutCaptureStartFailure> {
        if eventTap != nil { return .success(()) }
        guard accessibilityTrusted() else {
            return .failure(.accessibilityPermissionRequired)
        }

        resetCaptureState()

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: Self.captureEventMask,
            callback: shortcutCaptureEventTapCallback,
            userInfo: context
        ) else {
            return .failure(.eventTapUnavailable)
        }
        guard let runLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            eventTap,
            0
        ) else {
            // tapCreate 成功即已在 WindowServer 侧登记端口；此处失败若不释放端口，
            // 该 tap 会残留到进程退出，必须与 stop() 走同一条清理路径。
            EventTapPort.release(port: eventTap, source: nil)
            return .failure(.eventTapUnavailable)
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        EventTapPort.activate(port: eventTap, source: runLoopSource)
        return .success(())
    }

    func resetCaptureState() {
        lock.lock()
        captureGeneration &+= 1
        didCapture = false
        pressedModifierKeyCodes = Set(StandaloneKeyboardModifier.allCases.map(\.keyCode).filter(modifierIsPressed))
        standaloneModifierCandidate = nil
        modifierChordDetected = !pressedModifierKeyCodes.isEmpty
        lock.unlock()
    }

    func stop() {
        lock.lock()
        captureGeneration &+= 1
        lock.unlock()
        tapRecoveryGeneration += 1
        EventTapPort.release(port: eventTap, source: runLoopSource)
        runLoopSource = nil
        eventTap = nil
    }

    func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tapRecoveryGeneration += 1
            let generation = tapRecoveryGeneration
            if let port = eventTap {
                EventTapPort.deferRecovery(type: type,
                    dispatch: { DispatchQueue.main.async(execute: $0) },
                    isCurrent: { [weak self] in
                        self?.tapRecoveryGeneration == generation && self?.eventTap === port
                    },
                    permissionsGranted: { [weak self] in self?.accessibilityTrusted() == true },
                    enable: { CGEvent.tapEnable(tap: port, enable: true) },
                    stop: { [weak self] in
                        self?.stop()
                        AppLogger.shared.write("SHORTCUT CAPTURE stopped reason=system_disabled_or_permission_revoked")
                    })
            }
            return false
        }
        guard type == .keyDown || type == .flagsChanged else { return false }
        guard event.getIntegerValueField(.eventSourceUserData) != KeyboardInjector.syntheticEventMarker else {
            return false
        }

        if type == .flagsChanged {
            return handleModifierFlagsChanged(event)
        }

        lock.lock()
        if didCapture {
            lock.unlock()
            return true
        }
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            lock.unlock()
            return true
        }
        guard let nsEvent = NSEvent(cgEvent: event) else {
            lock.unlock()
            return false
        }
        didCapture = true
        let generation = captureGeneration
        pressedModifierKeyCodes.removeAll()
        standaloneModifierCandidate = nil
        modifierChordDetected = false
        lock.unlock()

        let shortcut = CustomKeyboardShortcut(event: nsEvent)
        dispatchCapture(shortcut, generation: generation)
        return true
    }

    private func handleModifierFlagsChanged(_ event: CGEvent) -> Bool {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard let modifier = StandaloneKeyboardModifier.allCases.first(where: {
            $0.keyCode == keyCode
        }) else {
            return false
        }

        lock.lock()
        if didCapture {
            lock.unlock()
            return true
        }

        if pressedModifierKeyCodes.contains(keyCode) {
            pressedModifierKeyCodes.remove(keyCode)
            let shouldCapture = pressedModifierKeyCodes.isEmpty &&
                !modifierChordDetected &&
                standaloneModifierCandidate == modifier
            if pressedModifierKeyCodes.isEmpty {
                standaloneModifierCandidate = nil
                modifierChordDetected = false
            }
            if shouldCapture {
                didCapture = true
            }
            let generation = captureGeneration
            lock.unlock()

            if shouldCapture {
                dispatchCapture(modifier.shortcut, generation: generation)
            }
            return true
        }

        pressedModifierKeyCodes.insert(keyCode)
        if pressedModifierKeyCodes.count == 1 && !modifierChordDetected {
            standaloneModifierCandidate = modifier
        } else {
            standaloneModifierCandidate = nil
            modifierChordDetected = true
        }
        lock.unlock()
        return true
    }

    private func dispatchCapture(_ shortcut: CustomKeyboardShortcut, generation: UInt64) {
        dispatchCallback { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let current = self.captureGeneration == generation
            self.lock.unlock()
            guard current else { return }
            self.onCapture(shortcut)
        }
    }

    deinit {
        stop()
    }
}
