import Foundation
import CryptoKit

// Verify against the public key embedded in the app, independently of the signer.
guard CommandLine.arguments.count == 4,
      let key = Data(base64Encoded: CommandLine.arguments[1]),
      let signature = Data(base64Encoded: CommandLine.arguments[2]) else {
    fatalError("Expected public key, signature and package path")
}
let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: key)
let payload = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3]))
guard publicKey.isValidSignature(signature, for: payload) else {
    fputs("Update signature does not match the embedded public key or package.\n", stderr)
    exit(1)
}
print("Verified package Ed25519 signature against application public key.")
