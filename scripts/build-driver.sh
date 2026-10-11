#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$root/.build/buddy-driver"
source="$work/BlackHole"
revision=e2b22aaaba4e507a097131704bf96dabc004d9cf
mkdir -p "$work" "$root/dist"
if [[ ! -d "$source/.git" ]]; then
    git clone --depth 1 --branch v0.7.1 https://github.com/ExistentialAudio/BlackHole.git "$source"
fi
[[ "$(git -C "$source" rev-parse HEAD)" == "$revision" ]] || { echo 'Unexpected BlackHole revision' >&2; exit 1; }
if git -C "$source" apply --check "$root/third_party/blackhole/device-usb.patch" 2>/dev/null; then
    git -C "$source" apply "$root/third_party/blackhole/device-usb.patch"
else
    git -C "$source" apply --reverse --check "$root/third_party/blackhole/device-usb.patch"
fi
driver="$root/dist/BuddyMic2ch.driver"
mkdir -p "$driver/Contents/MacOS" "$driver/Contents/Resources"
for arch in arm64 x86_64; do
    xcrun clang -arch "$arch" -mmacosx-version-min=14.0 -bundle -O2 \
        -framework CoreFoundation -framework CoreAudio -framework Accelerate \
        '-DkDriver_Name="BuddyMic2ch"' '-DkPlugIn_BundleID="com.zfdang.voice-input-buddy.mic"' \
        '-DkDevice_Name="Voice Input Buddy"' -DkNumber_Of_Channels=2 \
        "$source/BlackHole/BlackHole.c" -o "$work/BuddyMic2ch-$arch"
done
lipo -create "$work/BuddyMic2ch-arm64" "$work/BuddyMic2ch-x86_64" -output "$driver/Contents/MacOS/BuddyMic2ch"
cp "$source/BlackHole/BlackHole.plist" "$driver/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable BuddyMic2ch' "$driver/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.zfdang.voice-input-buddy.mic' "$driver/Contents/Info.plist"
cp "$root/Resources/AppIcon.icns" "$driver/Contents/Resources/BlackHole.icns"
cp "$source/LICENSE" "$driver/Contents/Resources/BlackHole-LICENSE"

codesign --force --deep --sign "${CODE_SIGN_IDENTITY:--}" "$root/dist/BuddyMic2ch.driver"
printf 'Driver source: %s\nInclude this source and patch alongside driver releases.\n' "$source"
