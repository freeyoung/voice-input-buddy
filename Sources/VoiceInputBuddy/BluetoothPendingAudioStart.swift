import Foundation

/// Owns an audio-configuration pre-roll for one device. Rejecting a different
/// device must not discard the original device's pending start.
final class BluetoothPendingAudioStart {
    var identifier: UUID?
    var audio = CommandVoiceActivationAudioBuffer(maximumSampleCount: 32_000)

    @discardableResult
    func cancel(ifOwnedBy identifier: UUID) -> Bool {
        guard self.identifier == identifier else { return false }
        self.identifier = nil
        audio.cancel()
        return true
    }
}
