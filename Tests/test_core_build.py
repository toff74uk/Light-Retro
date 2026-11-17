import importlib.util, json, pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('build_core',ROOT/'ci/build_core.py')
build=importlib.util.module_from_spec(spec);spec.loader.exec_module(build)
CORES={core['name']:core for core in json.loads((ROOT/'ci/cores.json').read_text())}
class CoreBuildTests(unittest.TestCase):
    def test_mame_c_backend_cannot_be_removed(self):
        core=dict(CORES['mamearcade']); core['make_args']=['TARGET=mame','SUBTARGET=arcade']
        with self.assertRaises(ValueError): build.build_command(core,'/sdk',4)
    def test_mame_keeps_host_compiler_and_arcade_target(self):
        cmd=build.build_command(CORES['mamearcade'],'/sdk',16)
        self.assertFalse(any(a.startswith(('CC=','CXX=','SOURCEFILTER=')) for a in cmd))
        self.assertIn('SUBTARGET=arcade',cmd);self.assertEqual(cmd[cmd.index('-j')+1],'2')
        self.assertTrue(any('arm64-apple-ios17.0' in a for a in cmd))
    def test_n64_no_native_recompilers_or_vulkan(self):
        cmd=build.build_command(CORES['mupen64plus_next'],'/SDK with space',8)
        for flag in ['WITH_DYNAREC=','HAVE_PARALLEL_RSP=0','HAVE_PARALLEL_RDP=0','HAVE_THR_AL=0','LLE=0','FORCE_GLES3=1','EGL=0']:
            self.assertIn(flag,cmd)
        self.assertTrue(any("-isysroot '/SDK with space'" in a for a in cmd))
    def test_every_core_is_pinned_and_patch_present(self):
        self.assertEqual(len(CORES),7)
        for core in CORES.values():
            self.assertRegex(core['commit'],r'^[0-9a-f]{40}$')
            for patch in core.get('patches',[]):self.assertTrue((ROOT/patch).is_file())
    def test_worker_limit_on_small_machine(self):
        cmd=build.build_command(CORES['mupen64plus_next'],'/sdk',1)
        self.assertEqual(cmd[cmd.index('-j')+1],'1')
if __name__=='__main__':unittest.main()
