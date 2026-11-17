# Light Retro for iPhone

Native SwiftUI + libretro port (iOS 17 or newer) of Light Retro Android 2.10. Version 0.2 source candidate. Mac compilation and physical-device validation are still pending; this is not a tested TestFlight release.

[![Build iPhone app](https://github.com/toff74uk/Light-Retro/actions/workflows/ios.yml/badge.svg)](https://github.com/toff74uk/Light-Retro/actions/workflows/ios.yml)

**Start here: [Apple setup and TestFlight](START-HERE-iPhone.md).** No Mac is needed to use the GitHub build workflow.

## Included

- Native iPhone/iPad library in portrait and landscape, original Android Light Retro artwork, orange/blue/pink/yellow themes and left-handed navigation.
- Game import through Files, or persistent linked folders for local storage, USB drives and available file providers. Console ROMs must be uncompressed; arcade ZIPs remain intact. CD games use linked folders to preserve tracks.
- Search, favourites, recent games and player profiles. Battery saves and three manual save-state slots are isolated per player and game. Automatic states are saved on Save & Exit and when the app becomes inactive; resume is offered next time.
- Touch controls, up to four extended game controllers, controller navigation in the game library, controller test and an in-game pause shortcut (L1 + R1 + Start).
- MAME 0.289, Nintendo 64, NES, SNES, Mega Drive, PC Engine, PC Engine CD and FBNeo engines built from pinned source for arm64 iOS, bundled and signed with the application. No runtime core downloads or JIT.
- BIOS import, offline local games, open-source notices and automatic build checks.

## Current limits

SCUMM is deferred. MAME uses the same pinned 0.289 source as Android, with its portable C backend. N64 uses Mupen64Plus-Next, cached CPU interpretation and GLideN64 through an OpenGL ES 3 framebuffer. Both additions need a successful Mac build and device tests. No MAME-to-FBNeo fallback is made: the ROM sets differ. N64 and demanding arcade games may run slowly without JIT.

The first native version does not yet port the Android curated arcade categories, ROM matcher, artwork scraper, screensaver or Android app launcher/updater. Settings and Files pickers currently use touch; the library and gameplay accept controllers. Touch controls use RetroPad for most systems and an analogue stick, Z and C-buttons for N64, with no custom remapping yet. Linked cloud/NAS folders require the provider to make the files available locally; this is not a UPnP client. Emulator performance, audio routing, drive permissions and game compatibility need physical iPhone testing.

No commercial ROMs, BIOS images or personal credentials are included. The application makes no analytics, account or game-upload requests. Uninstalling the app removes local games and saves; back up **Files → On My iPhone → Light Retro → Saves**.

## Build

Every push runs native library/audio/video regression tests, compiles the iPhone application, builds the seven emulator cores from pinned source, then verifies a complete unsigned bundle. Nothing is uploaded to Apple automatically.

For a local Mac build with Xcode 26 and XcodeGen:

```sh
python3 ci/build_core.py fceumm
python3 ci/build_core.py snes9x
python3 ci/build_core.py genesis_plus_gx
python3 ci/build_core.py mednafen_pce_fast
python3 ci/build_core.py fbneo
python3 ci/build_core.py mamearcade
python3 ci/build_core.py mupen64plus_next
INCLUDE_CORES=1 BUNDLE_ID=com.lightretro.app BUILD_NUMBER=1 python3 ci/generate_project.py
open LightRetro.xcodeproj
```

Select your Apple team in Xcode before installing on a device. `INCLUDE_CORES=1` is mandatory for a playable build. Omitting it is only for compiling frontend changes; it does not produce a playable app. Core frameworks are device-only arm64, not simulator binaries.

Application source is GPL-3.0-or-later. Core and artwork licences are separate, with notices in `LightRetro/Resources/Licenses` and pinned corresponding source in `ci/cores.json`. Several cores have non-commercial restrictions; this beta is not a paid product. Public App Store release and broader distribution require a separate licence/review assessment. See [port notes](docs/PORT-NOTES.md).

## MAME and N64 checks

- MAME: link the whole ROM folder, preserving parent/BIOS ZIPs and `game/game.chd` companions. Launch the matching game ZIP. Test a small 2D game first, then a vertical game and a CHD game. Check Coin/Start and rotation. Some games cannot save states; exiting still lets the core flush its own NVRAM.
- N64: import an extracted `.z64`, `.v64` or `.n64` file. Test left-stick movement, right-stick C directions, left trigger Z, physical A (N64 A), physical X (N64 B), shoulders and Start. On touch controls, the STICK/D-PAD button switches the left control.
- Test pause/resume, save/load, background/foreground, portrait/landscape, disconnect/reconnect and four-player inputs on device. Check a second player profile retains independent saves.
- The first complete MAME build may take hours; CI allows six hours and caches the resulting framework.
