#!/bin/bash
# Assemble a publishable glistzbin-macos.zip.
#
# Inputs (env vars or positional):
#   ECLIPSE_DMG_ARM64    Path to eclipse-cpp-*-macosx-cocoa-aarch64.dmg
#   ECLIPSE_DMG_X86_64   Path to eclipse-cpp-*-macosx-cocoa-x86_64.dmg
#   GLIST_WIZARDS_REPO   Path to the GlistWizards repo checkout (default: ../../../../GlistWizards)
#   OUT_DIR              Where to drop the zip (default: ./dist)
#
# Produces $OUT_DIR/glistzbin-macos.zip with this layout:
#   glistzbin-macos/
#     LICENSE
#     eclipse/
#       eclipsecpp-arm64/Eclipse.app/
#       eclipsecpp-x86_64/Eclipse.app/
#       GlistEngine.app/                    (universal Mach-O launcher)
#       workspace/                          (clean, no project bindings)
#
# Requires: macOS host with Xcode CLT (clang, codesign, hdiutil, sips), zip.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
TOOLS_ROOT="$(cd "$HERE/.." && pwd -P)"           # InstallScripts/tools
INSTALL_SCRIPTS_ROOT="$(cd "$TOOLS_ROOT/.." && pwd -P)"

ECLIPSE_DMG_ARM64="${ECLIPSE_DMG_ARM64:-${1:-}}"
ECLIPSE_DMG_X86_64="${ECLIPSE_DMG_X86_64:-${2:-}}"
GLIST_PLUGINS_REPO="${GLIST_PLUGINS_REPO:-${GLIST_WIZARDS_REPO:-$INSTALL_SCRIPTS_ROOT/../Eclipse-Plugins}}"
OUT_DIR="${OUT_DIR:-$HERE/dist}"
STAGING="${STAGING:-$HERE/staging}"

die() { echo "ERROR: $*" >&2; exit 1; }
[[ -f "$ECLIPSE_DMG_ARM64"  ]] || die "ECLIPSE_DMG_ARM64 not set or missing: $ECLIPSE_DMG_ARM64"
[[ -f "$ECLIPSE_DMG_X86_64" ]] || die "ECLIPSE_DMG_X86_64 not set or missing: $ECLIPSE_DMG_X86_64"
[[ -d "$GLIST_PLUGINS_REPO" ]] || die "GLIST_PLUGINS_REPO not set or missing: $GLIST_PLUGINS_REPO"
[[ -x "$GLIST_PLUGINS_REPO/build.sh" ]] || die "$GLIST_PLUGINS_REPO/build.sh not executable"

LAUNCHER_SRC="$TOOLS_ROOT/launcher/glistengine-launcher.c"
LAUNCHER_SH="$TOOLS_ROOT/launcher/launcher.sh"
LAUNCHER_PLIST="$TOOLS_ROOT/launcher/Info.plist"
ASSETS_PLUGINS="$HERE/assets/plugins"
ASSETS_SPLASH_PNG="$HERE/assets/splash/splash.png"
ASSETS_SPLASH_BMP="$HERE/assets/splash/splash.bmp"

echo "== Cleaning staging =="
rm -rf "$STAGING"
mkdir -p "$STAGING/glistzbin-macos/eclipse"
ZBIN_ROOT="$STAGING/glistzbin-macos"
ECLIPSE_DIR="$ZBIN_ROOT/eclipse"

extract_dmg() {
    local dmg="$1" dest="$2"
    local mnt
    mnt="$(mktemp -d)"
    echo "  Mounting $dmg"
    hdiutil attach -nobrowse -mountpoint "$mnt" "$dmg" >/dev/null
    mkdir -p "$dest"
    cp -R "$mnt/Eclipse.app" "$dest/"
    hdiutil detach "$mnt" -quiet
    rmdir "$mnt"
}

echo "== Extracting Eclipses =="
extract_dmg "$ECLIPSE_DMG_ARM64"  "$ECLIPSE_DIR/eclipsecpp-arm64"
extract_dmg "$ECLIPSE_DMG_X86_64" "$ECLIPSE_DIR/eclipsecpp-x86_64"

