import os, pathlib, plistlib, re
required=['BUNDLE_ID','TEAM_ID','ASC_KEY_ID','ASC_ISSUER_ID','ASC_KEY_P8']
missing=[key for key in required if not os.environ.get(key)]
if missing: raise SystemExit('Add repository secrets first: '+', '.join('APPLE_TEAM_ID' if key=='TEAM_ID' else key for key in missing)+'. See START-HERE-iPhone.md.')
if not re.fullmatch(r'[A-Z0-9]+',os.environ['ASC_KEY_ID']): raise SystemExit('Invalid API key ID format.')
if not re.fullmatch(r'[A-Za-z0-9.-]+',os.environ['BUNDLE_ID']): raise SystemExit('Invalid bundle ID format.')
if 'PRIVATE KEY' not in os.environ['ASC_KEY_P8']: raise SystemExit('ASC_KEY_P8 must contain the complete .p8 file.')
directory=pathlib.Path(os.environ['RUNNER_TEMP'])/'light-retro-keys';directory.mkdir(mode=0o700,exist_ok=True)
key=directory/f'AuthKey_{os.environ["ASC_KEY_ID"]}.p8'
key.write_text(os.environ['ASC_KEY_P8']);key.chmod(0o600)
with open(os.environ['GITHUB_ENV'],'a') as env: env.write(f'KEY_PATH={key}\n')
pathlib.Path('build').mkdir(exist_ok=True)
pathlib.Path('build/ExportOptions.plist').write_bytes(plistlib.dumps({
 'method':'app-store-connect','destination':'upload','signingStyle':'automatic','teamID':os.environ['TEAM_ID'],
 'manageAppVersionAndBuildNumber':False,'uploadSymbols':True
}))
