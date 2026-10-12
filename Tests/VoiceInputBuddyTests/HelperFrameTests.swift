import AppleRemoteAudioCore
import Foundation
import Network
import Testing
@testable import VoiceInputBuddy

@Suite("Bounded local helper protocol")
struct HelperFrameTests {
    @Test func zeroAndOversizedFramesAreRejectedWithoutRetainingBytes() {
        for bytes in [[UInt8](repeating: 0, count: 4), [0, 16, 0, 1], [255, 255, 255, 255]] {
            var buffer = Data(bytes)
            #expect(throws: AppleRemoteAudioIPC.FrameError.invalidLength) {
                try AppleRemoteAudioIPC.decodeFrames(buffer: &buffer)
            }
            #expect(buffer.isEmpty)
        }
    }
    @Test func fragmentedAndCoalescedFramesDecode() throws {
        let first = AppleRemoteAudioIPC.Frame(kind: .hello, payload: Data("token".utf8))
        let encoded = AppleRemoteAudioIPC.encode(first)
        var buffer = Data(encoded.prefix(5))
        #expect(try AppleRemoteAudioIPC.decodeFrames(buffer: &buffer).isEmpty)
        buffer.append(encoded.dropFirst(5))
        buffer.append(AppleRemoteAudioIPC.encode(.init(kind: .stop)))
        #expect(try AppleRemoteAudioIPC.decodeFrames(buffer: &buffer) == [first, .init(kind: .stop)])
        #expect(buffer.isEmpty)
    }
    @Test func commandLimitAndUnknownKindsAreRejected() {
        var buffer = AppleRemoteAudioIPC.encode(.init(kind: .hello, payload: Data(repeating: 0, count: 4096)))
        #expect(throws: AppleRemoteAudioIPC.FrameError.invalidLength) {
            try AppleRemoteAudioIPC.decodeFrames(buffer: &buffer, maximumLength: 4096)
        }
        buffer = Data([0, 0, 0, 1, 99])
        #expect(throws: AppleRemoteAudioIPC.FrameError.unknownKind) {
            try AppleRemoteAudioIPC.decodeFrames(buffer: &buffer)
        }
        #expect(buffer.isEmpty)
    }
    @Test func helperReadyMessageRequiresConcreteValidPort() {
        for line in ["READY 0", "READY 65536", "READY -1", "READY invalid",
                     "READY", "READY 1234 extra", "OTHER 1234"] {
            #expect(AppleRemoteAudioClient.helperReadyPort(from: line) == nil)
        }
        for value in [1, 12345, 65535] {
            #expect(AppleRemoteAudioClient.helperReadyPort(from: "READY \(value)")?.rawValue == UInt16(value))
        }
    }
    @Test func listenerBindsOnlyIPv4Loopback() {
        let parameters = AppleRemoteAudioListenerPolicy.parameters(port: 12345)
        #expect(parameters.requiredInterfaceType == .loopback)
        #expect(parameters.requiredLocalEndpoint == .hostPort(host: "127.0.0.1", port: 12345))
    }
}
