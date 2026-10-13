#!/usr/bin/env python3
"""Exercise removal and installation actions only against disposable fixtures."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parent
class InstallationActionsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.library = SCRIPTS / 'installation-common.sh'

    def bundle(self, path, identity):
        (path / 'Contents').mkdir(parents=True)
        (path / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': identity}))
        return path

    def remove(self, path, identity):
        return subprocess.run(['bash', '-c', 'source "$1"; buddy_remove_bundle "$2" "$3"',
                               'test', str(self.library), str(path), identity], capture_output=True)

    def test_product_bundle_is_removed_and_repeat_is_safe(self):
        bundle = self.bundle(self.root / 'app.app', 'com.zfdang.voice-input-buddy')
        self.assertEqual(self.remove(bundle, 'com.zfdang.voice-input-buddy').returncode, 0)
        self.assertFalse(bundle.exists())
        self.assertEqual(self.remove(bundle, 'com.zfdang.voice-input-buddy').returncode, 0)

    def test_foreign_bundle_and_symlink_are_refused(self):
        bundle = self.bundle(self.root / 'foreign.driver', 'com.example.other')
        self.assertNotEqual(self.remove(bundle, 'com.zfdang.voice-input-buddy.mic').returncode, 0)
        self.assertTrue(bundle.exists())
        owned = self.bundle(self.root / 'owned.driver', 'com.zfdang.voice-input-buddy.mic')
        link = self.root / 'link.driver'; link.symlink_to(owned, target_is_directory=True)
        self.assertNotEqual(self.remove(link, 'com.zfdang.voice-input-buddy.mic').returncode, 0)
        self.assertTrue(owned.exists())

    def test_installation_preserves_current_driver_and_other_bundles(self):
        hal = self.root / 'Library/Audio/Plug-Ins/HAL'
        other = self.bundle(hal / 'OtherMicrophone.driver', 'com.example.microphone')
        new = self.bundle(hal / 'VoiceInputBuddyMic.driver', 'com.zfdang.voice-input-buddy.mic')
        staging = self.root / 'package-scripts'; staging.mkdir()
        for source in [self.library, SCRIPTS / 'driver-package/preinstall']:
            shutil.copy2(source, staging / source.name)
        result = subprocess.run(['bash', str(staging / 'preinstall'), 'package.pkg', '/', str(self.root)], capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(other.exists()); self.assertTrue(new.exists())

    def test_cleanup_only_removes_this_products_personal_data(self):
        for relative in ['Preferences/com.zfdang.voice-input-buddy.plist',
                         'Application Support/VoiceInputBuddy', 'Logs/VoiceInputBuddy',
                         'Caches/com.zfdang.voice-input-buddy',
                         'Saved Application State/com.zfdang.voice-input-buddy.savedState']:
            (self.root / 'Library' / relative).mkdir(parents=True)
        other = self.root / 'Library/Logs/other-app'; other.mkdir()
        result = subprocess.run(['bash', '-c', 'source "$1"; buddy_cleanup_user_data "$2"',
                                  'test', str(self.library), str(self.root)], capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(other.exists())
        self.assertFalse((self.root / 'Library/Logs/VoiceInputBuddy').exists())
        self.assertFalse((self.root / 'Library/Preferences/com.zfdang.voice-input-buddy.plist').exists())

    def test_preinstall_refuses_foreign_app_or_driver_before_overwriting(self):
        staging = self.root / 'package-scripts'; staging.mkdir()
        for source in [self.library, SCRIPTS / 'driver-package/preinstall']:
            shutil.copy2(source, staging / source.name)
        for foreign_app in [True, False]:
            with self.subTest(foreign_app=foreign_app):
                volume = self.root / str(foreign_app)
                app = self.bundle(volume / 'Applications/Voice Input Buddy.app',
                                  'com.example.foreign' if foreign_app else 'com.zfdang.voice-input-buddy')
                driver = self.bundle(volume / 'Library/Audio/Plug-Ins/HAL/VoiceInputBuddyMic.driver',
                                     'com.zfdang.voice-input-buddy.mic' if foreign_app else 'com.example.foreign')
                result = subprocess.run(['bash', str(staging / 'preinstall'), 'package.pkg', '/', str(volume)],
                                        capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(app.exists())
                self.assertTrue(driver.exists())

if __name__ == '__main__': unittest.main()
