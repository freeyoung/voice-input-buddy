import AppKit
import AVFoundation
import Combine
import CoreAudio
import CoreBluetooth
import Foundation

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

    private var storage = [Int16](repeating: 0, count: Self.maximumSampleCount)
    private var writeIndex = 0
    private var count = 0
    private var lastAudioUptime: TimeInterval?

    private var recentSamples: [Int16] {
        let start = (writeIndex + Self.maximumSampleCount - count) % Self.maximumSampleCount
        return (0..<count).map { storage[(start + $0) % Self.maximumSampleCount] }
    }

    mutating func reset() {
        writeIndex = 0
        count = 0
        lastAudioUptime = nil
    }

    mutating func append(_ samples: [Int16], at uptime: TimeInterval) {
        guard !samples.isEmpty else { return }
        lastAudioUptime = uptime
        for sample in samples.suffix(Self.maximumSampleCount) {
            storage[writeIndex] = sample
            writeIndex = (writeIndex + 1) % Self.maximumSampleCount
            count = min(Self.maximumSampleCount, count + 1)
        }
    }

    func snapshot(at stopUptime: TimeInterval) -> BluetoothVoiceTailSnapshot {
        let samples = recentSamples
        var metrics = VoiceAudioSignalMetrics()
        metrics.append(samples)
        let finalWindowSamples = Array(samples.suffix(Self.sampleRate / 10))
        var finalWindowMetrics = VoiceAudioSignalMetrics()
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

struct VoiceAudioSignalMetrics: Equatable, Sendable {
    private(set) var sampleCount = 0
    private(set) var nonZeroSampleCount = 0
    private(set) var peak = 0
    private(set) var squaredSampleSum: UInt64 = 0

    init() {}

    var rms: Int {
        guard sampleCount > 0 else { return 0 }
        return Int(sqrt(Double(squaredSampleSum) / Double(sampleCount)))
    }

    mutating func append(_ samples: [Int16]) {
        for sample in samples {
            let magnitude = abs(Int(sample))
            sampleCount += 1
            if sample != 0 { nonZeroSampleCount += 1 }
            peak = max(peak, magnitude)
            squaredSampleSum += UInt64(magnitude * magnitude)
        }
    }
}
