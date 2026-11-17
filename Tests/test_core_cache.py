import importlib.util
import json
import pathlib
import shutil
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('core_cache', ROOT / 'ci/core_cache_key.py')
cache = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache)
TOOLCHAIN = 'Xcode 26.3\nBuild version 17C529'


class CoreCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        shutil.copytree(ROOT / 'ci', self.root / 'ci')
        self.cores = {c['name']: c for c in json.loads((self.root / 'ci/cores.json').read_text())}

    def keys(self, toolchain=TOOLCHAIN):
        return {name: cache.cache_key(core, self.root, toolchain) for name, core in self.cores.items()}

    def test_successful_engines_reuse_exact_verified_caches(self):
        recorded = json.loads((self.root / 'ci/verified_core_caches.json').read_text())
        self.assertEqual(len(recorded), 6)
        keys = self.keys()
        for name, previous in recorded.items():
            self.assertEqual(keys[name], previous['key'])
        self.assertTrue(keys['mupen64plus_next'].startswith('ios-arm64-v3-'))

    def test_n64_patch_change_preserves_every_other_engine(self):
        before = self.keys()
        path = self.root / 'ci/patches/n64-libpng-apple.patch'
        path.write_text(path.read_text() + '\n')
        after = self.keys()
        self.assertEqual([name for name in before if before[name] != after[name]], ['mupen64plus_next'])

    def test_source_change_invalidates_only_that_engine(self):
        before = self.keys()
        self.cores['fceumm']['commit'] = '0' * 40
        after = self.keys()
        self.assertEqual([name for name in before if before[name] != after[name]], ['fceumm'])

    def test_shared_recipe_change_invalidates_all_engines(self):
        before = self.keys()
        path = self.root / 'ci/build_core.py'
        path.write_text(path.read_text() + '\n')
        after = self.keys()
        self.assertTrue(all(before[name] != after[name] for name in before))

    def test_toolchain_change_invalidates_all_engines(self):
        before = self.keys()
        after = self.keys(TOOLCHAIN + '-updated')
        self.assertTrue(all(before[name] != after[name] for name in before))


if __name__ == '__main__':
    unittest.main()
