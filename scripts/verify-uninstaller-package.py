#!/usr/bin/env python3
"""Expand the uninstall package and validate choices and scripts without executing them."""
from pathlib import Path
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

package = Path(sys.argv[1])
root = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory() as directory:
    expanded = Path(directory) / 'expanded'
    subprocess.run(['pkgutil', '--expand-full', str(package), str(expanded)], check=True)
    distribution = ET.parse(expanded / 'Distribution')
    assert set(distribution.find('options').get('hostArchitectures').split(',')) == {'arm64', 'x86_64'}
    for element in ['welcome', 'readme', 'conclusion']:
        document = distribution.find(element)
        assert document is not None
        content = (expanded / 'Resources' / document.get('file')).read_text()
        assert '卸载' in content and 'install' in content.lower()
    choices = {choice.get('id'): choice for choice in distribution.findall('choice')}
    assert choices['system'].get('selected') == 'true'
    assert choices['system'].get('enabled') == 'false'
    assert choices['data'].get('start_selected') == 'true'
    for component in ['system', 'data']:
        info = ET.parse(expanded / f'{component}.pkg/PackageInfo')
        assert info.find('payload') is None or info.find('payload').get('numberOfFiles') == '0'
        scripts = expanded / f'{component}.pkg/Scripts'
        for file in scripts.iterdir():
            subprocess.run(['bash', '-n', str(file)], check=True)
        for name in ['installation-common.sh', 'installer-common.sh', 'uninstall-user.sh']:
            source = root / name if name == 'installation-common.sh' else root / 'uninstaller' / name
            assert (scripts / name).read_bytes() == source.read_bytes()
        for name in (['preinstall', 'postinstall', 'uninstall-system.sh'] if component == 'system' else ['postinstall']):
            source = root / 'uninstaller' / ('cleanup-postinstall' if component == 'data' else name)
            assert (scripts / name).read_bytes() == source.read_bytes()
print(f'Verified universal uninstall PKG: no payload, required system removal, optional data removal selected by default.')
