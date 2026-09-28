#!/bin/bash
version="0.3.0"
echo "Installation script version $version"

# ---- options ----
# Each can also come from the environment, for runs that cannot pass flags
# (Glist Studio sets them):
#   --github-user NAME   GLIST_GITHUB_USERNAME=NAME  clone NAME's forks (default: GlistEngine)
#   --unattended         GLIST_UNATTENDED=1          ask nothing; sudo may still ask for a password
#   --no-eclipse         GLIST_NO_ECLIPSE=1          skip the Eclipse shortcut
username="${GLIST_GITHUB_USERNAME:-}"
unattended="${GLIST_UNATTENDED:-}"
no_eclipse="${GLIST_NO_ECLIPSE:-}"
while [ $# -gt 0 ]; do
    case "$1" in
        --github-user) username="$2"; shift ;;
        --unattended) unattended=1 ;;
        --no-eclipse) no_eclipse=1 ;;
    esac
    shift
done

# Unattended, git fails on a repository it cannot read instead of asking for a login.
[ -n "$unattended" ] && export GIT_TERMINAL_PROMPT=0

# ---- progress ----
# Steps print as "==> [n/total] name", and the run ends with "==> Done: ..." or
# "==> Failed: ...", the same in all three installers, so a front end can follow.
step_total=7
step_index=0
step() {
    step_index=$((step_index + 1))
    echo ""
    echo "==> [$step_index/$step_total] $*"
}
fail() {
    echo "==> Failed: $*"
    exit 1
}

# Pulls a string field out of the metadata JSON without needing jq.
metadata_get() {
    printf '%s' "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -1
}

# Installs a list of packages one at a time, skipping any that the current
# release does not carry. Used for the Vulkan set, which is optional: the engine
# falls back to OpenGL when the development files are absent, so a package that
# is missing on an older distro must not abort the whole install the way a
# single batch transaction would.
install_optional() {
    for pkg in "$@"; do
        if $PKG_INSTALL "$pkg" >/dev/null 2>&1; then
            echo "  installed: $pkg"
        else
            echo "  skipped (unavailable on this release): $pkg"
        fi
    done
}

step "System packages"

# Determine package manager
if command -v apt >/dev/null; then
    PKG_INSTALL="sudo apt install -y"
    UPDATE_CMD="sudo apt update"
    PACKAGES="git cmake clang-14 libstdc++-12-dev libglew-dev curl libcurl4-openssl-dev libssl-dev build-essential openssl libomp-dev llvm libglfw3-dev libglm-dev libfreetype6-dev libassimp-dev wget pkg-config unzip"
    # Vulkan: loader+headers for find_package(Vulkan), mesa ICD, validation
    # layers for Debug, glslang for GVK_RUNTIME_GLSLANG, shaderc for hot
    # reload, glslc for the gVKShaders.h regeneration target.
    # glslc is a separate binary package and is absent before Ubuntu 23.04 /
    # Debian bookworm, which is why this set is installed non-fatally.
    VULKAN_PACKAGES="libvulkan-dev vulkan-tools mesa-vulkan-drivers vulkan-validationlayers libglslang-dev glslang-tools libshaderc-dev glslc"

elif command -v pacman >/dev/null; then
    PKG_INSTALL="sudo pacman -S --needed --noconfirm"
    # -Syu (not -Sy) to avoid partial-upgrade breakage on Arch; this does a full system upgrade
    UPDATE_CMD="sudo pacman -Syu --noconfirm"
    # Arch bundles dev headers into the main package, so no separate -dev packages.
    # base-devel replaces build-essential; pkgconf provides pkg-config; openmp provides libomp.
    PACKAGES="git cmake clang gcc glew curl openssl base-devel openmp llvm glfw glm freetype2 assimp wget pkgconf unzip"
    # shaderc ships both libshaderc and glslc on Arch.
    VULKAN_PACKAGES="vulkan-headers vulkan-icd-loader vulkan-tools vulkan-validation-layers vulkan-mesa-layers mesa glslang shaderc"

elif command -v yum >/dev/null; then
    PKG_INSTALL="sudo yum install -y"
    UPDATE_CMD="sudo yum update"
    PACKAGES="git cmake clang gcc-c++ glew-devel libcurl-devel openssl-devel openssl libomp-devel llvm glfw-devel glm-devel freetype-devel assimp-devel wget pkgconf-pkg-config unzip"
    VULKAN_PACKAGES="vulkan-loader-devel vulkan-headers vulkan-tools mesa-vulkan-drivers vulkan-validation-layers glslang-devel libshaderc-devel"

else
    fail "Unsupported package manager. Install the dependencies manually."
fi

$UPDATE_CMD

# Install required packages
$PKG_INSTALL $PACKAGES || fail "Could not install the required packages"

