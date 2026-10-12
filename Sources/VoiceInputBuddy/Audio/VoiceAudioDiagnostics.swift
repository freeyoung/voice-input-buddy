import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation
import BuddyRemoteCore

struct CommandVoiceActivationAudioBuffer {
    let maximumSampleCount: Int
    var samples: [Int16] = []
    private(set) var isWaiting = false

    init(maximumSampleCount: Int = 8_000) {
        self.maximumSampleCount = maximumSampleCount
    }

    var bufferedSampleCount: Int {
        samples.count
    }

    mutating func begin() {
        samples.removeAll(keepingCapacity: true)
        isWaiting = true
    }

    mutating func appendIfWaiting(_ newSamples: [Int16]) -> Bool {
        guard isWaiting else { return false }
        samples.append(contentsOf: newSamples)
        if samples.count > maximumSampleCount {
            samples.removeFirst(samples.count - maximumSampleCount)
        }
        return true
    }

    mutating func drain() -> [Int16] {
        guard isWaiting else { return [] }
        isWaiting = false
        defer { samples.removeAll(keepingCapacity: true) }
        return samples
    }

    mutating func cancel() {
        isWaiting = false
        samples.removeAll(keepingCapacity: true)
    }
}

enum VoiceSamplePresentationPolicy {
    static func shouldPublishReceipt(
        hasReceivedSamples: Bool,
        sampleCount: Int
    ) -> Bool {
        sampleCount > 0 && !hasReceivedSamples
    }
}

struct AudioRecoveryCoalescingState {
    private(set) var pendingEventCount = 0
    private(set) var includesHardwareChange = false

    mutating func recordEvent(reason: String) {
        pendingEventCount += 1
        if reason == "hardware_change" {
            includesHardwareChange = true
        }
    }

    mutating func consumePendingEvents() -> (count: Int, includesHardwareChange: Bool) {
        let result = (pendingEventCount, includesHardwareChange)
        pendingEventCount = 0
        includesHardwareChange = false
        return result
    }

    mutating func reset() {
        pendingEventCount = 0
        includesHardwareChange = false
    }
}

struct BluetoothVoiceTailSnapshot: Equatable {
    let sampleCount: Int
    let durationMilliseconds: Int
    let nonZeroSampleCount: Int
    let peak: Int
    let rms: Int
    let finalWindowSampleCount: Int
    let finalWindowDurationMilliseconds: Int
    let finalWindowNonZeroSampleCount: Int
    let finalWindowPeak: Int
    let finalWindowRMS: Int
    let lastAudioAgeMilliseconds: Int?
}

struct BluetoothVoiceTailDiagnostics {
    static let sampleRate = 16_000
    static let maximumSampleCount = 4_800

    private var recentSamples: [Int16] = []
    private var lastAudioUptime: TimeInterval?

    mutating func reset() {
        recentSamples.removeAll(keepingCapacity: true)
        lastAudioUptime = nil
    }

    mutating func append(_ samples: [Int16], at uptime: TimeInterval) {
        guard !samples.isEmpty else { return }
        lastAudioUptime = uptime
        if samples.count >= Self.maximumSampleCount {
            recentSamples = Array(samples.suffix(Self.maximumSampleCount))
            return
        }
        let overflow = max(0, recentSamples.count + samples.count - Self.maximumSampleCount)
        if overflow > 0 {
            recentSamples.removeFirst(overflow)
        }
        recentSamples.append(contentsOf: samples)
    }

    func snapshot(at stopUptime: TimeInterval) -> BluetoothVoiceTailSnapshot {
        var metrics = WatchBluetoothAudioSignalMetrics()
        metrics.append(recentSamples)
        let finalWindowSamples = Array(recentSamples.suffix(Self.sampleRate / 10))
        var finalWindowMetrics = WatchBluetoothAudioSignalMetrics()
        finalWindowMetrics.append(finalWindowSamples)
        return BluetoothVoiceTailSnapshot(
            sampleCount: metrics.sampleCount,
            durationMilliseconds: metrics.sampleCount * 1_000 / Self.sampleRate,
            nonZeroSampleCount: metrics.nonZeroSampleCount,
            peak: metrics.peak,
            rms: metrics.rms,
            finalWindowSampleCount: finalWindowMetrics.sampleCount,
            finalWindowDurationMilliseconds:
                finalWindowMetrics.sampleCount * 1_000 / Self.sampleRate,
            finalWindowNonZeroSampleCount: finalWindowMetrics.nonZeroSampleCount,
            finalWindowPeak: finalWindowMetrics.peak,
            finalWindowRMS: finalWindowMetrics.rms,
            lastAudioAgeMilliseconds: lastAudioUptime.map {
                max(0, Int(((stopUptime - $0) * 1_000).rounded()))
            }
        )
    }
}
