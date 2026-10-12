#!/usr/bin/env python3
"""Remove the unused architecture from every real Mach-O in a copied framework."""
from pathlib import Path
import os
import subprocess
import sys
root, architecture = Path(sys.argv[1]), sys.argv[2]
for path in root.rglob('*'):
    if not path.is_file() or path.is_symlink():
        continue
    if 'Mach-O' not in subprocess.check_output(['/usr/bin/file', '-b', str(path)], text=True):
        continue
    arches = subprocess.check_output(['lipo', '-archs', str(path)], text=True).split()
    if architecture not in arches:
        raise RuntimeError(f'{path.name} does not support {architecture}')
    if len(arches) > 1:
        temporary = path.with_name(path.name + '.thin')
        subprocess.run(['lipo', str(path), '-thin', architecture, '-output', str(temporary)], check=True)
        temporary.chmod(path.stat().st_mode)
        os.replace(temporary, path)
