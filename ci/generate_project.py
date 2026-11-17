#!/usr/bin/env python3
import json, os, pathlib, plistlib, subprocess
from verify_bundle import validate_build_version
root=pathlib.Path(__file__).resolve().parents[1]
spec=(root/'project.yml').read_text()
if os.environ.get('INCLUDE_CORES')=='1':
    entries=[]
    for core in json.loads((root/'ci/cores.json').read_text()):
        name=core['name']; framework=root/'Frameworks'/f'{name}.framework'
        if not (framework/name).is_file(): raise SystemExit(f'Missing required core: {name}')
        entries.append(f'      - framework: Frameworks/{name}.framework\n        embed: true\n        codeSign: true\n        link: false')
    spec=spec.replace('    dependencies:\n', '    dependencies:\n'+'\n'.join(entries)+'\n')
for key,default in [('BUNDLE_ID','com.lightretro.app'),('TEAM_ID',''),('BUILD_NUMBER','1')]:
    spec=spec.replace('${'+key+'}',os.environ.get(key) or default)
generated=root/'project.generated.yml'; generated.write_text(spec)
try:
    subprocess.run(['xcodegen','generate','--spec',str(generated)],cwd=root,check=True)
    validate_build_version(plistlib.loads((root/'build/Info.plist').read_bytes()), 'Generated app Info.plist')
finally: generated.unlink(missing_ok=True)
