#!/usr/bin/env python3
"""Check real Git counts, Singapore dates, padding and shallow-history rejection."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

script = Path(__file__).with_name('release-metadata.sh')
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory) / 'repository'
    (root / 'scripts').mkdir(parents=True)
    shutil.copy2(script, root / 'scripts/release-metadata.sh')
    env = dict(os.environ, GIT_AUTHOR_NAME='Release Test', GIT_AUTHOR_EMAIL='test@example.invalid',
               GIT_COMMITTER_NAME='Release Test', GIT_COMMITTER_EMAIL='test@example.invalid',
               GIT_AUTHOR_DATE='2026-10-10T18:00:00Z', GIT_COMMITTER_DATE='2026-10-10T18:00:00Z')
    def git(*args):
        return subprocess.check_output(['git', '-C', str(root), *args], env=env, text=True)
    git('init', '-q')
    git('add', 'scripts/release-metadata.sh')
    for count in range(1, 114):
        git('commit', '-q', '--allow-empty', '-m', f'test: commit {count}')
        if count in (1, 11, 113):
            output = subprocess.check_output([str(root / 'scripts/release-metadata.sh')], text=True)
            assert f'RELEASE_TAG=v26-10-11.{count:03d}\n' in output, output
            assert f'RELEASE_COMMIT_COUNT={count}\n' in output, output
    shallow = Path(directory) / 'shallow'
    subprocess.run(['git', 'clone', '-q', '--depth', '1', root.as_uri(), str(shallow)], check=True)
    result = subprocess.run([str(shallow / 'scripts/release-metadata.sh')], capture_output=True, text=True)
    assert result.returncode != 0 and 'full Git history' in result.stderr
print('Release version checks passed: 001 / 011 / 113, Singapore date, shallow checkout.')
