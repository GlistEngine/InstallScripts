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
GLIST_WIZARDS_REPO="${GLIST_WIZARDS_REPO:-$INSTALL_SCRIPTS_ROOT/../GlistWizards}"
OUT_DIR="${OUT_DIR:-$HERE/dist}"
STAGING="${STAGING:-$HERE/staging}"

die() { echo "ERROR: $*" >&2; exit 1; }
[[ -f "$ECLIPSE_DMG_ARM64"  ]] || die "ECLIPSE_DMG_ARM64 not set or missing: $ECLIPSE_DMG_ARM64"
[[ -f "$ECLIPSE_DMG_X86_64" ]] || die "ECLIPSE_DMG_X86_64 not set or missing: $ECLIPSE_DMG_X86_64"
[[ -d "$GLIST_WIZARDS_REPO" ]] || die "GLIST_WIZARDS_REPO not set or missing: $GLIST_WIZARDS_REPO"
[[ -x "$GLIST_WIZARDS_REPO/build.sh" ]] || die "GlistWizards/build.sh not executable"

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

echo "== Building wizard JAR =="
ECLIPSE_HOME="$ECLIPSE_DIR/eclipsecpp-arm64/Eclipse.app/Contents/Eclipse" \
    "$GLIST_WIZARDS_REPO/build.sh"
WIZARD_JAR=$(ls "$GLIST_WIZARDS_REPO"/com.aitial.glist.wizards_*.jar | tail -1)
[[ -f "$WIZARD_JAR" ]] || die "build.sh did not produce a JAR"
WIZARD_JAR_NAME=$(basename "$WIZARD_JAR")
WIZARD_VERSION=$(echo "$WIZARD_JAR_NAME" | sed 's/^com.aitial.glist.wizards_//; s/\.jar$//')
echo "  Wizard $WIZARD_VERSION -> $WIZARD_JAR_NAME"

customize_eclipse() {
    local eclipse_root="$1"     # .../eclipsecpp-<arch>/Eclipse.app
    local contents="$eclipse_root/Contents/Eclipse"

    # 1. Drop in our plugin JARs.
    cp "$WIZARD_JAR" "$contents/plugins/"
    cp "$ASSETS_PLUGINS"/*.jar "$contents/plugins/"

    # 2. Register them in bundles.info.
    local bundles="$contents/configuration/org.eclipse.equinox.simpleconfigurator/bundles.info"
    grep -v "^com.aitial.glist.wizards," "$bundles" > "$bundles.tmp"
    grep -v "^de.marw\." "$bundles.tmp" > "$bundles.tmp2"
    mv "$bundles.tmp2" "$bundles"; rm "$bundles.tmp"
    printf "com.aitial.glist.wizards,%s,plugins/%s,4,false\n" \
        "$WIZARD_VERSION" "$WIZARD_JAR_NAME" >> "$bundles"
    for jar in "$ASSETS_PLUGINS"/*.jar; do
        local n
        n=$(basename "$jar")
        local sym ver
        # e.g. de.marw.cmake4eclipse.mbs_3.0.2.202510221825.jar
        sym="${n%_*}"
        ver="${n#*_}"; ver="${ver%.jar}"
        local start_level=4
        printf "%s,%s,plugins/%s,%d,false\n" \
            "$sym" "$ver" "$n" "$start_level" >> "$bundles"
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

# Mirror the wizard sources into the workspace (matches Windows convention,
# lets curious users browse/modify the plugin from inside the IDE).
WS_SRC="$WS/com.aitial.glist.wizards"
mkdir -p "$WS_SRC"
cp -R "$GLIST_WIZARDS_REPO/META-INF" "$WS_SRC/"
cp -R "$GLIST_WIZARDS_REPO/icons"    "$WS_SRC/"
cp -R "$GLIST_WIZARDS_REPO/src"      "$WS_SRC/"
cp    "$GLIST_WIZARDS_REPO/.project"      "$WS_SRC/" 2>/dev/null || true
cp    "$GLIST_WIZARDS_REPO/.classpath"    "$WS_SRC/" 2>/dev/null || true
cp    "$GLIST_WIZARDS_REPO/build.properties" "$WS_SRC/"
cp    "$GLIST_WIZARDS_REPO/plugin.xml"       "$WS_SRC/"
[[ -d "$GLIST_WIZARDS_REPO/.settings" ]] && cp -R "$GLIST_WIZARDS_REPO/.settings" "$WS_SRC/"

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