echo "== Building plugin JARs =="
ECLIPSE_HOME="$ECLIPSE_DIR/eclipsecpp-arm64/Eclipse.app/Contents/Eclipse" \
    "$GLIST_PLUGINS_REPO/build.sh"
# Discover every <symbolic-name>_<version>.jar the build script produced.
PLUGIN_JARS=()
for plugin_dir in "$GLIST_PLUGINS_REPO"/*/; do
    while IFS= read -r -d '' jar; do
        PLUGIN_JARS+=("$jar")
    done < <(find "$plugin_dir" -maxdepth 1 -name "*_*.jar" -print0)
done
[[ ${#PLUGIN_JARS[@]} -gt 0 ]] || die "$GLIST_PLUGINS_REPO/build.sh did not produce any JARs"
for jar in "${PLUGIN_JARS[@]}"; do
    echo "  -> $(basename "$jar")"
done

customize_eclipse() {
    local eclipse_root="$1"     # .../eclipsecpp-<arch>/Eclipse.app
    local contents="$eclipse_root/Contents/Eclipse"

    # 1. Drop in our plugin JARs (built from Eclipse-Plugins/ + vendored assets).
    for jar in "${PLUGIN_JARS[@]}"; do
        cp "$jar" "$contents/plugins/"
    done
    cp "$ASSETS_PLUGINS"/*.jar "$contents/plugins/"

    # 2. Register them in bundles.info. Strip any pre-existing entry with the
    #    same symbolic name first so we don't ship duplicates.
    local bundles="$contents/configuration/org.eclipse.equinox.simpleconfigurator/bundles.info"
    local purge_file
    purge_file=$(mktemp)
    {
        for jar in "${PLUGIN_JARS[@]}" "$ASSETS_PLUGINS"/*.jar; do
            basename "$jar" | sed 's/_[^_]*$//'
        done
    } > "$purge_file"
    awk -F, 'NR==FNR{purge[$0]=1; next} !purge[$1]' \
        "$purge_file" "$bundles" > "$bundles.tmp"
    mv "$bundles.tmp" "$bundles"
    rm -f "$purge_file"

    for jar in "${PLUGIN_JARS[@]}" "$ASSETS_PLUGINS"/*.jar; do
        local n sym ver
        n=$(basename "$jar")
        # e.g. com.aitial.glist.wizards_1.3.0.202605271026.jar
        sym="${n%_*}"
        ver="${n#*_}"; ver="${ver%.jar}"
        printf "%s,%s,plugins/%s,4,false\n" "$sym" "$ver" "$n" >> "$bundles"
    done

    # 3. Replace splash images (PNG in both common + platform; BMP in common
    #    for the rare case someone runs this Eclipse on Windows).
    local common platform
    common=$(ls -d "$contents"/plugins/org.eclipse.epp.package.common_*)
    platform=$(ls -d "$contents"/plugins/org.eclipse.platform_*)
    # Back up originals once (idempotent).
    [[ -f "$common/splash-eclipse.bmp"   ]] || cp "$common/splash.bmp"   "$common/splash-eclipse.bmp"   2>/dev/null || true
    [[ -f "$platform/splash-eclipse.png" ]] || cp "$platform/splash.png" "$platform/splash-eclipse.png" 2>/dev/null || true
    cp "$ASSETS_SPLASH_PNG" "$common/splash.png"
    cp "$ASSETS_SPLASH_PNG" "$platform/splash.png"
    cp "$ASSETS_SPLASH_BMP" "$common/splash.bmp"

    # Progress rect is left at the upstream default (2,290,448,10) because the
    # splash is 452x302; nothing to adjust.
}

echo "== Customising Eclipses =="
customize_eclipse "$ECLIPSE_DIR/eclipsecpp-arm64/Eclipse.app"
customize_eclipse "$ECLIPSE_DIR/eclipsecpp-x86_64/Eclipse.app"

echo "== Building universal launcher binary =="
clang -arch arm64 -arch x86_64 -O2 -mmacosx-version-min=11.0 \
    "$LAUNCHER_SRC" -o "$STAGING/launcher-binary"

echo "== Assembling GlistEngine.app =="
APP="$ECLIPSE_DIR/GlistEngine.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$LAUNCHER_PLIST" "$APP/Contents/Info.plist"
cp "$STAGING/launcher-binary" "$APP/Contents/MacOS/launcher"
cp "$LAUNCHER_SH" "$APP/Contents/MacOS/launcher.sh"
chmod +x "$APP/Contents/MacOS/launcher" "$APP/Contents/MacOS/launcher.sh"
# Icon: reuse Eclipse's icon if no custom one was provided.
cp "$ECLIPSE_DIR/eclipsecpp-arm64/Eclipse.app/Contents/Resources/Eclipse.icns" \
   "$APP/Contents/Resources/glistengine.icns"

echo "== Seeding clean workspace =="
WS="$ECLIPSE_DIR/workspace"
mkdir -p "$WS/.metadata/.plugins/org.eclipse.core.runtime/.settings"
cat > "$WS/.metadata/.plugins/org.eclipse.core.runtime/.settings/org.eclipse.ui.prefs" <<'EOF'
eclipse.preferences.version=1
showIntro=false
EOF
cat > "$WS/.metadata/.plugins/org.eclipse.core.runtime/.settings/org.eclipse.ui.ide.prefs" <<'EOF'
eclipse.preferences.version=1
IMPORT_FILES_AND_FOLDERS_RELATIVE=true
quickStart=false
tipsAndTricks=false
EOF

# Mirror every plugin's source into the workspace (matches Windows convention,
# lets curious users browse/modify the plugins from inside the IDE).
for plugin_dir in "$GLIST_PLUGINS_REPO"/*/; do
    [[ -f "$plugin_dir/META-INF/MANIFEST.MF" ]] || continue
    name=$(basename "${plugin_dir%/}")
    ws_src="$WS/$name"
    mkdir -p "$ws_src"
    cp -R "$plugin_dir/META-INF" "$ws_src/"
    cp -R "$plugin_dir/src"      "$ws_src/"
    [[ -d "$plugin_dir/icons"    ]] && cp -R "$plugin_dir/icons"    "$ws_src/"
    [[ -d "$plugin_dir/OSGI-INF" ]] && cp -R "$plugin_dir/OSGI-INF" "$ws_src/"
    [[ -d "$plugin_dir/.settings" ]] && cp -R "$plugin_dir/.settings" "$ws_src/"
    cp "$plugin_dir/plugin.xml"        "$ws_src/" 2>/dev/null || true
    cp "$plugin_dir/build.properties"  "$ws_src/" 2>/dev/null || true
    cp "$plugin_dir/.project"          "$ws_src/" 2>/dev/null || true
    cp "$plugin_dir/.classpath"        "$ws_src/" 2>/dev/null || true
