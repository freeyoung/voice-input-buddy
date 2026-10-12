#!/usr/bin/env python3
"""Generate validated bundled phrases from the single editable Markdown source."""
import json
from pathlib import Path
import sys


def generate(text):
    section = None
    phrases = []
    defaults = {}
    buttons = {'OK': 'ok', '左': 'left', '上': 'up', '右': 'right', '下': 'down'}
    for line in text.splitlines():
        if line.startswith('## '):
            section = line[3:].strip()
        if not line.startswith('|'):
            continue
        cells = [value.strip() for value in line.strip().strip('|').split('|')]
        if section == '常用语表':
            if cells[0] == '#' or all(set(c) <= set('-:') for c in cells):
                continue
            if len(cells) != 5 or not all(cells) or not cells[0].isdigit() or int(cells[0]) != len(phrases) + 1:
                raise ValueError('Phrase rows must contain five nonempty columns and consecutive numbers')
            number, zh, zh_label, en, en_label = cells
            if max(len(zh), len(en)) > 4000 or max(len(zh_label), len(en_label)) > 80:
                raise ValueError('Phrase text or label is too long')
            phrases.append(dict(id=f'builtin-{int(number):03}', chineseText=zh, chineseLabel=zh_label,
                                englishText=en, englishLabel=en_label))
        elif section == '默认键位':
            if cells[0] == '按键' or all(set(c) <= set('-:') for c in cells):
                continue
            if len(cells) != 3 or cells[0] not in buttons or not cells[1].isdigit():
                raise ValueError('Invalid default binding row')
            button = buttons[cells[0]]
            index = int(cells[1]) - 1
            if button in defaults or index not in range(min(5, len(phrases))) or cells[2] != phrases[index]['chineseText']:
                raise ValueError('Duplicate, unknown or inconsistent default binding')
            defaults[button] = phrases[index]['id']
    if not 5 <= len(phrases) <= 500 or set(defaults) != set(buttons.values()) or len(set(defaults.values())) != 5:
        raise ValueError('Missing phrases or defaults')
    return dict(schemaVersion=1, entries=phrases, bindings=defaults, builtInIDs=[p['id'] for p in phrases])


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Usage: generate-common-phrases.py INPUT.md OUTPUT.json')
    source, destination = map(Path, sys.argv[1:])
    destination.write_text(json.dumps(generate(source.read_text()), ensure_ascii=False, indent=2) + '\n')
