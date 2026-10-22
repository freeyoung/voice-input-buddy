#!/usr/bin/env python3
"""Exercise App ownership on fixtures without installing or changing system files."""
from pathlib import Path
import json
import os
import plistlib
import shutil
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parent


class AppOwnershipTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / 'Applications/Voice Input Buddy.app'
        self.app.mkdir(parents=True)
        (self.app / 'Contents').mkdir()
        (self.app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'com.zfdang.voice-input-buddy',
            'CFBundleExecutable': 'VoiceInputBuddy',
        }))
        self.staging = self.root / 'scripts'
        self.staging.mkdir()
        shutil.copy2(SCRIPTS / 'installation-common.sh', self.staging)
        self.script = self.staging / 'postinstall'
        self.source = (SCRIPTS / 'app-package/postinstall').read_text().replace(
            "app='/Applications/Voice Input Buddy.app'", f"app='{self.app}'")
        self.calls = self.root / 'calls'
        self.stub('/usr/bin/stat', 'echo 501')
        self.stub('/usr/bin/id', 'echo 20')
        self.stub('/usr/sbin/chown', f'printf "%s\\n" "$@" > "{self.calls}"')
        self.driver_calls = self.root / 'driver-calls'
        self.driver_script = self.staging / 'driver-postinstall'
        self.driver_script.write_text(f'#!/bin/bash\nprintf "%s\\n" "$@" > "{self.driver_calls}"\n')

    def stub(self, command, body):
        target = self.staging / Path(command).name
        target.write_text('#!/bin/bash\n' + body + '\n')
        target.chmod(0o755)
        self.source = self.source.replace(command, str(target))

    def run_install(self, volume='/'):
        self.script.write_text(self.source)
        return subprocess.run(['bash', str(self.script), 'package.pkg', '/', volume],
                              capture_output=True, text=True)

    def test_only_app_is_assigned_to_console_user_and_driver_step_still_runs(self):
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls.read_text().splitlines(), ['-R', '-P', '-h', '501:20', str(self.app)])
        self.assertEqual(self.driver_calls.read_text().splitlines(), ['package.pkg', '/', '/'])

    def test_no_desktop_user_or_offline_volume_keeps_system_ownership(self):
        for uid, volume in [('0', '/'), ('248', '/'), ('501', '/Volumes/Other')]:
            with self.subTest(uid=uid, volume=volume):
                (self.staging / 'stat').write_text(f'#!/bin/bash\necho {uid}\n')
                result = self.run_install(volume)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(self.calls.exists())
                self.assertTrue(self.driver_calls.exists())

    def test_foreign_app_and_top_level_symlink_are_refused(self):
        info = self.app / 'Contents/Info.plist'
        info.write_bytes(plistlib.dumps({'CFBundleIdentifier': 'com.example.other'}))
        self.assertNotEqual(self.run_install().returncode, 0)
        self.assertFalse(self.calls.exists())
        moved = self.app.with_name('Other.app')
        self.app.rename(moved)
        self.app.symlink_to(moved, target_is_directory=True)
        self.assertNotEqual(self.run_install().returncode, 0)
        self.assertFalse(self.calls.exists())

    def test_failed_ownership_change_is_reported(self):
        (self.staging / 'chown').write_text('#!/bin/bash\nexit 1\n')
        self.assertNotEqual(self.run_install().returncode, 0)

    def test_real_ownership_command_preserves_signature_modes_and_bundle_symlinks(self):
        executable = self.app / 'Contents/MacOS/VoiceInputBuddy'
        executable.parent.mkdir()
        subprocess.run(['xcrun', 'clang', '-x', 'c', '-', '-o', str(executable)],
                       input='int main(void) { return 0; }', text=True, check=True)
        link = self.app / 'Contents/executable-link'
        link.symlink_to('MacOS/VoiceInputBuddy')
        subprocess.run(['codesign', '--force', '--sign', '-', str(self.app)], capture_output=True, check=True)
        signature = (self.app / 'Contents/_CodeSignature/CodeResources').read_bytes()
        modes = executable.stat().st_mode
        # Use the actual recursive command, with this test user's existing ownership.
        # Record the invocation while executing chown on the disposable bundle.
        observer = self.staging / 'observe-chown'
        observer.write_text('#!/usr/bin/env python3\nimport json, subprocess, sys\n'
            f'open({str(self.calls)!r}, "w").write(json.dumps(sys.argv[1:]))\n'
            'subprocess.run(["/usr/sbin/chown", *sys.argv[1:]], check=True)\n')
        observer.chmod(0o755)
        self.source = self.source.replace(str(self.staging / 'chown'), str(observer))
        (self.staging / 'stat').write_text(f'#!/bin/bash\necho {os.getuid()}\n')
        (self.staging / 'id').write_text(f'#!/bin/bash\necho {os.getgid()}\n')
        result = self.run_install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('-P', json.loads(self.calls.read_text()))
        self.assertTrue(link.is_symlink())
        self.assertEqual(os.readlink(link), 'MacOS/VoiceInputBuddy')
        self.assertEqual(executable.stat().st_mode, modes)
        self.assertEqual((self.app / 'Contents/_CodeSignature/CodeResources').read_bytes(), signature)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(self.app)], check=True)


if __name__ == '__main__':
    unittest.main()
