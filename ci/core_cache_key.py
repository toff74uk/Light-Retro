#!/usr/bin/env python3
"""Cache each engine by its own source, patches, build recipe and toolchain."""
import hashlib
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]


def fingerprint(core, root, toolchain):
    parts = [json.dumps(core, sort_keys=True).encode(), toolchain.strip().encode()]
    for relative in ['ci/build_core.py', 'ci/select_xcode.sh', *core.get('patches', [])]:
        parts.extend([relative.encode(), (root / relative).read_bytes()])
    digest = hashlib.sha256()
    for part in parts:
        digest.update(len(part).to_bytes(8, 'big'))
        digest.update(part)
    return digest.hexdigest()


def cache_key(core, root, toolchain):
    digest = fingerprint(core, root, toolchain)
    previous = json.loads((root / 'ci/verified_core_caches.json').read_text()).get(core['name'])
    if previous and previous['fingerprint'] == digest:
        return previous['key']
    return f"ios-arm64-v3-{core['name']}-{digest}"


if __name__ == '__main__':
    core = next(c for c in json.loads((ROOT / 'ci/cores.json').read_text()) if c['name'] == sys.argv[1])
    toolchain = subprocess.check_output(['xcodebuild', '-version'], text=True)
    print('key=' + cache_key(core, ROOT, toolchain))
