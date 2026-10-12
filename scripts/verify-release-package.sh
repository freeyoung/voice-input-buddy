#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/scripts/architecture.sh"
: "${RELEASE_TAG:?Run release-metadata.sh first}"
work="$(mktemp -d "$root/.build/verify-package.XXXXXX")"
trap 'rm -rf "$work"' EXIT
pkgutil --expand-full "$root/dist/release/Voice_Input_Buddy_${RELEASE_TAG}_macOS_${RELEASE_ARCH_LABEL}.pkg" "$work/expanded"
app="$work/expanded/Payload/Applications/Voice Input Buddy.app"
driver="$work/expanded/Payload/Library/Audio/Plug-Ins/HAL/VoiceInputBuddyMic.driver"
test -s "$app/Contents/MacOS/VoiceInputBuddy"
test -s "$driver/Contents/MacOS/VoiceInputBuddyMic"
test -x "$work/expanded/Scripts/postinstall"
cmp "$root/scripts/driver-package/postinstall" "$work/expanded/Scripts/postinstall"
cmp "$root/scripts/driver-package/preinstall" "$work/expanded/Scripts/preinstall"
cmp "$root/scripts/installation-common.sh" "$work/expanded/Scripts/installation-common.sh"
python3 "$root/scripts/verify-onboarding-resources.py" "$app/Contents/Resources"
codesign --verify --deep --strict "$app"
codesign --verify --deep --strict "$driver"
[[ "$(lipo -archs "$app/Contents/MacOS/VoiceInputBuddy")" == "$BUILD_ARCH" ]]
[[ "$(lipo -archs "$driver/Contents/MacOS/VoiceInputBuddyMic")" == "$BUILD_ARCH" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" == "$RELEASE_COMMIT_COUNT" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :BuddyReleaseVersion' "$app/Contents/Info.plist")" == "$RELEASE_TAG" ]]
echo 'Verified architecture-specific app, HAL driver, version and installation scripts.'
