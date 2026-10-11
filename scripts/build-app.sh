#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
configuration="${CONFIGURATION:-release}"
binaries=()
# Release builds include both Mac architectures; local builds default to the host.
for arch in ${BUILD_ARCHS:-$(uname -m)}; do
    scratch="$root/.build/app-$arch"
    swift build --disable-keychain --scratch-path "$scratch" -c "$configuration" --arch "$arch" --product VoiceInputBuddy
    bin="$(swift build --disable-keychain --scratch-path "$scratch" -c "$configuration" --arch "$arch" --show-bin-path)"
    binaries+=("$bin/VoiceInputBuddy")
done
app="$root/dist/Voice Input Buddy.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/VoiceInputBuddy"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp -R Resources/. "$app/Contents/Resources/"
cp LICENSE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/"
cp -R "$bin/Sparkle.framework" "$app/Contents/Frameworks/"
if ! otool -l "$app/Contents/MacOS/VoiceInputBuddy" | sed -n '/cmd LC_RPATH/,+3p' | grep -Fq '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath @executable_path/../Frameworks "$app/Contents/MacOS/VoiceInputBuddy"
fi
if [[ -n "${RELEASE_BUNDLE_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $RELEASE_BUNDLE_VERSION" "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $RELEASE_COMMIT_COUNT" "$app/Contents/Info.plist"
fi
python3 scripts/verify-onboarding-resources.py "$app/Contents/Resources"
codesign --force --deep --sign "${CODE_SIGN_IDENTITY:--}" "$app"
printf 'Built %s\nLocal development build; Developer ID signing and notarization are required for public distribution.\n' "$app"
