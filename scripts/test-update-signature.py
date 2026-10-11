#!/usr/bin/env python3
"""Exercise the release verifier with fresh disposable keys and tampered bytes."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory() as directory:
    fixture = Path(directory) / 'fixture.swift'
    package = Path(directory) / 'fixture.pkg'
    package.write_bytes(b'valid package fixture')
    fixture.write_text('''import Foundation
import CryptoKit
let key = Curve25519.Signing.PrivateKey()
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
print(key.publicKey.rawRepresentation.base64EncodedString())
print(try key.signature(for: data).base64EncodedString())
print(Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString())
''')
    public, signature, other_public = subprocess.check_output(['swift', str(fixture), str(package)], text=True).splitlines()
    def verify(key):
        return subprocess.run(['swift', str(root / 'verify-update-signature.swift'), key, signature, str(package)], capture_output=True)
    assert verify(public).returncode == 0, 'Valid signature rejected'
    assert verify(other_public).returncode != 0, 'Wrong public key accepted'
    package.write_bytes(b'tampered package fixture')
    assert verify(public).returncode != 0, 'Tampered package accepted'
print('Signature tests passed: valid, wrong key, tampered package')
