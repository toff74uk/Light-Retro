import json
import pathlib
import plistlib
import re
import subprocess
import sys


def validate_build_version(info, bundle):
    version = info.get('CFBundleVersion')
    if not isinstance(version, str) or not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', version):
        raise ValueError(
            f'{bundle}: CFBundleVersion must be a non-empty string of one to three '
            f'period-separated integers; got {version!r} ({type(version).__name__}).'
        )


def verify_bundle(app, signed=False):
    root = pathlib.Path(__file__).resolve().parents[1]
    validate_build_version(plistlib.loads((app / 'Info.plist').read_bytes()), app.name)
    for core in json.loads((root / 'ci/cores.json').read_text()):
        name = core['name']
        fw = app / 'Frameworks' / f'{name}.framework'
        assert (fw / name).is_file(), f'Missing engine: {name}'
        info = plistlib.loads((fw / 'Info.plist').read_bytes())
        validate_build_version(info, fw.name)
        assert info['CFBundleExecutable'] == name
        result = subprocess.check_output(['lipo', '-archs', str(fw / name)], text=True).strip()
        assert result == 'arm64', result
        if signed:
            subprocess.run(['codesign', '--verify', '--strict', str(fw)], check=True)
    catalogue = app / 'Catalogue'
    assert len(json.loads((catalogue / 'mame-titles.json').read_text())) == 31122, 'Missing Android MAME names'
    assert len(json.loads((catalogue / 'fbneo-titles.json').read_text())) == 8436, 'Missing Android FBNeo names'
    boards = json.loads((catalogue / 'fbneo-boards.json').read_text())
    assert len(set().union(*boards.values())) == 1839, 'Missing Android FBNeo routing data'
    assert len(json.loads((catalogue / 'collections.json').read_text())) == 11, 'Missing arcade, SNES or Mega Drive curated collections'
    assert (app / 'PrivacyInfo.xcprivacy').is_file(), 'Missing privacy manifest'
    assert (app / 'Licenses').is_dir(), 'Missing licences'
    if signed:
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    print('Verified bundle versions, every bundled iPhone engine, privacy manifest and licence folder.')


if __name__ == '__main__':
    verify_bundle(pathlib.Path(sys.argv[1]), signed='--signed' in sys.argv)
