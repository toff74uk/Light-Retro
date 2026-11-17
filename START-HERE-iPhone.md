# Light Retro → your iPhone

The code and build workflow are in this repository. You supply the Apple account details directly to GitHub; do not put keys in a commit or send them in chat.

## 1. Create Light Retro in Apple

In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list), register a new explicit App ID for **Light Retro**. Suggested bundle ID: `com.lightretro.app`. Use a different unique ID if that is unavailable. Keep it separate from Light Media.

In [App Store Connect](https://appstoreconnect.apple.com/), open My Apps → + → New App. Select iOS, name **Light Retro**, your language, that bundle ID, and a SKU such as `light-retro-ios`. Complete any required agreements. The app does not need to be publicly released to use TestFlight.

## 2. Add five repository secrets

Open [Light Retro → Settings → Secrets and variables → Actions](https://github.com/toff74uk/Light-Retro/settings/secrets/actions) and choose **New repository secret** for each row.

| Secret name | Value |
| --- | --- |
| `BUNDLE_ID` | The exact Light Retro bundle ID you just registered, e.g. `com.lightretro.app` |
| `APPLE_TEAM_ID` | Your 10-character Apple Developer Team ID |
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | The API key issuer ID |
| `ASC_KEY_P8` | Complete text of the downloaded `.p8` key, including BEGIN and END lines |

You can use the same eligible team/API key as Light Media. Secrets belong to each GitHub repository, so they must also be added here. **BUNDLE_ID must be Light Retro's own ID.** The workflow uses automatic signing with the API key; the key needs permissions for signing and uploading (a team Admin key is the straightforward option). No Android signing key is used.

An account that cannot create cloud signing certificates may need its signing permissions adjusted in Apple Developer/App Store Connect. Do not delete or revoke certificates used by Light Media; this workflow does not revoke account certificates.

## 3. Build and upload

Open [Actions → Build iPhone app](https://github.com/toff74uk/Light-Retro/actions/workflows/ios.yml). First check that the latest automatic build is green.

Choose **Run workflow**, select `main`, tick **Sign and upload to TestFlight**, then run. The first engine builds can take a while; subsequent runs reuse compiled-core caches. The build number advances automatically.

The workflow first runs tests, compiles the app and all engines, checks the full bundle, then signs and uploads. It stops before uploading if required secrets or a core are missing. Apple then processes the build. In App Store Connect → Light Retro → TestFlight, complete any prompts and add yourself as an internal tester. External testing may require Beta App Review.

## 4. First device check

1. Install from TestFlight and add a small known-good NES or Mega Drive ROM you own. Console ZIPs should be unzipped in Files first.
2. Check picture, sound, touch controls and your Razer/Bluetooth controller. L1 + R1 + Start opens the pause menu; a Pause button is also always at the top.
3. Save to slot 1, restart the game, load slot 1, then Save & Exit. Reopen and choose Resume saved game.
4. Switch to another player and check that game saves and favourites are separate.
5. Test an external folder, then disconnect/reconnect it. Test backgrounding the app, audio interruptions, portrait and landscape.
6. For PC Engine CD, import your `syscard3.pce`, then link the whole disc folder. For FBNeo, use a compatible set with any parent/BIOS ZIPs beside it.

MAME 0.289 and N64 are included in the 0.2 source candidate and still require Mac compilation and device checks. SCUMM is deferred. Follow the MAME/N64 checks in README.md after the smaller console test. Compilation is not proof that every game works; keep your existing saves backed up during beta testing.
