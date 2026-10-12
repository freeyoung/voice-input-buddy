#!/usr/bin/env python3
"""Check every screenshot used by setup is included in an app resource directory."""
import re
import struct
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
resources = Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'Resources'
source = (root / 'Sources/VoiceInputBuddy/OnboardingView.swift').read_text()
names = set(re.findall(r'\.screenshot\("([\w-]+)"\)', source))
names.update(re.findall(r'onboardingGuideScreenshot\(\s*resourceName: "([\w-]+)"', source))
files = []
for name in sorted(names):
    files.append(resources / 'Onboarding' / f'{name}-light.png')
    dark = resources / 'Onboarding' / f'{name}-dark.png'
    # New local captures are light only; the view falls back to that real capture.
    if dark.exists() or name not in {'doubao-microphone', 'weixin-input-microphone'}:
        files.append(dark)
files.append(resources / 'BuddyRemoteIllustration.png')
for path in files:
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', f'Invalid PNG: {path}'
    width, height = struct.unpack('>II', data[16:24])
    assert width > 0 and height > 0, f'Empty image: {path}'
print(f'Verified {len(files)} setup and device images in {resources}')