# Install Vulkan support. Optional: without it the engine builds without
# GLIST_HAS_VULKAN and reports "Vulkan backend requested but Vulkan development
# support was not available" at run time, then uses OpenGL.
step "Vulkan support (optional, the engine falls back to OpenGL without it)"
install_optional $VULKAN_PACKAGES

step "Folders"
mkdir -p ~/dev/glist ~/dev/glist/zbin ~/dev/glist/myglistapps || fail "Could not create ~/dev/glist"

# GitHub username
if [ -z "$username" ] && [ -z "$unattended" ] && [ -t 0 ]; then
    echo "Enter your GitHub Username (press enter to clone from the default repo): "
    read username
fi
username=${username:-GlistEngine}

step "GlistEngine"
cd ~/dev/glist || fail "Could not open ~/dev/glist"
if [ -d GlistEngine ]; then
    echo "GlistEngine already exists, skipping"
else
    git clone "https://github.com/$username/GlistEngine" || fail "Could not clone GlistEngine from $username"
fi

step "GlistApp"
cd ~/dev/glist/myglistapps || fail "Could not open ~/dev/glist/myglistapps"
if [ -d GlistApp ]; then
    echo "GlistApp already exists, skipping"
else
    git clone "https://github.com/$username/GlistApp" || fail "Could not clone GlistApp from $username"
fi

step "Glist tools (zbin)"
cd ~/dev/glist/zbin || fail "Could not open ~/dev/glist/zbin"
META_URL="https://raw.githubusercontent.com/GlistEngine/InstallScripts/main/metadata/zbin-linux.json"
META_JSON=$(curl -fsSL "$META_URL") || fail "Could not fetch the zbin metadata"
REPO=$(metadata_get "$META_JSON" repo)
PATTERN=$(metadata_get "$META_JSON" pattern)
META_VERSION=$(metadata_get "$META_JSON" version)
ECLIPSE_FOLDER=$(metadata_get "$META_JSON" eclipse_folder)
ZBIN_URL="https://github.com/${REPO}/releases/download/${META_VERSION}/${PATTERN}"
UNZIP_DIR="glistzbin-linux"
if [ ! -f "$PATTERN" ]; then
    echo "Downloading zbin: $ZBIN_URL"
    wget -O "$PATTERN" "$ZBIN_URL" || fail "Could not download the zbin"
fi
if [ ! -d "$UNZIP_DIR" ]; then
    echo "Unzipping zbin"
    unzip -q "$PATTERN" -x '__MACOSX/*' '.git/*' || fail "Could not unzip the zbin"
else
    echo "Zbin already exists, skipping"
fi

step "Eclipse shortcut"
ECLIPSE_DIR=~/dev/glist/zbin/$UNZIP_DIR/eclipse/$ECLIPSE_FOLDER
ECLIPSE_BIN="$ECLIPSE_DIR/eclipse"
ECLIPSE_ICON="$ECLIPSE_DIR/icon.xpm"
if [ -n "$no_eclipse" ]; then
    echo "Skipped (--no-eclipse)"
elif [ -x "$ECLIPSE_BIN" ]; then
    DESKTOP_FILE=~/.local/share/applications/glistengine-eclipse.desktop
    mkdir -p "$(dirname "$DESKTOP_FILE")"
    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=GlistEngine Eclipse
Exec=$ECLIPSE_BIN
Icon=$ECLIPSE_ICON
Type=Application
Categories=Development;IDE;
Terminal=false
EOF
    chmod +x "$DESKTOP_FILE"
    echo "Shortcut created at $DESKTOP_FILE"
else
    echo "Eclipse binary not found, skipping shortcut creation."
fi

# Report what the Vulkan backend will actually be able to do. find_package(Vulkan)
# only needs the headers and loader, so the engine can configure with Vulkan
# enabled and still find no device at run time if no ICD is installed.
echo ""
echo "Checking Vulkan setup:"
if command -v vulkaninfo >/dev/null; then
    if vulkaninfo --summary >/dev/null 2>&1; then
        echo "  driver: OK"
    else
        echo "  driver: loader is installed but no working ICD was found."
        echo "          On NVIDIA proprietary the ICD ships with the driver package"
        echo "          (nvidia-driver / nvidia-utils), not with mesa-vulkan-drivers."
    fi
else
    echo "  driver: vulkaninfo not installed, skipping check."
fi
if command -v glslc >/dev/null; then
    echo "  glslc:  OK (gVKShaders.h will be regenerated when shaders change)"
else
    echo "  glslc:  not found, the committed SPIR-V in core/gVKShaders.h will be used as-is"
fi
if pkg-config --exists shaderc 2>/dev/null; then
    echo "  shaderc: OK (Vulkan shader hot reload available in Debug builds)"
else
    echo "  shaderc: not found, Vulkan shaders come from the committed SPIR-V"
fi

echo ""
echo "==> Done: Glist Engine is installed in ~/dev/glist"
