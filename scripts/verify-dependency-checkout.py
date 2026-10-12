#!/usr/bin/env python3
"""Reject local dependency edits; permit only the exact checked-in driver patch."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def verify(repository, patch=None):
    def git(*args, env=None):
        return subprocess.check_output(['git', '-C', str(repository), *args], env=env)
    if git('ls-files', '--others', '--exclude-standard').strip():
        raise ValueError(f'Untracked files in dependency checkout: {repository}')
    actual = git('diff', '--binary', 'HEAD', '--')
    if not actual:
        return
    if patch is not None:
        with tempfile.TemporaryDirectory() as directory:
            environment = dict(os.environ, GIT_INDEX_FILE=str(Path(directory) / 'index'))
            git('read-tree', 'HEAD', env=environment)
            git('apply', '--cached', str(patch.resolve()), env=environment)
            expected = git('diff', '--cached', '--binary', 'HEAD', '--', env=environment)
        if actual == expected:
            return
    raise ValueError(f'Unexpected local changes in dependency checkout: {repository}')


if __name__ == '__main__':
    try:
        verify(Path(sys.argv[1]), Path(sys.argv[2]) if len(sys.argv) == 3 else None)
    except (ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
