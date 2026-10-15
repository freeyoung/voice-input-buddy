#!/bin/bash
set -euo pipefail
bundle="${1:?Bundle path is required}"
options=(--force --sign "${CODE_SIGN_IDENTITY:--}")
if [[ -n "${CODE_SIGN_KEYCHAIN:-}" ]]; then
    options+=(--keychain "$CODE_SIGN_KEYCHAIN")
fi
# Sign real nested code from the inside out. Do not follow framework symlinks.
# A failed discovery must abort rather than leave nested code signed by someone else.
manifest="$(mktemp)"
trap 'rm -f "$manifest"' EXIT
python3 - "$bundle" > "$manifest" <<'PY'
import os
from pathlib import Path
import sys
root = Path(sys.argv[1])
if not root.is_dir() or root.is_symlink():
    raise SystemExit('Expected a real bundle directory')
magic = {bytes.fromhex(value) for value in
         ['feedface', 'cefaedfe', 'feedfacf', 'cffaedfe', 'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca']}
for directory, dirs, files in os.walk(root, topdown=False, followlinks=False):
    path = Path(directory)
    for name in sorted(files):
        file = path / name
        if file.is_symlink():
            continue
        with file.open('rb') as stream:
            is_macho = stream.read(4) in magic
        if is_macho:
            sys.stdout.buffer.write(os.fsencode(file) + b'\0')
    if path != root and not path.is_symlink() and path.suffix in {'.app', '.framework', '.xpc', '.appex', '.bundle', '.driver'}:
        sys.stdout.buffer.write(os.fsencode(path) + b'\0')
PY
while IFS= read -r -d '' nested; do
    codesign "${options[@]}" "$nested"
done < "$manifest"
codesign "${options[@]}" "$bundle"
