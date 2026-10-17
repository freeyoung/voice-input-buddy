import Foundation
import Testing
@testable import VoiceInputBuddy

private final class AudioDeliveries: @unchecked Sendable {
    private let lock = NSLock()
    private var actions: [@MainActor @Sendable () -> Void] = []
    func enqueue(_ action: @escaping @MainActor @Sendable () -> Void) { lock.withLock { actions.append(action) } }
    @MainActor func run() {
        let pending = lock.withLock { let result = actions; actions.removeAll(); return result }
        pending.forEach { $0() }
    }
}

@Suite("Background Bluetooth audio ordering") @MainActor
struct BluetoothAudioPipelineTests {
    @Test func normalStopDrainsPriorFramesBeforeNextStart() {
        let queue = DispatchQueue(label: "test.audio.order")
        let deliveries = AudioDeliveries()
        let pipeline = BluetoothAudioPipeline(queue: queue, deliver: deliveries.enqueue)
        var events: [String] = []
        var audio: [[Int16]] = []
        let bytes = Data(repeating: 0x37, count: 120)
        for _ in 0..<2 {
            #expect(pipeline.beginStream { events.append("start") })
            #expect(!pipeline.beginStream { Issue.record("Duplicate start") })
            #expect(pipeline.append(bytes, frameSize: 120, gainDB: 0) { samples in
                events.append("audio"); audio.append(samples)
            })
            pipeline.endStream { events.append("stop") }
        }
        queue.sync {} // only worker computation completes; main delivery remains queued
        #expect(events.isEmpty)
        deliveries.run()
        #expect(events == ["start", "audio", "stop", "start", "audio", "stop"])
        let reference = ATVVAudioDecoder().append(bytes, frameSize: 120, gainDB: 0)
        #expect(audio == reference + reference)
    }

    @Test func connectionResetRejectsAlreadyComputedOldResultsAndResetsFormat() {
        let queue = DispatchQueue(label: "test.audio.cancel")
        let deliveries = AudioDeliveries()
        let pipeline = BluetoothAudioPipeline(queue: queue, deliver: deliveries.enqueue)
        let bytes = Data([0x12, 0x34, 0x56])
        pipeline.configureFormat(lowNibbleFirst: true)
        #expect(pipeline.beginStream { Issue.record("Old start delivered") })
        #expect(pipeline.append(bytes, frameSize: 3, gainDB: 0) { _ in Issue.record("Old audio delivered") })
        queue.sync {}
        pipeline.reset(peripheral: true)
        var results: [[Int16]] = []
        #expect(pipeline.beginStream {})
        #expect(pipeline.append(bytes, frameSize: 3, gainDB: 0) { results.append($0) })
        queue.sync {}
        deliveries.run()
        #expect(results == ATVVAudioDecoder().append(bytes, frameSize: 3, gainDB: 0))
    }

    @Test func backlogIncludesResultsAwaitingMainDeliveryAndResetReclaimsBudget() {
        let queue = DispatchQueue(label: "test.audio.bound")
        let deliveries = AudioDeliveries()
        let pipeline = BluetoothAudioPipeline(queue: queue, maximumPendingBytes: 120, deliver: deliveries.enqueue)
        let bytes = Data(repeating: 0x11, count: 120)
        #expect(pipeline.beginStream {})
        #expect(pipeline.append(bytes, frameSize: 120, gainDB: 0) { _ in })
        queue.sync {}
        #expect(!pipeline.append(bytes, frameSize: 120, gainDB: 0) { _ in })
        deliveries.run()
        #expect(pipeline.append(bytes, frameSize: 120, gainDB: 0) { _ in })
        pipeline.reset()
        #expect(pipeline.beginStream {})
        #expect(pipeline.append(bytes, frameSize: 120, gainDB: 0) { _ in })
        queue.sync {}
        deliveries.run()
    }
}
