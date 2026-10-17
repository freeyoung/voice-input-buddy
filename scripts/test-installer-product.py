#!/usr/bin/env python3
"""Build and inspect an inert package; never install it or restart Core Audio."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent

@unittest.skipUnless(all(shutil.which(t) for t in ('pkgbuild', 'productbuild', 'pkgutil')), 'macOS packaging tools required')
class InstallerNoticeTests(unittest.TestCase):
    def test_notice_precedes_install_and_payload_identity_survives(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            component, product = work / 'component.pkg', work / 'product.pkg'
            subprocess.run(['pkgbuild', '--nopayload', '--identifier', 'com.example.inert-test',
                            '--version', '1.0', str(component)], check=True, capture_output=True)
            subprocess.run([str(ROOT / 'scripts/build-installer-product.sh'), str(component), str(product)],
                           check=True, capture_output=True)
            subprocess.run(['pkgutil', '--expand-full', str(product), str(work / 'expanded')],
                           check=True, capture_output=True)
            expanded = work / 'expanded'
            distribution = ET.parse(expanded / 'Distribution').getroot()
            self.assertEqual(distribution.find('readme').get('file'), 'ReadMe.html')
            notice = (expanded / 'Resources/ReadMe.html').read_text()
            self.assertIn('all system playback and recording', notice)
            self.assertIn('系统全部播放和录音', notice)
            self.assertIn('not notarized', notice)
            info = ET.parse(expanded / 'VoiceInputBuddyPayload.pkg/PackageInfo').getroot()
            self.assertEqual(info.get('identifier'), 'com.example.inert-test')
            self.assertEqual(info.get('version'), '1.0')

if __name__ == '__main__':
    unittest.main()
