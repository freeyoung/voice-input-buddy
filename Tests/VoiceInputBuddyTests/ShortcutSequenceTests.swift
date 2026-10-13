import AppKit
import Testing
@testable import VoiceInputBuddy

@Suite("Shortcut modifier ownership")
struct ShortcutSequenceTests {
    private struct Posted {
        let code: UInt16
        let type: CGEventType
        let flags: CGEventFlags
        let marker: Int64
        init(_ event: CGEvent) {
            code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            type = event.type
            flags = event.flags
            marker = event.getIntegerValueField(.eventSourceUserData)
        }
    }

    @Test func plainKeyUsesMarkedDownAndUpWithoutModifiers() {
        var posted: [Posted] = []
        #expect(ShortcutEventSequence.send(keyCode: 0, modifiers: [], hardwareFlags: { [] },
            eventPoster: { posted.append(Posted($0)); return true }, logger: { _ in }))
        #expect(posted.map(\.code) == [0, 0])
        #expect(posted.map(\.type) == [.keyDown, .keyUp])
        #expect(posted.allSatisfy { $0.flags.isEmpty && $0.marker == KeyboardInjector.syntheticEventMarker })
    }

    @Test func combinationReleasesOwnedModifiersInReverseOrder() {
        var posted: [Posted] = []
        #expect(ShortcutEventSequence.send(keyCode: 8, modifiers: [.maskCommand, .maskShift],
            hardwareFlags: { [] }, eventPoster: { posted.append(Posted($0)); return true }, logger: { _ in }))
        #expect(posted.map(\.code) == [56, 55, 8, 8, 55, 56])
        #expect(posted.map(\.type) == [.flagsChanged, .flagsChanged, .keyDown, .keyUp, .flagsChanged, .flagsChanged])
        #expect(posted[2].flags.contains([.maskCommand, .maskShift]))
        #expect(!posted[4].flags.contains(.maskCommand) && posted[4].flags.contains(.maskShift))
        #expect(posted[5].flags.isEmpty)
        #expect(posted.allSatisfy { $0.marker == KeyboardInjector.syntheticEventMarker })
    }

    @Test func physicallyHeldCommandIsNeverReleasedBySyntheticShortcut() {
        var posted: [Posted] = []
        #expect(ShortcutEventSequence.send(keyCode: 8, modifiers: .maskCommand,
            hardwareFlags: { .maskCommand }, eventPoster: { posted.append(Posted($0)); return true }, logger: { _ in }))
        #expect(posted.map(\.code) == [8, 8])
        #expect(posted.allSatisfy { $0.flags.contains(.maskCommand) })
    }

    @Test func rightCommandRequestPreservesPhysicallyHeldLeftCommand() {
        var posted: [Posted] = []
        let left = CGEventFlags(rawValue: 0x0008)
        let right = CGEventFlags(rawValue: 0x0010)
        #expect(ShortcutEventSequence.send(keyCode: 8, modifiers: [.maskCommand, right],
            hardwareFlags: { [.maskCommand, left] },
            eventPoster: { posted.append(Posted($0)); return true }, logger: { _ in }))
        #expect(posted.map(\.code) == [54, 8, 8, 54])
        #expect(posted[0].flags.contains([.maskCommand, left, right]))
        #expect(posted[3].flags.contains([.maskCommand, left]))
        #expect(!posted[3].flags.contains(right))
    }

    @Test func failedKeyDownStillAttemptsKeyUpAndModifierCleanup() {
        var posted: [Posted] = []
        #expect(!ShortcutEventSequence.send(keyCode: 8, modifiers: .maskCommand,
            hardwareFlags: { [] }, eventPoster: { event in
                posted.append(Posted(event))
                return !(event.type == .keyDown && event.getIntegerValueField(.keyboardEventKeycode) == 8)
            }, logger: { _ in }))
        #expect(posted.map(\.code) == [55, 8, 8, 55])
        #expect(posted[2].type == .keyUp)
        #expect(posted.last?.flags.isEmpty == true)
    }

    @Test func failedModifierPressSkipsMainKeyButAttemptsRelease() {
        var posted: [Posted] = []
        #expect(!ShortcutEventSequence.send(keyCode: 8, modifiers: .maskCommand,
            hardwareFlags: { [] }, eventPoster: { event in
                posted.append(Posted(event))
                return !event.flags.contains(.maskCommand)
            }, logger: { _ in }))
        #expect(posted.map(\.code) == [55, 55])
        #expect(posted.last?.flags.isEmpty == true)
    }

    @Test func physicalModifierPressedMidTransactionSurvivesCleanup() {
        var physical: CGEventFlags = []
        var posted: [Posted] = []
        #expect(ShortcutEventSequence.send(keyCode: 8, modifiers: .maskCommand,
            hardwareFlags: { physical }, eventPoster: { event in
                posted.append(Posted(event))
                if event.type == .keyDown { physical = [.maskShift, CGEventFlags(rawValue: 0x0002)] }
                return true
            }, logger: { _ in }))
        #expect(posted.map(\.code) == [55, 8, 8, 55])
        #expect(posted.last?.flags.contains(.maskShift) == true)
        #expect(posted.last?.flags.contains(.maskCommand) == false)
    }
    @Test(arguments: [CGEventFlags.maskControl, .maskAlternate, .maskShift, .maskCommand, .maskSecondaryFn])
    func everyModifierFamilyIsPressedAndReleased(flag: CGEventFlags) {
        let keys: [CGEventFlags.RawValue: UInt16] = [CGEventFlags.maskControl.rawValue: 59,
            CGEventFlags.maskAlternate.rawValue: 58, CGEventFlags.maskShift.rawValue: 56,
            CGEventFlags.maskCommand.rawValue: 55, CGEventFlags.maskSecondaryFn.rawValue: 63]
        var posted: [Posted] = []
        #expect(ShortcutEventSequence.send(keyCode: 8, modifiers: flag, hardwareFlags: { [] },
            eventPoster: { posted.append(Posted($0)); return true }, logger: { _ in }))
        #expect(posted.count == 4)
        #expect(posted.first?.code == keys[flag.rawValue])
        #expect(posted.first?.type == .flagsChanged)
        #expect(posted[1].type == .keyDown && posted[2].type == .keyUp)
        #expect(posted[1].flags.contains(flag))
        #expect(posted.last?.code == keys[flag.rawValue])
        #expect(posted.last?.flags.isEmpty == true)
    }

    @Test func failedReleaseRetriesOnceButDoesNotReportSuccess() {
        var releases = 0
        var posted: [Posted] = []
        #expect(!ShortcutEventSequence.send(keyCode: 8, modifiers: .maskCommand,
            hardwareFlags: { [] }, eventPoster: { event in
                posted.append(Posted(event))
                if event.type == .keyUp {
                    releases += 1
                    return releases > 1
                }
                return true
            }, logger: { _ in }))
        #expect(releases == 2)
        #expect(posted.map(\.code) == [55, 8, 8, 8, 55])
        #expect(posted.last?.flags.isEmpty == true)
    }

    @Test func repeatedReleaseFailureHasFiniteCleanupAndDiagnostic() {
        var posted: [Posted] = []
        var logs: [String] = []
        #expect(!ShortcutEventSequence.send(keyCode: 8, modifiers: .maskCommand,
            hardwareFlags: { [] }, eventPoster: { event in
                posted.append(Posted(event))
                return event.type != .keyUp && !event.flags.isEmpty
            }, logger: { logs.append($0) }))
        #expect(posted.map(\.code) == [55, 8, 8, 8, 55, 55])
        #expect(logs.last?.contains("cleanup_failed=true") == true)
    }

}
