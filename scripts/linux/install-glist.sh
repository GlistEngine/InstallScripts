#!/bin/bash
version="0.2.0"
echo "Installation script version $version"

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
    echo "Unsupported package manager. Install dependencies manually."
    exit 1
fi

$UPDATE_CMD

# Install required packages
$PKG_INSTALL $PACKAGES || { echo "Failed to install core dependencies"; exit 1; }

# Install Vulkan support. Optional: without it the engine builds without
# GLIST_HAS_VULKAN and reports "Vulkan backend requested but Vulkan development
# support was not available" at run time, then uses OpenGL.
echo "Installing Vulkan support (optional, engine falls back to OpenGL without it)"
install_optional $VULKAN_PACKAGES

# Create directories
mkdir -p ~/dev/glist ~/dev/glist/zbin ~/dev/glist/myglistapps

# GitHub username
echo "Enter your GitHub Username (press enter to clone from the default repo): "
read username
username=${username:-GlistEngine}

# Clone repositories
cd ~/dev/glist
git clone https://github.com/$username/GlistEngine || { echo "Failed to clone GlistEngine"; exit 1; }
cd ~/dev/glist/myglistapps
git clone https://github.com/$username/GlistApp || { echo "Failed to clone GlistApp"; exit 1; }

# Download zbin
cd ~/dev/glist/zbin
ZIP_NAME="glistzbin-linux.zip"
URL=$(curl -s https://raw.githubusercontent.com/GlistEngine/InstallScripts/main/url/zbin-linux)
if [ ! -f "$ZIP_NAME" ]; then
    echo "Downloading zbin: $ZIP_NAME"
    wget -O "$ZIP_NAME" "$URL" || { echo "Failed to download zbin!"; exit 1; }
fi
UNZIP_DIR="${ZIP_NAME%.zip}"
if [ ! -d "$UNZIP_DIR" ]; then
    echo "Unzipping zbin"
    unzip "$ZIP_NAME" -x '__MACOSX/*' '.git/*'
else
    echo "Zbin already exists, skipping"
fi

# Create Eclipse shortcut
ECLIPSE_FOLDER=$(curl -s https://raw.githubusercontent.com/GlistEngine/InstallScripts/main/url/eclipse-linux)
ECLIPSE_DIR=~/dev/glist/zbin/glistzbin-linux/eclipse/$ECLIPSE_FOLDER
ECLIPSE_BIN="$ECLIPSE_DIR/eclipse"
ECLIPSE_ICON="$ECLIPSE_DIR/icon.xpm"
if [ -x "$ECLIPSE_BIN" ]; then
    echo "Creating desktop shortcut..."
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
echo "Installation completed successfully!"
