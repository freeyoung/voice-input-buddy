import AppleRemoteAudioCore
import Foundation
import Testing

@Suite("Helper startup token pipe")
struct HelperTokenTests {
    private let token = "01234567-89AB-CDEF-0123-456789ABCDEF"

    @Test func validTokenRoundTripsOverPipe() throws {
        let pipe = try AppleRemoteAudioIPC.startupTokenPipe(token: token)
        #expect(try AppleRemoteAudioIPC.readStartupToken(from: pipe.fileHandleForReading) == token)
        #expect(try pipe.fileHandleForReading.read(upToCount: 1)?.isEmpty != false)
    }

    @Test func childReceivesTokenWithNoSecretInArguments() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cat")
        process.arguments = []
        process.standardInput = try AppleRemoteAudioIPC.startupTokenPipe(token: token)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let received = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(String(data: received, encoding: .utf8) == token + "\n")
    }

    @Test func tokenWriterRejectsMalformedSecrets() {
        for value in ["", "not-a-uuid", token + "\n", token + "extra"] {
            #expect(throws: AppleRemoteAudioIPC.StartupTokenError.invalidToken) {
                try AppleRemoteAudioIPC.startupTokenPipe(token: value)
            }
        }
    }

    @Test func tokenReaderRejectsMissingTruncatedAndOversizedInput() throws {
        for data in [Data(), Data(token.utf8), Data((token + "x").utf8),
                     Data((String(repeating: "x", count: 36) + "\n").utf8),
                     Data(repeating: 0xFF, count: 37), Data(repeating: 0x41, count: 100)] {
            let pipe = Pipe()
            try pipe.fileHandleForWriting.write(contentsOf: data)
            try pipe.fileHandleForWriting.close()
            #expect(throws: AppleRemoteAudioIPC.StartupTokenError.invalidToken) {
                try AppleRemoteAudioIPC.readStartupToken(from: pipe.fileHandleForReading)
            }
        }
    }
}
