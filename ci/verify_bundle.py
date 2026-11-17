import json, pathlib, plistlib, subprocess, sys
root=pathlib.Path(__file__).resolve().parents[1];app=pathlib.Path(sys.argv[1])
for core in json.loads((root/'ci/cores.json').read_text()):
    name=core['name'];fw=app/'Frameworks'/f'{name}.framework'
    assert (fw/name).is_file(),f'Missing engine: {name}'
    info=plistlib.loads((fw/'Info.plist').read_bytes());assert info['CFBundleExecutable']==name
    result=subprocess.check_output(['lipo','-archs',str(fw/name)],text=True).strip();assert result=='arm64',result
    if '--signed' in sys.argv: subprocess.run(['codesign','--verify','--strict',str(fw)],check=True)
assert (app/'PrivacyInfo.xcprivacy').is_file(),'Missing privacy manifest'
assert (app/'Licenses').is_dir(),'Missing licences'
if '--signed' in sys.argv: subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print('Verified every bundled iPhone engine, privacy manifest and licence folder.')
