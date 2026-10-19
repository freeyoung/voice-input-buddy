#!/usr/bin/env python3
"""Check fixed-identity local builds, credential isolation, and cleanup on failure."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('local_build', Path(__file__).with_name('build-local-signed.py'))
local_build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(local_build)


class LocalSignedBuildTests(unittest.TestCase):
    def setUp(self):
        self.fixture = tempfile.TemporaryDirectory()
        self.addCleanup(self.fixture.cleanup)
        self.identity = Path(self.fixture.name)
        (self.identity / 'release-signing.p12').write_bytes(b'fixture-archive')
        (self.identity / 'password.txt').write_text('fixture-password\n')
        self.calls = []
        self.fail = None
        self.incomplete = False

    def run_command(self, command, **kwargs):
        self.calls.append((command, kwargs))
        if self.fail and self.fail in command:
            raise subprocess.CalledProcessError(1, command)
        if command[-1] == 'setup':
            content = 'CODE_SIGN_IDENTITY=pinned-fingerprint\n'
            if not self.incomplete:
                content += 'CODE_SIGN_KEYCHAIN=/fixture/local.keychain-db\n'
            Path(kwargs['env']['GITHUB_ENV']).write_text(content)
        return subprocess.CompletedProcess(command, 0)

    def test_uses_fixed_identity_for_all_artifacts_and_isolates_credentials(self):
        with mock.patch.object(local_build.subprocess, 'run', side_effect=self.run_command), \
             mock.patch.dict(os.environ, MACOS_SIGNING_P12_PASSWORD='inherited-secret'):
            local_build.build(self.identity, 'debug')
        self.assertEqual(len(self.calls), 6)
        setup = self.calls[0][1]['env']
        self.assertEqual(setup['MACOS_SIGNING_P12_PASSWORD'], 'fixture-password')
        self.assertTrue(setup['PATH'].startswith('/usr/bin:'))
        for _, arguments in self.calls[1:]:
            self.assertNotIn('MACOS_SIGNING_P12_BASE64', arguments['env'])
            self.assertNotIn('MACOS_SIGNING_P12_PASSWORD', arguments['env'])
        for _, arguments in self.calls[1:-1]:
            self.assertEqual(arguments['env']['CODE_SIGN_IDENTITY'], 'pinned-fingerprint')
            self.assertEqual(arguments['env']['CODE_SIGN_KEYCHAIN'], '/fixture/local.keychain-db')
        self.assertEqual(self.calls[-1][0][-1], 'cleanup')
        self.assertFalse(Path(setup['RUNNER_TEMP']).exists())

    def test_setup_failure_still_cleans_up_and_never_builds(self):
        self.fail = 'setup'
        with mock.patch.object(local_build.subprocess, 'run', side_effect=self.run_command):
            with self.assertRaises(subprocess.CalledProcessError):
                local_build.build(self.identity, 'debug')
        self.assertEqual([call[0][-1] for call in self.calls], ['setup', 'cleanup'])

    def test_missing_environment_never_falls_back_to_ad_hoc(self):
        self.incomplete = True
        with mock.patch.object(local_build.subprocess, 'run', side_effect=self.run_command):
            with self.assertRaises(RuntimeError):
                local_build.build(self.identity, 'debug')
        self.assertEqual([call[0][-1] for call in self.calls], ['setup', 'cleanup'])

    def test_build_failure_cleans_up_without_packaging(self):
        self.fail = str(local_build.ROOT / 'scripts/build-app.sh')
        with mock.patch.object(local_build.subprocess, 'run', side_effect=self.run_command):
            with self.assertRaises(subprocess.CalledProcessError):
                local_build.build(self.identity, 'release')
        self.assertEqual(self.calls[-1][0][-1], 'cleanup')
        self.assertEqual(len(self.calls), 3)

    def test_missing_identity_never_generates_a_replacement(self):
        (self.identity / 'release-signing.p12').unlink()
        with mock.patch.object(local_build.subprocess, 'run') as command:
            with self.assertRaises(RuntimeError):
                local_build.build(self.identity, 'debug')
            command.assert_not_called()


if __name__ == '__main__':
    unittest.main()
