#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
: "${RELEASE_TAG:?Run release-metadata.sh first}"
work="$(mktemp -d "$root/.build/verify-package.XXXXXX")"
trap 'rm -rf "$work"' EXIT
pkgutil --expand-full "$root/dist/release/Voice_Input_Buddy_${RELEASE_TAG}_macOS_universal.pkg" "$work/expanded"
app="$work/expanded/Payload/Applications/Voice Input Buddy.app"
driver="$work/expanded/Payload/Library/Audio/Plug-Ins/HAL/BuddyMic2ch.driver"
test -s "$app/Contents/MacOS/VoiceInputBuddy"
test -s "$driver/Contents/MacOS/BuddyMic2ch"
test -x "$work/expanded/Scripts/postinstall"
cmp "$root/scripts/driver-package/postinstall" "$work/expanded/Scripts/postinstall"
python3 "$root/scripts/verify-onboarding-resources.py" "$app/Contents/Resources"
codesign --verify --deep --strict "$app"
codesign --verify --deep --strict "$driver"
lipo "$app/Contents/MacOS/VoiceInputBuddy" -verify_arch arm64 x86_64
lipo "$driver/Contents/MacOS/BuddyMic2ch" -verify_arch arm64 x86_64
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" == "$RELEASE_COMMIT_COUNT" ]]
echo 'Verified combined PKG: universal app, universal HAL driver, version and postinstall script.'
