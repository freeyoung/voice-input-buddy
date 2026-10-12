#!/usr/bin/env python3
"""Publish the localized text assets consumed by the in-app update panel."""
import os
from pathlib import Path

root = Path(__file__).resolve().parent.parent
tag = os.environ['RELEASE_TAG']
output = root / 'dist/release'
output.mkdir(parents=True, exist_ok=True)
for language, lines in {
    'en': [f'Voice Input Buddy {tag}',
           'Download the installer matching your Mac: arm64 for Apple Silicon, intel for Intel.',
           'The installer includes the app and Voice Input Buddy Mic driver.',
           'A separate uninstall PKG removes the app, driver and personal data by default.',
           f'Full release details: https://github.com/zfdang/voice-input-buddy/releases/tag/{tag}'],
    'zh': [f'语音搭子 {tag}',
           '请下载对应架构的安装包：Apple Silicon 选择 arm64，Intel 选择 intel。',
           '安装包包含程序及 Voice Input Buddy Mic 虚拟麦克风驱动。',
           '独立卸载 PKG 默认删除程序、驱动和当前用户的个人数据。',
           f'完整版本说明：https://github.com/zfdang/voice-input-buddy/releases/tag/{tag}']
}.items():
    (output / f'Voice_Input_Buddy_{tag}.{language}.txt').write_text('\n'.join(lines) + '\n', encoding='utf-8')
