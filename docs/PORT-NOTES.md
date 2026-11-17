# Port provenance and implementation

Android baseline inspected: **Light-Retro-2.10-Full-Source.zip**, package `com.lightretro.app`, release notes dated 23 October 2026. The Kotlin/Java UI, Android document permissions, LibretroDroid JNI runtime and Android `.so` binaries cannot be used as iOS executables.

This repository replaces them with SwiftUI, iOS security-scoped folder bookmarks, GameController, an Objective-C++ libretro host, CoreGraphics software video, an OpenGL ES 3 hardware surface and AVAudioEngine PCM output. The native runtime is built for iOS arm64 from the exact upstream revisions recorded in `ci/cores.json`. Android icon, wordmark and system artwork are reused with the source project's notices. The app is open source under the baseline's GPL-3.0-or-later licence.

| Android component | iPhone implementation |
| --- | --- |
| System list / library | SwiftUI grid and system rail; compact horizontal rail in portrait |
| Storage Access Framework / USB | Files picker, persistent folder bookmarks held throughout a play session |
| Library scan | Recursive system-specific scan, BIOS/support filtering, stable game IDs on rescan |
| Favourites / profiles | Codable JSON with atomic writes; independent profile favourites, recents, theme and saves |
| LibretroDroid | Native libretro callback host, signed bundled iOS frameworks |
| Audio/video | Single-producer audio ring, AVAudioEngine conversion, pixel formats 0RGB1555/RGB565/XRGB8888 |
| Gamepad | GameController RetroPad mapping, four ports, digital and analogue input, N64 touch stick/C-buttons, pause chord |
| Saves | Battery RAM, three manual states, automatic state on exit/inactivity, manual resume |
| APK updater | GitHub build + manual App Store Connect/TestFlight upload |

The host deliberately returns false for unsupported libretro environment extensions instead of claiming they work. Software video handles MAME geometry/rotation updates. N64 requests an ES3 context and receives an offscreen framebuffer, GL symbol lookup and context reset/destruction callbacks. Presentation blits to a CAEAGLLayer and restores framebuffer/renderbuffer/scissor state. N64 CPU interpretation, HLE RSP and single-threaded GLideN64 are fixed frontend options; no option editor is included. The build excludes the native CPU/RSP recompilers, Vulkan and Angrylion. MAME keeps the Android 0.289 revision and forces its C backend. The accompanying cache patch keeps interpreted instruction storage read/write and suppresses executable memory transitions; the recipe refuses the patch configuration without FORCE_DRC_C_BACKEND=1 and NOASM=1.

Core source is fetched at exact commits and built with the iOS SDK, then each dylib is placed in its own framework with a bundle ID and install name. Xcode embeds and signs each framework. The bundle validation script checks that all required engines, licences and the privacy manifest are present, and checks signatures for the TestFlight archive. No core can be downloaded after installation.

The N64 recipe skips submodules because its disabled native RSP backend contains a gnulib gitlink without a submodule URL. The selected interpreter/HLE sources are tracked in the main repository. PC Engine and N64 carry a small zlib header patch that limits the classic Mac `fdopen` fallback to non-Apple targets, preserving the real iOS SDK declaration.

N64's bundled libpng likewise selects standard `math.h` on modern Apple platforms instead of the classic Mac `fp.h` header. Engine caches are keyed independently by each engine's pinned manifest entry, patches, shared build recipe and selected Xcode version. The six successful engine builds from run 44146344722 are reused only when those inputs match their recorded fingerprints; an N64-only patch no longer discards the MAME build.

## Validation

- `Tests/main.swift`: system recognition, support-file exclusions, path traversal rejection, stable IDs on rescan and profile persistence/isolation.
- `Tests/frame_audio.cpp`: RGB conversion including row pitch and bounds, channel ordering, audio underrun and ring capacity/wraparound.
- `Tests/analog_input.cpp`: signed axes, clamping, invalid indices/values, port isolation and clearing. Passed locally with ASan/UBSan.
- `Tests/test_core_build.py`: pinned build policy and no-JIT flags. Passed locally; the upstream N64 makefile also resolved to 275 source files without native recompilers or Vulkan.
- GitHub Actions runs native iPhone compilation, source compilation of every bundled core and complete bundle verification. Check the latest run for results; successful source compilation alone does not establish device compatibility.
- Device-only behavior remains unverified until TestFlight installation: game compatibility and speed, physical controllers, touch combinations, audio interruptions, USB/cloud file-provider permissions, automatic state restore, and memory pressure.

### Save/resume device regression

Create an automatic save with recognisable progress. Reopen the game and, before choosing Resume or Start fresh, switch apps and return, then exit from the pause menu. Reopen again and confirm Resume restores the original progress. Repeat with N64, whose core completes initialization on its first frame. Also load a manual slot from the initial resume menu, play, exit and confirm the next automatic resume uses that new session. The frontend preserves an awaiting automatic save and initializes a core before serialization or restoration; this sequence still requires device verification.

Reference implementation/docs: [libretro iOS build guidance](https://docs.libretro.com/development/retroarch/compilation/ios/), [libretro API header](https://github.com/libretro/libretro-fceumm/tree/77468e568d9fe9c48d684ca911f1a3fe7259fdf7/src/drivers/libretro/libretro-common/include), [Apple GameController](https://developer.apple.com/documentation/gamecontroller), [Apple review guidelines](https://developer.apple.com/app-store/review/guidelines/).