done

echo "== Ad-hoc signing =="
xattr -cr "$ECLIPSE_DIR/eclipsecpp-arm64/Eclipse.app" \
          "$ECLIPSE_DIR/eclipsecpp-x86_64/Eclipse.app" \
          "$APP"
codesign --force --deep --sign - "$ECLIPSE_DIR/eclipsecpp-arm64/Eclipse.app"  >/dev/null
codesign --force --deep --sign - "$ECLIPSE_DIR/eclipsecpp-x86_64/Eclipse.app" >/dev/null
codesign --force --deep --sign - "$APP"                                        >/dev/null

# Drop a LICENSE alongside if one exists upstream (mirrors the legacy zbin).
if [[ -f "$INSTALL_SCRIPTS_ROOT/../GlistEngine/LICENSE" ]]; then
    cp "$INSTALL_SCRIPTS_ROOT/../GlistEngine/LICENSE" "$ZBIN_ROOT/LICENSE"
fi

echo "== Packaging zip =="
mkdir -p "$OUT_DIR"
ZIP_PATH="$OUT_DIR/glistzbin-macos.zip"
rm -f "$ZIP_PATH"
( cd "$STAGING" && zip -qry "$ZIP_PATH" glistzbin-macos -x '*.DS_Store' '__MACOSX/*' )

echo
echo "Built $ZIP_PATH ($(du -h "$ZIP_PATH" | awk '{print $1}'))"
echo "Staging tree left under $STAGING for inspection."
