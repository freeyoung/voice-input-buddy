#!/usr/bin/env python3
import base64
import importlib.util
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location('appcast', Path(__file__).with_name('generate-appcast.py'))
appcast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appcast)

class AppcastTests(unittest.TestCase):
    def test_package_metadata_and_invalid_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            package = Path(directory) / 'Voice_Input_Buddy_v26-10-11.021_macOS_universal.pkg'
            package.write_bytes(b'test package bytes')
            output = Path(directory) / 'appcast.xml'
            signature = base64.b64encode(bytes(64)).decode()
            appcast.generate(package, 'v26-10-11.021', '21', signature, output)
            item = ET.parse(output).find('channel/item')
            self.assertEqual(item.find(f'{{{appcast.SPARKLE}}}version').text, '21')
            enclosure = item.find('enclosure')
            self.assertEqual(enclosure.get('length'), str(package.stat().st_size))
            self.assertEqual(enclosure.get(f'{{{appcast.SPARKLE}}}installationType'), 'package')
            self.assertTrue(enclosure.get('url').endswith('/v26-10-11.021/' + package.name))
            for tag, version, sig in [('bad', '21', signature), ('v26-10-11.021', '0', signature),
                                      ('v26-10-11.021', '22', signature), ('v26-10-11.021', '21', 'bad'), ('v26-10-11.022', '22', signature)]:
                with self.assertRaises(ValueError):
                    appcast.generate(package, tag, version, sig, output)

if __name__ == '__main__':
    unittest.main()
