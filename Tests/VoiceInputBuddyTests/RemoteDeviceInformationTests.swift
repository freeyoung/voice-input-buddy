import Foundation
import Testing
@testable import VoiceInputBuddy

@Suite("Remote device information")
struct RemoteDeviceInformationTests {
    @Test func missingReadingsDoNotAdvertiseDefaultIdentityOrAudio() {
        let information = RemoteDeviceInformation()
        #expect(information.modelNumber == nil)
        #expect(information.firmwareRevision == nil)
        #expect(information.identitySummary == nil)
        #expect(information.audioSummary == nil)
    }

    @Test func decodesOptionalBluetoothStringsWithoutPadding() {
        #expect(RemoteDeviceInformation.deviceString(Data(" RC003\0\r\n".utf8)) == "RC003")
        #expect(RemoteDeviceInformation.deviceString(Data("\0 \n".utf8)) == nil)
        #expect(RemoteDeviceInformation.deviceString(Data([0xFF])) == nil)
    }

    @Test func displaysReportedIdentityAndNegotiatedAudio() throws {
        let identity = try #require(RemoteHIDIdentity.fromPnP(Data([2, 0xD1, 0x18, 0x50, 0x94, 0, 0])))
        let capabilities = try #require(ATVVCapabilities.parse(Data([0x0B, 1, 0, 2, 3, 0, 120])))
        let information = RemoteDeviceInformation(identity: identity, capabilities: capabilities)
        #expect(information.identitySummary == "VID 18D1 · PID 9450")
        #expect(information.audioSummary == "ATVV 1.0 · IMA ADPCM · 16 kHz · 120 B")
    }

    @Test func retainsActualEightKilohertzReading() throws {
        let capabilities = try #require(ATVVCapabilities.parse(Data([0x0B, 1, 0, 1, 3, 0, 134])))
        let information = RemoteDeviceInformation(capabilities: capabilities)
        #expect(information.audioSummary == "ATVV 1.0 · IMA ADPCM · 8 kHz · 134 B")
    }
}
