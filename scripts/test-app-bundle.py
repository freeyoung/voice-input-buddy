#!/usr/bin/env python3
"""Exercise app assembly twice with a fixture compiler and signing failures."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parent.parent

class AppBundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'scripts').mkdir()
        shutil.copy2(SOURCE / 'scripts/build-app.sh', self.root / 'scripts/build-app.sh')
        shutil.copy2(SOURCE / 'scripts/verify-onboarding-resources.py', self.root / 'scripts/verify-onboarding-resources.py')
        shutil.copytree(SOURCE / 'Resources', self.root / 'Resources')
        (self.root / 'Sources/VoiceInputBuddy').mkdir(parents=True)
        shutil.copy2(SOURCE / 'Sources/VoiceInputBuddy/OnboardingView.swift',
                     self.root / 'Sources/VoiceInputBuddy/OnboardingView.swift')
        for name in ['LICENSE', 'THIRD_PARTY_NOTICES.md']:
            shutil.copy2(SOURCE / name, self.root / name)
        self.toolbin = self.root / 'tools'
        self.toolbin.mkdir()
        self.compilerbin = self.root / 'compiler'
        (self.compilerbin / 'Sparkle.framework').mkdir(parents=True)
        (self.compilerbin / 'Sparkle.framework/current').write_text('current framework')
        (self.compilerbin / 'VoiceInputBuddy').write_text('current executable')
        self.script(self.root / 'scripts/release-metadata.sh', "printf 'RELEASE_TAG=v26-10-11.001\\nRELEASE_BUNDLE_VERSION=26.10.11\\nRELEASE_COMMIT_COUNT=1\\nRELEASE_PACKAGE_VERSION=26.10.11.1\\n'\n")
        self.script(self.toolbin / 'swift', 'if [[ "$*" == *--show-bin-path* ]]; then printf "%s\\n" "$BUDDY_BUILD_FIXTURE_BIN"; fi\n')
        self.script(self.toolbin / 'lipo', 'cp "$2" "${@: -1}"\n')
        self.script(self.toolbin / 'otool', "printf 'cmd LC_RPATH\\npath @executable_path/../Frameworks\\n'\n")
        self.script(self.toolbin / 'codesign', '[[ "${BUDDY_BUILD_FIXTURE_FAIL_SIGN:-0}" != 1 ]]\n')
        self.app = self.root / 'dist/Voice Input Buddy.app'

    def script(self, path, body):
        path.write_text('#!/bin/bash\nset -euo pipefail\n' + body)
        path.chmod(0o755)

    def build(self, fail_sign=False):
        return subprocess.run(['bash', 'scripts/build-app.sh'], cwd=self.root,
            env={**os.environ, 'PATH': str(self.toolbin) + os.pathsep + os.environ['PATH'],
                 'BUDDY_BUILD_FIXTURE_BIN': str(self.compilerbin), 'BUILD_ARCHS': 'arm64',
                 'BUDDY_BUILD_FIXTURE_FAIL_SIGN': '1' if fail_sign else '0'},
            capture_output=True, text=True)

    def test_rebuild_removes_retired_resources_and_frameworks(self):
        resource = self.root / 'Resources/retired.txt'
        resource.write_text('retired resource')
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.app / 'Contents/Resources/retired.txt').exists())
        resource.unlink()
        (self.app / 'Contents/Frameworks/Retired.framework').mkdir()
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.app / 'Contents/Resources/retired.txt').exists())
        self.assertFalse((self.app / 'Contents/Frameworks/Retired.framework').exists())
        self.assertTrue((self.app / 'Contents/Frameworks/Sparkle.framework/current').exists())
        self.assertEqual(list((self.root / 'dist').glob('.app-build.*')), [])

    def test_failed_signing_preserves_previous_bundle(self):
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stderr)
        marker = self.app / 'Contents/Resources/previous-build.txt'
        marker.write_text('keep previous build')
        result = self.build(fail_sign=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(marker.read_text(), 'keep previous build')
        self.assertEqual(list((self.root / 'dist').glob('.app-build.*')), [])

if __name__ == '__main__':
    unittest.main()
