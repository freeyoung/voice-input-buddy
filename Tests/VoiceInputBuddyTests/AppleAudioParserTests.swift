import Darwin
import Foundation
import Testing
import AppleRemoteAudioCore

@Suite("Apple audio parsers")
struct AppleAudioParserTests {
    private func word(_ value: UInt16) -> [UInt8] { [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)] }
    private func voicePDU(_ sequence: UInt16) -> [UInt8] {
        let opus: [UInt8] = [0xB8, 0]
        var wrapper = [UInt8](repeating: 0, count: 99)
        wrapper.replaceSubrange(2..<4, with: word(sequence))
        wrapper[4] = 2
        wrapper.replaceSubrange(5..<7, with: opus)
        return [0x1B, 0x33, 0] + wrapper
    }
    private func acl(_ payload: [UInt8], boundary: UInt16 = 2) -> Data {
        Data([0x03] + word(1 | (boundary << 12)) + word(UInt16(payload.count)) + payload)
    }
    private func packet(_ sequence: UInt16) -> Data {
        let pdu = voicePDU(sequence)
        return acl(word(UInt16(pdu.count)) + [4, 0] + pdu)
    }

    @Test func parserLocksOnlyConsecutiveFramesAndRejectsDuplicateSequence() {
        var parser = AppleRemoteXPCVoiceParser()
        #expect(parser.ingestXPCPacket(packet(1)).isEmpty)
        #expect(parser.ingestXPCPacket(packet(2)).isEmpty)
        #expect(parser.ingestXPCPacket(packet(3)) == [Data([0xB8, 0]), Data([0xB8, 0]), Data([0xB8, 0])])
        #expect(parser.ingestXPCPacket(packet(4)) == [Data([0xB8, 0])])
        #expect(parser.ingestXPCPacket(packet(4)).isEmpty)
        #expect(parser.statistics.opusPacketsEmitted == 4)
        parser.reset()
        #expect(parser.statistics == AppleRemoteXPCVoiceParserStatistics())
        #expect(parser.ingestXPCPacket(packet(5)).isEmpty)
    }

    @Test func fragmentedACLReassemblesATTAndMalformedLengthsDoNotPoisonNextStream() {
        var parser = AppleRemoteXPCVoiceParser()
        let pdu = voicePDU(1)
        #expect(parser.ingestXPCPacket(acl(word(UInt16(pdu.count)) + [4, 0] + Array(pdu.prefix(8)))).isEmpty)
        #expect(parser.ingestXPCPacket(acl(Array(pdu.dropFirst(8)), boundary: 1)).isEmpty)
        #expect(parser.statistics.validVoiceWrappers == 1)
        #expect(parser.ingestXPCPacket(packet(2)).isEmpty)
        #expect(parser.ingestXPCPacket(packet(3)).count == 3)
        parser.reset()
        let full = packet(1)
        for size in 0..<full.count { #expect(parser.ingestXPCPacket(Data(full.prefix(size))).isEmpty) }
        #expect(parser.ingestXPCPacket(packet(1)).isEmpty)
        #expect(parser.ingestXPCPacket(packet(2)).isEmpty)
        #expect(parser.ingestXPCPacket(packet(3)).count == 3)
        parser.reset()
        #expect(parser.ingestXPCPacket(acl(word(513) + [4, 0] + [0x1B, 0x33, 0])).isEmpty)
        #expect(parser.statistics.completedATTValues == 0)
    }

    @Test func frameAndPacketLoggerHeadersEnforceLengths() throws {
        let bytes: [UInt8] = [4, 0, 0x1B, 0x33, 0, 0, 0, 1, 2, 2, 0xB8, 0]
        let frame = try #require(AppleRemoteVoiceFrameParser.parse(bytes: bytes, handle: "0x0001"))
        #expect(frame.attributeHandle == 0x33)
        #expect(frame.sequence == 0x0201)
        #expect(frame.opusPayload == Data([0xB8, 0]))
        for size in 0..<bytes.count { #expect(AppleRemoteVoiceFrameParser.parse(bytes: Array(bytes.prefix(size)), handle: "0x0001") == nil) }
        let payload = Data("Bluetooth Profile Required".utf8)
        let length = UInt32(payload.count + 9)
        var record = Data([0, 0, 0, UInt8(length)] + [UInt8](repeating: 0, count: 8) + [0xFC])
        record.append(payload)
        #expect(AppleRemotePacketLoggerRecord.isValid(record))
        #expect(AppleRemotePacketLoggerRecord.isProfileRequired(record))
        #expect(!AppleRemotePacketLoggerRecord.isValid(Data(record.dropLast())))
        #expect(AppleRemotePacketLoggerRecord.isProfileRequired(payload + Data([0])))
    }

    @Test func opusLoaderClosesFailedSymbolsAndDestroysDecoder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func compile(_ source: String, name: String) throws -> URL {
            let c = directory.appendingPathComponent(name + ".c")
            let dylib = directory.appendingPathComponent(name + ".dylib")
            try source.write(to: c, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["clang", "-dynamiclib", c.path, "-o", dylib.path]
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
            return dylib
        }
        let missing = try compile("int unrelated(void) { return 0; }", name: "missing")
        #expect(AppleRemoteOpusDecoder(libraryPath: missing.path) == nil)
        let fixture = try compile("""
        #include <stdint.h>
        #include <stdlib.h>
        static int destroyed = 0;
        void *opus_decoder_create(int32_t rate, int channels, int *error) { *error=0; return malloc(1); }
        void opus_decoder_destroy(void *state) { free(state); destroyed++; }
        int opus_decode(void *state, const unsigned char *packet, int length, int16_t *pcm, int size, int fec) {
          if (length && packet[0] == 255) return -1;
          pcm[0]=42; pcm[1]=-42; return 2;
        }
        int destroy_count(void) { return destroyed; }
        """, name: "opus")
        let handle = try #require(dlopen(fixture.path, RTLD_NOW | RTLD_LOCAL))
        defer { dlclose(handle) }
        let symbol = try #require(dlsym(handle, "destroy_count"))
        let count = unsafeBitCast(symbol, to: (@convention(c) () -> Int32).self)
        var decoder: AppleRemoteOpusDecoder? = AppleRemoteOpusDecoder(libraryPath: fixture.path)
        #expect(decoder != nil)
        #expect(decoder?.decode(Data([0xB8, 0])) == [42, -42])
        #expect(decoder?.decode(Data([255])) == nil)
        #expect(decoder?.conceal() == [42, -42])
        decoder = nil
        #expect(count() == 1)
    }
}
