#!/usr/bin/env python3
"""Exercise the real loopback helper without requesting audio or hardware access."""
import json
from pathlib import Path
import select
import socket
import struct
import subprocess
import sys
import unittest
import uuid

BINARY = Path(sys.argv.pop(1)) if len(sys.argv) > 1 else Path('.build/debug/VoiceInputBuddyAppleRemoteAudioCapture')

def frame(kind, payload=b''):
    body = bytes([kind]) + payload
    return struct.pack('!I', len(body)) + body

def receive(connection):
    def exact(size):
        data = b''
        while len(data) < size:
            part = connection.recv(size - len(data))
            if not part: raise EOFError('closed connection')
            data += part
        return data
    size = struct.unpack('!I', exact(4))[0]
    if not 1 <= size <= 4096: raise ValueError('invalid frame size')
    body = exact(size)
    return body[0], body[1:]

class HelperSessionTests(unittest.TestCase):
    def setUp(self):
        self.token = str(uuid.uuid4())
        self.process = subprocess.Popen([str(BINARY.resolve()), '--port', '0'], stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(self.cleanup)
        self.process.stdin.write((self.token + '\n').encode())
        self.process.stdin.close()
        if not select.select([self.process.stdout], [], [], 10)[0]: self.fail('helper startup timed out')
        line = self.process.stdout.readline().decode()
        self.assertTrue(line.startswith('READY '), line)
        self.port = int(line.split()[1])

    def cleanup(self):
        self.process.terminate()
        try: self.process.wait(timeout=3)
        except subprocess.TimeoutExpired: self.process.kill(); self.process.wait()
        self.process.stdout.close()
        self.process.stderr.close()

    def connect(self):
        connection = socket.create_connection(('127.0.0.1', self.port), timeout=5)
        self.addCleanup(connection.close)
        return connection

    def authenticate(self, connection):
        connection.sendall(frame(1, self.token.encode()))
        kind, status = receive(connection)
        self.assertEqual(kind, 4)
        self.assertTrue(status and status != b'unauthorized')

    def test_pending_or_new_clients_cannot_displace_authenticated_owner(self):
        silent = self.connect()
        invalid = self.connect()
        invalid.sendall(frame(1, b'invalid'))
        owner = self.connect()
        self.authenticate(owner)
        for authenticate in [False, True]:
            intruder = self.connect()
            if authenticate:
                try: intruder.sendall(frame(1, self.token.encode()))
                except OSError: pass
            owner.sendall(frame(1, self.token.encode()))
            kind, status = receive(owner)
            self.assertEqual(kind, 4)
            self.assertTrue(status and status != b'unauthorized')
        silent.settimeout(5)
        self.assertEqual(silent.recv(1), b'')

    def test_expired_silent_handshake_allows_new_authenticated_session(self):
        silent = self.connect()
        self.assertEqual(silent.recv(1), b'')
        self.authenticate(self.connect())

if __name__ == '__main__': unittest.main()
