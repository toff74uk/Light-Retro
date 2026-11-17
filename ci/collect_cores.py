import json, pathlib, shutil
root=pathlib.Path(__file__).resolve().parents[1]
for core in json.loads((root/'ci/cores.json').read_text()):
    name=core['name']; src=root/'build/core-artifacts'/f'core-{name}'
    if not (src/name).is_file() or not (src/'Info.plist').is_file(): raise SystemExit(f'Missing core artifact: {name}')
    shutil.copytree(src,root/'Frameworks'/f'{name}.framework',dirs_exist_ok=True)
