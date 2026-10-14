import CoreGraphics
import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Ordered voice input activation")
@MainActor
struct VoiceInputActivationTests {
    private func model() throws -> BridgeAppModel {
        let suite = "voice-activation-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let settings = AppSettings(defaults: defaults)
        settings.setOnboardingVoiceTool(.weixin)
        settings.voiceKeyMode = .function
        return BridgeAppModel(settings: settings, initialAudioDevices: [])
    }

    @Test func firstFnWaitsForSourceActivationAndRemoteStopRestoresWithoutGlobalUp() throws {
        let model = try model()
        let target = try #require(OnboardingVoiceTool.weixin.preferredInputSourceID)
        var source = "previous"
        var events: [String] = []
        model.preferredInputSourceMonitor = PreferredInputSourceMonitor(
            voiceTool: { .weixin }, prepareInputSource: { _ in events.append("select"); return .selected },
            currentInputSourceID: { source },
            restoreInputSource: { source = $0; events.append("restore"); return .selected },
            waitForInputSourceActivation: { requested, current, continuing in
                #expect(current() == "previous")
                source = requested
                events.append("activated")
                return continuing()
            }, installMonitor: { _ in nil }, logger: { _ in })
        for _ in 0..<2 {
            let started = model.updateVoiceKeyState(streaming: true, forceSoftware: true, owner: .bluetooth,
                keySetter: { mode, down in
                    #expect(mode == .function)
                    #expect(source == target)
                    events.append(down ? "fn_down" : "fn_up")
                    return true
                })
            #expect(started)
            let stopped = model.updateVoiceKeyState(streaming: false, forceSoftware: true, owner: .bluetooth,
                keySetter: { _, _ in events.append("fn_up"); return true })
            #expect(stopped)
            #expect(source == "previous")
            #expect(!model.voiceKeyLatch.isHeld)
            #expect(!model.preferredInputSourceMonitor.functionKeyIsPressedForDiagnostics)
        }
        #expect(events == ["select", "activated", "fn_down", "fn_up", "restore",
                           "select", "activated", "fn_down", "fn_up", "restore"])
    }

    @Test func cancelledActivationCannotSendFnDownOrBlockTheNextSession() throws {
        let model = try model()
        var source = "previous"
        var cancel = true
        var posted: [Bool] = []
        model.preferredInputSourceMonitor = PreferredInputSourceMonitor(
            voiceTool: { .weixin }, prepareInputSource: { _ in .selected },
            currentInputSourceID: { source }, restoreInputSource: { source = $0; return .selected },
            waitForInputSourceActivation: { target, _, continuing in
                source = target
                if cancel {
                    let stopped = model.updateVoiceKeyState(streaming: false, forceSoftware: true, owner: .bluetooth,
                        keySetter: { _, down in posted.append(down); return true })
                    #expect(stopped)
                    let overlap = model.updateVoiceKeyState(streaming: true, forceSoftware: true, owner: .bluetooth,
                        keySetter: { _, down in posted.append(down); return true })
                    #expect(!overlap)
                }
                return continuing()
            }, installMonitor: { _ in nil }, logger: { _ in })
        let cancelled = model.updateVoiceKeyState(streaming: true, forceSoftware: true, owner: .bluetooth,
            keySetter: { _, down in posted.append(down); return true })
        #expect(!cancelled)
        #expect(posted.isEmpty)
        #expect(model.pendingVoiceKeyMode == nil)
        #expect(!model.voiceKeyLatch.isHeld)
        #expect(source == "previous")
        cancel = false
        let restarted = model.updateVoiceKeyState(streaming: true, forceSoftware: true, owner: .bluetooth,
            keySetter: { _, down in posted.append(down); return true })
        #expect(restarted)
        #expect(posted == [true])
        let cleaned = model.releaseVoiceKeyIfNeeded(releaseKey: { _ in posted.append(false); return true })
        #expect(cleaned)
        #expect(posted == [true, false])
        #expect(source == "previous")
    }

    @Test func activationTimeoutRollsBackBeforePostingAnyKey() throws {
        let model = try model()
        var source = "previous"
        var posts = 0
        model.preferredInputSourceMonitor = PreferredInputSourceMonitor(
            voiceTool: { .weixin }, prepareInputSource: { _ in .selected },
            currentInputSourceID: { source }, restoreInputSource: { source = $0; return .selected },
            waitForInputSourceActivation: { _, _, _ in false }, installMonitor: { _ in nil }, logger: { _ in })
        let started = model.updateVoiceKeyState(streaming: true, forceSoftware: true, owner: .bluetooth,
            keySetter: { _, _ in posts += 1; return true })
        #expect(!started)
        #expect(posts == 0)
        #expect(!model.voiceKeyLatch.isHeld)
        #expect(model.pendingVoiceKeyMode == nil)
        #expect(!model.pendingCommandVoiceAudio.isWaiting)
    }

    @Test func failedFnUpKeepsSourceUntilAConfirmedCleanupSubmission() throws {
        let model = try model()
        var source = "previous"
        model.preferredInputSourceMonitor = PreferredInputSourceMonitor(
            voiceTool: { .weixin }, prepareInputSource: { tool in source = tool.preferredInputSourceID!; return .selected },
            currentInputSourceID: { source }, restoreInputSource: { source = $0; return .selected },
            waitForInputSourceActivation: { _, _, continuing in continuing() }, installMonitor: { _ in nil }, logger: { _ in })
        let started = model.updateVoiceKeyState(streaming: true, forceSoftware: true, owner: .bluetooth,
            keySetter: { _, _ in true })
        #expect(started)
        let stopped = model.updateVoiceKeyState(streaming: false, forceSoftware: true, owner: .bluetooth,
            keySetter: { _, _ in false })
        #expect(!stopped)
        #expect(model.voiceKeyLatch.isHeld)
        #expect(source == OnboardingVoiceTool.weixin.preferredInputSourceID)
        let cleaned = model.releaseVoiceKeyIfNeeded(releaseKey: { _ in true })
        #expect(cleaned)
        #expect(source == "previous")
    }

    @Test func alreadySelectedSourceAndUserChangesArePreserved() throws {
        let target = try #require(OnboardingVoiceTool.weixin.preferredInputSourceID)
        var source = target
        var restored: [String] = []
        let monitor = PreferredInputSourceMonitor(voiceTool: { .weixin },
            prepareInputSource: { _ in source = target; return .selected }, currentInputSourceID: { source },
            restoreInputSource: { restored.append($0); source = $0; return .selected },
            waitForInputSourceActivation: { _, _, continuing in continuing() }, installMonitor: { _ in nil }, logger: { _ in })
        #expect(monitor.beginVoiceSession())
        monitor.endVoiceSession()
        #expect(restored.isEmpty)
        source = "previous"
        #expect(monitor.beginVoiceSession())
        source = "user_selected"
        monitor.endVoiceSession()
        #expect(restored.isEmpty)
        #expect(source == "user_selected")
    }

    @Test func ordinaryKeyboardFnStillSelectsAndRestoresItsInputSource() throws {
        var source = "previous"
        let target = try #require(OnboardingVoiceTool.weixin.preferredInputSourceID)
        let monitor = PreferredInputSourceMonitor(voiceTool: { .weixin },
            prepareInputSource: { _ in source = target; return .selected }, currentInputSourceID: { source },
            restoreInputSource: { source = $0; return .selected }, installMonitor: { _ in nil }, logger: { _ in })
        monitor.handleFunctionKeyPressed(true)
        #expect(source == target)
        #expect(monitor.functionKeyIsPressedForDiagnostics)
        monitor.handleFunctionKeyPressed(false)
        #expect(source == "previous")
    }

    @Test func orderedEventsCannotAcquireAnExtraGlobalFnOwnerAndRemainSynthetic() throws {
        #expect(!PreferredInputSourceMonitor.shouldObserveFunctionEvent(marker: KeyboardInjector.orderedVoiceEventMarker))
        #expect(PreferredInputSourceMonitor.shouldObserveFunctionEvent(marker: 0))
        // Fn tap sessions retain their existing, separately managed behavior.
        #expect(PreferredInputSourceMonitor.shouldObserveFunctionEvent(marker: KeyboardInjector.syntheticEventMarker))
        let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 63, keyDown: true))
        event.setIntegerValueField(.eventSourceUserData, value: KeyboardInjector.orderedVoiceEventMarker)
        #expect(KeyboardInjector.isSyntheticEvent(event))
        let ordinarySource = try #require(CGEventSource(stateID: .privateState))
        let ordinaryEvent = try #require(CGEvent(keyboardEventSource: ordinarySource, virtualKey: 63, keyDown: true))
        #expect(!KeyboardInjector.isSyntheticEvent(ordinaryEvent))
    }

    @Test func failedSourceSelectionOrFnDownNeverLeavesTheSourceOwned() throws {
        for selection in [OnboardingInputSourceSwitchResult.failed, .selected] {
            let model = try model()
            var source = "previous"
            var posts = 0
            model.preferredInputSourceMonitor = PreferredInputSourceMonitor(
                voiceTool: { .weixin }, prepareInputSource: { tool in
                    if selection == .selected { source = tool.preferredInputSourceID! }
                    return selection
                }, currentInputSourceID: { source }, restoreInputSource: { source = $0; return .selected },
                waitForInputSourceActivation: { _, _, continuing in continuing() },
                installMonitor: { _ in nil }, logger: { _ in })
            let started = model.updateVoiceKeyState(streaming: true, forceSoftware: true, owner: .bluetooth,
                keySetter: { _, _ in posts += 1; return false })
            #expect(!started)
            #expect(posts == (selection == .selected ? 1 : 0))
            #expect(source == "previous")
            #expect(!model.voiceKeyLatch.isHeld)
            #expect(model.pendingVoiceKeyMode == nil)
        }
    }

    @Test func orderedHardwareFnRequiresNeutralizationAndPostingPermission() {
        #expect(OrderedVoiceActivationPolicy.needsSoftwareFn(mode: .function, fnTapEnabled: false,
            preferredInputSourceID: "weixin"))
        #expect(!OrderedVoiceActivationPolicy.needsSoftwareFn(mode: .function, fnTapEnabled: true,
            preferredInputSourceID: "weixin"))
        #expect(!OrderedVoiceActivationPolicy.needsSoftwareFn(mode: .function, fnTapEnabled: false,
            preferredInputSourceID: nil))
        #expect(!BridgeAppModel.canStartBluetoothVoice(mode: .function, isVoiceKeyNeutralized: false,
            accessibilityGranted: true, requiresOrderedFn: true))
        #expect(!BridgeAppModel.canStartBluetoothVoice(mode: .function, isVoiceKeyNeutralized: true,
            accessibilityGranted: false, requiresOrderedFn: true))
        #expect(BridgeAppModel.canStartBluetoothVoice(mode: .function, isVoiceKeyNeutralized: true,
            accessibilityGranted: true, requiresOrderedFn: true))
        #expect(BridgeAppModel.canStartBluetoothVoice(mode: .function, isVoiceKeyNeutralized: false))
        #expect(VoiceKeySessionPreservationPolicy.shouldPreserveInputSourceSession(latchHeld: true,
            heldMode: .function, pendingMode: nil))
    }

    @Test func anotherVoiceOwnerDoesNotRestoreTheSourceUntilTheLastFnUp() throws {
        let model = try model()
        var source = "previous"
        var posts: [Bool] = []
        model.preferredInputSourceMonitor = PreferredInputSourceMonitor(
            voiceTool: { .weixin }, prepareInputSource: { tool in source = tool.preferredInputSourceID!; return .selected },
            currentInputSourceID: { source }, restoreInputSource: { source = $0; return .selected },
            waitForInputSourceActivation: { _, _, continuing in continuing() }, installMonitor: { _ in nil }, logger: { _ in })
        let setter: (VoiceKeyMode, Bool) -> Bool = { _, down in posts.append(down); return true }
        let first = model.updateVoiceKeyState(streaming: true, forceSoftware: true, owner: .bluetooth, keySetter: setter)
        let second = model.updateVoiceKeyState(streaming: true, forceSoftware: true, owner: .mobile, keySetter: setter)
        #expect(first && second)
        let firstStop = model.updateVoiceKeyState(streaming: false, forceSoftware: true, owner: .bluetooth, keySetter: setter)
        #expect(firstStop)
        #expect(source == OnboardingVoiceTool.weixin.preferredInputSourceID)
        #expect(posts == [true])
        let secondStop = model.updateVoiceKeyState(streaming: false, forceSoftware: true, owner: .mobile, keySetter: setter)
        #expect(secondStop)
        #expect(source == "previous")
        #expect(posts == [true, false])
    }
}
