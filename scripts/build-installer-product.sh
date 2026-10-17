#!/bin/bash
# Wrap a component in Installer's standard pre-install Read Me flow.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
component="${1:?Component package is required}"
output="${2:?Output package is required}"
work="$(mktemp -d "$root/.build/installer-product.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cp "$component" "$work/VoiceInputBuddyPayload.pkg"
productbuild --synthesize --package "$work/VoiceInputBuddyPayload.pkg" "$work/Distribution.xml"
python3 - "$work/Distribution.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET
path = sys.argv[1]
tree = ET.parse(path)
root = tree.getroot()
ET.SubElement(root, 'title').text = 'Voice Input Buddy'
ET.SubElement(root, 'readme', {'file': 'ReadMe.html'})
# Synthesized package URLs must resolve inside package-path, not a temp path.
for ref in root.findall('pkg-ref'):
    if ref.text and ref.text.strip():
        ref.text = 'VoiceInputBuddyPayload.pkg'
tree.write(path, encoding='utf-8', xml_declaration=True)
PY
productbuild --distribution "$work/Distribution.xml" --resources "$root/scripts/installer-resources" \
    --package-path "$work" "$output"
