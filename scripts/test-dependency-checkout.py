#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('dependency', Path(__file__).with_name('verify-dependency-checkout.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class CheckoutTests(unittest.TestCase):
    def test_only_clean_or_exact_product_patch_is_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo = root / 'dependency'
            repo.mkdir()
            def git(*args):
                return subprocess.check_output(['git', '-C', str(repo), *args], stderr=subprocess.DEVNULL)
            git('init')
            source = repo / 'source.c'
            source.write_text('original\n')
            git('add', 'source.c')
            git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-m', 'fixture')
            module.verify(repo)
            source.write_text('patched\n')
            patch = root / 'product.patch'
            patch.write_bytes(git('diff', '--binary'))
            module.verify(repo, patch)
            with self.assertRaises(ValueError): module.verify(repo)
            source.write_text('patched\nextra change\n')
            with self.assertRaises(ValueError): module.verify(repo, patch)
            source.write_text('patched\n')
            (repo / 'unexpected.c').write_text('untracked\n')
            with self.assertRaises(ValueError): module.verify(repo, patch)

if __name__ == '__main__': unittest.main()
