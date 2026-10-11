#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
swift build --disable-keychain -c "${CONFIGURATION:-release}" --product VoiceInputBuddy
bin="$(swift build --disable-keychain -c "${CONFIGURATION:-release}" --show-bin-path)"
app="$root/dist/Voice Input Buddy.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$bin/VoiceInputBuddy" "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp -R Resources/. "$app/Contents/Resources/"
cp LICENSE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
cp -R "$bin/Sparkle.framework" "$app/Contents/Frameworks/"
if ! otool -l "$app/Contents/MacOS/VoiceInputBuddy" | sed -n '/cmd LC_RPATH/,+3p' | grep -Fq '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath @executable_path/../Frameworks "$app/Contents/MacOS/VoiceInputBuddy"
fi
codesign --force --deep --sign "${CODE_SIGN_IDENTITY:--}" "$app"
printf 'Built %s\nLocal development build; Developer ID signing and notarization are required for public distribution.\n' "$app"
