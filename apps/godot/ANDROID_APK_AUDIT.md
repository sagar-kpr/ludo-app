# Android release APK size and architecture audit

Inspected 2026-10-25: `dist-android/rally-ludo-release.apk`, built from commit
`4b16a12`. APK size: **87.8 MiB**. This is an investigation; export settings,
dependencies, assets, gameplay and the signed APK were not changed.

## Measured package contents

Sizes below are ZIP entry sizes, in MiB (1,048,576 bytes).

| Component | Packaged size | Finding |
| --- | ---: | --- |
| `libgodot_android.so` | 66.02 | Official precompiled release engine |
| `liblkjingle_peerconnection_so.so` | 11.23 | Required LiveKit WebRTC library |
| `libc++_shared.so` | 1.20 | Shared native runtime |
| Godot assets and scripts | 4.53 | Includes dynamically discovered avatars |
| `classes.dex` and `classes2.dex` | 4.33 | Compressed Java/Kotlin bytecode |

The native libraries total 78.45 MiB, approximately 89% of the APK. All three
are stored uncompressed. ELF inspection with `readelf -SW` found no `.debug_*`,
`.symtab` or `.strtab` sections; stripping debug information again is not a
meaningful optimization here. No tests, environment files, signing passwords or
keystores were found in the APK.

The project uses Gradle release export with the official Godot 4.6.1 template.
The media plugin uses `compileOnly` for Godot, avoiding a second bundled engine,
and LiveKit Android 2.23.5. The plugin's release AAR disables its own minification;
that fact alone does not demonstrate that any particular packaged class is unused.

## Assets

The 1.85 MiB imported texture for `assets/art/woodland-table-v1.png` is packaged
because the preset exports all resources. A source search found no runtime
reference to its filename or `assets/art/`; the only reference is its artwork
documentation. It is a candidate for export exclusion, rather than source deletion,
after checking the current menu and board visually. Maximum expected saving from
this texture alone is about 1.85 MiB.

Keep all avatar images: `scripts/avatar_catalog.gd` discovers them at runtime with
`DirAccess.get_files_at()`. Switching blindly to an export mode based on static
scene references could remove selectable avatars. There are 13 packaged avatar
texture imports. The board and dice use procedural rendering and 3D nodes, so
disabling the engine's 3D subsystem would break the game.

## Packaging versus engine optimization

A raw ZIP-deflate experiment on the existing native binaries produced these
sizes without changing their contents:

| Library | Deflated estimate |
| --- | ---: |
| Godot | 22.18 MiB |
| WebRTC | 5.34 MiB |
| C++ runtime | 0.38 MiB |

Replacing only native ZIP storage would suggest roughly **37.2 MiB** total.
This is an estimate, not a built, signed or tested APK. Do not manually recompress
the signed APK. Godot exposes `gradle_build/compress_native_libraries` for a proper
export. Compression trades a smaller APK for extracted native-library storage and
potential startup cost; it does not shrink the engine or guarantee a smaller
installed app. Keep the present release unchanged until a separate compressed
export has passed installation, cold-start, gameplay and two-way media tests.

Further engine reduction requires custom release templates and a reviewed build
profile. Preserve 3D rendering, GDScript, GUI, shaders, image loaders, TLS,
WebSocket networking and Android plugin integration. Any feature-pruned template
requires full regression and physical-device testing. No size saving is claimed
for an unbuilt custom template. Similarly, evaluate bytecode shrinking separately
with plugin/JNI keep rules and media tests; do not remove WebRTC or codecs based
only on APK size.

## Architecture support

`export_presets.cfg` enables `arm64-v8a` and disables `armeabi-v7a`. Inspection
confirms that the final APK contains **only ARM64** native libraries. Minimum SDK
is 24; target SDK is 35. This APK is not a native 32-bit ARM or x86/x86_64 build.
Use an ARM64 Android environment to test this artifact; do not rely on emulator
architecture translation.

Both the installed Godot release AAR and the resolved WebRTC
`android-prefixed:137.7151.05` AAR contain `arm64-v8a`, `armeabi-v7a`, `x86` and
`x86_64` binaries. The packaging limitation comes from the current export selection,
not missing ABI binaries in those two dependencies. This does not establish
runtime compatibility on those other architectures; each still needs its own build
and device/emulator verification.

For broader distribution, prefer separate ABI APKs for direct downloads or a
multi-ABI Android App Bundle for Play delivery, rather than inflating the current
direct-download APK with every ABI. Additional packages were not requested or built
as part of this audit. Physical-device/emulator gameplay and media tests were not
run in this investigation.

## Relevant implementation and documentation

- `export_presets.cfg`: resource export policy and selected architecture.
- `android-plugin/rally-media/build.gradle.kts`: LiveKit dependency and plugin build.
- `scripts/avatar_catalog.gd`: runtime avatar discovery.
- `scripts/board.gd`, `scripts/dice.gd`: required 3D rendering.
- [Godot Android export settings](https://docs.godotengine.org/en/stable/classes/class_editorexportplatformandroid.html)
- [Godot engine size optimization](https://docs.godotengine.org/en/stable/engine_details/development/compiling/optimizing_for_size.html)
- [Android native-library packaging trade-offs](https://developer.android.com/guide/practices/page-sizes)
