#!/usr/bin/env python3
"""Build pinned, interpreter-only iOS cores as signable frameworks."""
import json, os, pathlib, plistlib, shlex, shutil, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parents[1]
MIN_IOS = '17.0'
def run(*args, cwd=None): subprocess.run(args, cwd=cwd, check=True)

def update_submodules(core, src):
    # N64's unused native RSP backend contains an orphan gnulib gitlink.
    # Its interpreter/HLE build uses only files in the pinned main repository.
    if core.get('submodules', True):
        run('git','-C',str(src),'submodule','update','--init','--recursive','--depth','1')

def build_command(core, sdk, cpu_count):
    args=['make','-f',core['makefile'],'-j',str(min(cpu_count or 2,core.get('jobs',4))), 'platform=ios-arm64']
    target=f'-target arm64-apple-ios{MIN_IOS} -isysroot {shlex.quote(sdk)}'
    if core.get('builder')=='mame':
        # GENie is a host executable. Do not cross-compile its CC/CXX overrides.
        required={'FORCE_DRC_C_BACKEND=1','NOASM=1','TARGET=mame','SUBTARGET=arcade'}
        if not required.issubset(core.get('make_args',[])):
            raise ValueError('The read/write-only MAME cache requires the C interpreter backend')
        args += [f'ARCHOPTS={target} -arch arm64 -miphoneos-version-min={MIN_IOS}']
    else:
        args += [f'CC=xcrun --sdk iphoneos clang {target}', f'CXX=xcrun --sdk iphoneos clang++ {target}',
                 f'IOSSDK={sdk}',f'MINVERSION=-miphoneos-version-min={MIN_IOS}',f'IPHONEMINVER=-miphoneos-version-min={MIN_IOS}']
    return args+core.get('make_args',[])

def collect_licences(core, src, destination):
    destination.mkdir(parents=True,exist_ok=True)
    name=core['name']
    for p in src.rglob('*'):
        if p.is_file() and '.git' not in p.parts and p.suffix not in ('.pl','.py','.sh') and ('license' in p.name.lower() or 'copying' in p.name.lower()) and p.stat().st_size<300000:
            shutil.copy2(p,destination/(name+'-'+str(p.relative_to(src)).replace('/','-')))
    patches='\n'.join(core.get('patches',[])) or 'None'
    (destination/(name+'-SOURCE.txt')).write_text(f"{name}\n{core['license']}\nExact upstream source:\n{core['repo'].removesuffix('.git')}/tree/{core['commit']}\nLight Retro patches (part of corresponding source):\n{patches}\nBuild recipe: ci/build_core.py and ci/cores.json\n")

def main(name):
    core=next(c for c in json.loads((ROOT/'ci/cores.json').read_text()) if c['name']==name)
    src=ROOT/'.cores'/name; src.mkdir(parents=True,exist_ok=True)
    if not (src/'.git').exists(): run('git','init',str(src))
    run('git','-C',str(src),'fetch','--depth','1',core['repo'],core['commit'])
    run('git','-C',str(src),'checkout','--detach','FETCH_HEAD')
    update_submodules(core, src)
    assert subprocess.check_output(['git','-C',str(src),'rev-parse','HEAD'],text=True).strip()==core['commit']
    for patch in core.get('patches',[]):
        patch_path=str(ROOT/patch)
        # Permit rerunning an identical recipe without applying a patch twice.
        if subprocess.run(['git','apply','--reverse','--check',patch_path],cwd=src,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode!=0:
            run('git','apply','--check',patch_path,cwd=src)
            run('git','apply',patch_path,cwd=src)
    sdk=subprocess.check_output(['xcrun','--sdk','iphoneos','--show-sdk-path'],text=True).strip()
    directory=src/core['directory']
    run(*build_command(core,sdk,os.cpu_count()),cwd=directory)
    binary=directory/core.get('output',f'{name}_libretro_ios.dylib')
    if not binary.exists(): raise RuntimeError(f'Expected core missing: {binary}')
    framework=ROOT/'Frameworks'/f'{name}.framework'; framework.mkdir(parents=True,exist_ok=True)
    shutil.copy2(binary,framework/name)
    run('install_name_tool','-id',f'@rpath/{name}.framework/{name}',str(framework/name))
    dependencies=subprocess.check_output(['otool','-L',str(framework/name)],text=True)
    for line in dependencies.splitlines()[1:]:
        dep=line.strip().split(' (')[0]
        if not dep.startswith(('@rpath/','/usr/lib/','/System/Library/')): raise RuntimeError(f'Unexpected runtime dependency: {dep}')
    info={'CFBundleExecutable':name,'CFBundleIdentifier':f'com.lightretro.core.{name.replace("_","-")}',
          'CFBundleName':name,'CFBundlePackageType':'FMWK','CFBundleShortVersionString':'1.0',
          'CFBundleVersion':'1','CFBundleSupportedPlatforms':['iPhoneOS'],'MinimumOSVersion':MIN_IOS}
    (framework/'Info.plist').write_bytes(plistlib.dumps(info))
    collect_licences(core,src,ROOT/'LightRetro/Resources/Licenses')
    print(f'Built {name} at {core["commit"]}')

if __name__=='__main__': main(sys.argv[1])
