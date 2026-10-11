#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
[[ -d "$root/dist/BuddyMic2ch.driver" ]] || { echo 'Run scripts/build-driver.sh first' >&2; exit 1; }
test -s "$root/dist/BuddyMic2ch.driver/Contents/MacOS/BuddyMic2ch"
codesign --verify --deep --strict "$root/dist/BuddyMic2ch.driver"
work="$(mktemp -d "$root/.build/driver-package.XXXXXX")"
mkdir -p "$work/payload/Library/Audio/Plug-Ins/HAL"
cp -R "$root/dist/BuddyMic2ch.driver" "$work/payload/Library/Audio/Plug-Ins/HAL/"
pkgbuild --root "$work/payload" --identifier com.zfdang.voice-input-buddy.mic.installer \
    --version 0.1.0 --install-location / "$root/dist/VoiceInputBuddy-Microphone.pkg"
echo 'Unsigned local installer. Public releases require Developer ID Installer signing and notarization.'
