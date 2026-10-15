#!/usr/bin/env python3
"""Verify nested signing order, identity, symlinks and failure propagation."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('sign-bundle.sh').resolve()

class SigningTests(unittest.TestCase):
    def test_nested_code_is_signed_inside_out_with_the_release_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / 'Example App.app'
            framework = app / 'Contents/Frameworks/Example.framework'
            library = framework / 'Versions/A/Example'
            library.parent.mkdir(parents=True)
            library.write_bytes(bytes.fromhex('cffaedfe') + b'fixture')
            helper = framework / 'Versions/A/Helpers/Update.xpc'
            executable = helper / 'Contents/MacOS/Update'
            executable.parent.mkdir(parents=True)
            executable.write_bytes(bytes.fromhex('cffaedfe') + b'fixture')
            (framework / 'Versions/Current').symlink_to('A', target_is_directory=True)
            (framework / 'Example').symlink_to('Versions/Current/Example')
            log = root / 'calls.jsonl'
            codesign = root / 'codesign'
            codesign.write_text('#!/usr/bin/env python3\nimport json,os,sys\n'
                'with open(os.environ["SIGNING_TEST_LOG"], "a") as stream: stream.write(json.dumps(sys.argv[1:])+"\\n")\n'
                'if os.environ.get("SIGNING_TEST_FAIL") == sys.argv[-1]: sys.exit(1)\n')
            codesign.chmod(0o755)
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'],
                SIGNING_TEST_LOG=str(log), CODE_SIGN_IDENTITY='fixed release certificate',
                CODE_SIGN_KEYCHAIN='/tmp/release-test.keychain')
            subprocess.run(['bash', str(SCRIPT), str(app)], env=env, check=True)
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            signed = [call[-1] for call in calls]
            self.assertEqual(set(signed), {str(library), str(executable), str(helper), str(framework), str(app)})
            self.assertLess(signed.index(str(executable)), signed.index(str(helper)))
            self.assertLess(signed.index(str(helper)), signed.index(str(framework)))
            self.assertEqual(signed[-1], str(app))
            for call in calls:
                self.assertNotIn('--deep', call)
                self.assertEqual(call[call.index('--sign') + 1], env['CODE_SIGN_IDENTITY'])
                self.assertEqual(call[call.index('--keychain') + 1], env['CODE_SIGN_KEYCHAIN'])
            log.unlink()
            result = subprocess.run(['bash', str(SCRIPT), str(app)],
                env=dict(env, SIGNING_TEST_FAIL=str(executable)), capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn(str(app), [json.loads(line)[-1] for line in log.read_text().splitlines()])

if __name__ == '__main__':
    unittest.main()
