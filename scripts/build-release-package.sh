#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
: "${RELEASE_TAG:?Run release-metadata.sh first}"
: "${RELEASE_PACKAGE_VERSION:?Run release-metadata.sh first}"
app="$root/dist/Voice Input Buddy.app"
driver="$root/dist/BuddyMic2ch.driver"
codesign --verify --deep --strict "$app"
codesign --verify --deep --strict "$driver"
work="$(mktemp -d "$root/.build/release-package.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/payload/Applications" "$work/payload/Library/Audio/Plug-Ins/HAL" "$work/scripts" "$root/dist/release"
ditto "$app" "$work/payload/Applications/Voice Input Buddy.app"
ditto "$driver" "$work/payload/Library/Audio/Plug-Ins/HAL/BuddyMic2ch.driver"
cp scripts/driver-package/postinstall "$work/scripts/postinstall"
chmod 755 "$work/scripts/postinstall"
# Disable bundle relocation: always update the canonical /Applications copy.
pkgbuild --analyze --root "$work/payload" "$work/components.plist"
python3 - "$work/components.plist" <<'PY'
import plistlib, sys
path = sys.argv[1]
with open(path, 'rb') as f:
    components = plistlib.load(f)
for component in components:
    component['BundleIsRelocatable'] = False
    component['BundleOverwriteAction'] = 'upgrade'
with open(path, 'wb') as f:
    plistlib.dump(components, f)
PY
pkgbuild --root "$work/payload" --component-plist "$work/components.plist" \
    --identifier com.zfdang.voice-input-buddy.installer --version "$RELEASE_PACKAGE_VERSION" \
    --scripts "$work/scripts" --install-location / \
    "$root/dist/release/Voice_Input_Buddy_${RELEASE_TAG}_macOS_universal.pkg"
