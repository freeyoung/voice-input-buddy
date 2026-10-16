import CoreAudio
import Foundation

/// Owns audio resources and asynchronous recovery lifetimes. State is main-queue
/// confined; engine work and HAL notifications keep their dedicated queues.
final class AudioRuntime {
    typealias AudioHardwareListenerRemover = (
        inout AudioObjectPropertyAddress, DispatchQueue, @escaping AudioObjectPropertyListenerBlock
    ) -> OSStatus
    let output = VirtualAudioOutput()
    let preparationQueue = DispatchQueue(label: "VoiceInputBuddy.audioPreparation", qos: .userInitiated)
    var configurationGeneration: UInt64 = 0
    var startupGeneration: UInt64 = 0
    var deviceRefreshGeneration: UInt64 = 0
    var startupPending = false
    var hardwareListenerRemover: AudioHardwareListenerRemover = { address, queue, listener in
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
    }
    let hardwareListenerQueue = DispatchQueue(label: "VoiceInputBuddy.audioHardware")
    var observedHardwareAddresses: [AudioObjectPropertyAddress] = []
    var recoveryWorkItem: DispatchWorkItem?
    var recoveryGeneration: UInt64 = 0
    var recoveryCoalescingState = AudioRecoveryCoalescingState()
    var virtualAudioReleaseGeneration: UInt64 = 0
    var pendingVirtualAudioRelease: (generation: UInt64, reason: String)?
    var suspensionState = SystemAudioSuspensionState()

    private var registeredListener: AudioObjectPropertyListenerBlock?

    func retainHardwareListener(_ listener: @escaping AudioObjectPropertyListenerBlock) {
        registeredListener = listener
    }

    func stopObservingHardware() {
        guard let listener = registeredListener else { return }
        for var address in observedHardwareAddresses {
            _ = hardwareListenerRemover(&address, hardwareListenerQueue, listener)
        }
        observedHardwareAddresses.removeAll()
        registeredListener = nil
    }

    func invalidatePendingWork() {
        startupGeneration &+= 1
        deviceRefreshGeneration &+= 1
        configurationGeneration &+= 1
        startupPending = false
        recoveryGeneration &+= 1
        recoveryWorkItem?.cancel()
        recoveryWorkItem = nil
        recoveryCoalescingState.reset()
        virtualAudioReleaseGeneration &+= 1
        pendingVirtualAudioRelease = nil
    }

    deinit {
        invalidatePendingWork()
        stopObservingHardware()
    }
}
