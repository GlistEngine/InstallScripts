# zbin builders

Scripts that assemble the `glistzbin-*` release archives — i.e. the prebuilt
Eclipse bundles students download via the install scripts.

The point of these is reproducibility: if the layout/customisations drift, anyone
can rebuild a clean zbin from a vanilla upstream Eclipse plus the assets in this
folder, and get the same artefact.

## Layout

```
zbin-builders/
├── README.md                this file
├── assets/
│   ├── plugins/             extra Eclipse plugin JARs to drop in alongside CDT
│   │   ├── de.marw.cmake4eclipse.mbs_*.jar
│   │   ├── de.marw.cmake4eclipse.mbs.ui_*.jar
│   │   └── de.marw.cmakeed.assist_*.jar
│   └── splash/
│       ├── splash.png       custom 452x302 @ 72dpi (Retina-friendly)
│       └── splash.bmp       custom 452x302 (kept for the Windows builder)
├── build-macos.sh           assembles glistzbin-macos.zip (this doc)
└── dist/                    output zips (gitignored)
```

The wizard plugin itself is **not** vendored here — the builder compiles it
fresh from the [GlistWizards](https://github.com/GlistEngine/GlistWizards) repo
checkout. Pin a tag there if you want a reproducible build.

## build-macos.sh

Produces a single `glistzbin-macos.zip` that bundles both arm64 and x86_64
Eclipse installs side-by-side under one universal Mach-O launcher. The same
zip works on Apple Silicon and Intel Macs.

### Inputs

```bash
ECLIPSE_DMG_ARM64=...    # path to eclipse-cpp-*-macosx-cocoa-aarch64.dmg
ECLIPSE_DMG_X86_64=...   # path to eclipse-cpp-*-macosx-cocoa-x86_64.dmg
GLIST_WIZARDS_REPO=...   # path to GlistWizards checkout (default: ../../../../GlistWizards)
OUT_DIR=...              # where to drop the zip (default: ./dist)
```

DMGs can be downloaded from
<https://www.eclipse.org/downloads/packages/release/2025-12/m1/eclipse-ide-cc-developers>
(or whichever release you're targeting). Both arches must come from the same
release for the bundled plugins to match.

### Usage

```bash
cd ~/dev/glist/InstallScripts/tools/zbin-builders
export ECLIPSE_DMG_ARM64=~/Downloads/eclipse-cpp-2025-12-M1-macosx-cocoa-aarch64.dmg
export ECLIPSE_DMG_X86_64=~/Downloads/eclipse-cpp-2025-12-M1-macosx-cocoa-x86_64.dmg
./build-macos.sh
# -> dist/glistzbin-macos.zip
```

The first run takes ~3–5 minutes (mostly DMG extraction and zip compression).
Staging tree is kept under `./staging/` so you can poke around if something
looks off.

### What it does, step by step

1. Mounts both Eclipse DMGs, copies `Eclipse.app` into
   `staging/.../eclipsecpp-{arm64,x86_64}/`, detaches the DMGs.
2. Builds the wizard plugin JAR via `GlistWizards/build.sh`
   (uses Eclipse's own bundled JRE + plugin classpath — no separate Java needed).
3. For each Eclipse:
   - Drops the wizard JAR plus the three `de.marw.*` cmake4eclipse JARs into
     `Contents/Eclipse/plugins/`.
   - Adds matching lines to
     `Contents/Eclipse/configuration/org.eclipse.equinox.simpleconfigurator/bundles.info`
     (after stripping any pre-existing entries with the same symbolic name).
   - Replaces `splash.png` (in both the EPP common bundle and the platform
     bundle) and `splash.bmp` (EPP common only). The custom splash is shipped
     at 72 DPI so macOS NSImage renders it at the correct logical size.
4. Builds the universal Mach-O launcher
   (`clang -arch arm64 -arch x86_64`) from
   [`../launcher/glistengine-launcher.c`](../launcher/glistengine-launcher.c).
5. Assembles `GlistEngine.app` with the launcher binary,
   [`../launcher/launcher.sh`](../launcher/launcher.sh) (which sets arch-correct
   PATH and execs the right Eclipse), and
   [`../launcher/Info.plist`](../launcher/Info.plist).
6. Seeds a clean Eclipse workspace with `showIntro=false` so first launch lands
   directly in the workbench. No project bindings are pre-imported — the wizard
   plugin's startup hook discovers `~/dev/glist/GlistEngine/engine` and
   `~/dev/glist/myglistapps/*` at runtime and imports them on first boot.
7. Ad-hoc codesigns all three `.app` bundles
   (`codesign --force --deep --sign -`).
8. Zips `staging/glistzbin-macos/` into `dist/glistzbin-macos.zip`.

### Publishing a release

1. Bump `version` in `metadata/zbin-macos.json` to match the release tag.
2. Run `build-macos.sh`.
3. Upload `dist/glistzbin-macos.zip` as a GitHub release artefact on
   `GlistEngine/glistzbin-macos`.
4. The install script (`scripts/macos/install-glist.sh`) reads the JSON and
   downloads from the new release automatically — no install-script change
   needed.

## TODOs

- `build-win64.sh` — same pattern for `glistzbin-win64.zip`.
- `build-linux.sh` — same pattern for `glistzbin-linux.zip`.
