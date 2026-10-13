#!/bin/bash
set -euo pipefail
bundle="${1:?Bundle path is required}"
options=(--force --deep --sign "${CODE_SIGN_IDENTITY:--}")
if [[ -n "${CODE_SIGN_KEYCHAIN:-}" ]]; then
    options+=(--keychain "$CODE_SIGN_KEYCHAIN")
fi
codesign "${options[@]}" "$bundle"
