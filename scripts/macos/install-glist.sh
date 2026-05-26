version="0.4.0"
echo "Installation script version $version"

# ---- helper: pull values from metadata JSON ----
# jq-free, BSD-grep-friendly extraction. Each "key" maps to a JSON string field.
metadata_get() {
    local json="$1"
    local key="$2"
    printf '%s' "$json" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -1
}

# ---- args ----
skip_brew=false
for arg in "$@"; do
  case "$arg" in
    --skip-brew) skip_brew=true ;;
  esac
done

brew_prefix=""

# ---- sudo: prompt once, keep alive for the rest of the script ----
# Saves us from getting prompted again mid-install (e.g. before codesign).
sudo -v
( while true; do sudo -n true; sleep 60; kill -0 $$ 2>/dev/null || exit; done ) >/dev/null 2>&1 &
sudo_keeper_pid=$!
trap 'kill $sudo_keeper_pid 2>/dev/null' EXIT

# ---- macOS Gatekeeper ----
# Required so the ad-hoc-signed Eclipse + launcher .apps can be opened. Newer
# macOS versions changed the flag name; try both, ignore failures.
sudo spctl --master-disable 2>/dev/null || sudo spctl --global-disable 2>/dev/null || true

# ---- Xcode Command Line Tools (BEFORE brew, since Homebrew's installer would
# otherwise pop the GUI CLT installer itself) ----
# We only need CLT (clang, git, make) for cmake-driven builds. Full Xcode is
# only required for iOS targeting and is left to the user — install via
# `brew install xcodes && xcodes install --latest` if needed.
install_xcode_clt() {
    if xcode-select -p >/dev/null 2>&1 && [ -f "$(xcode-select -p)/usr/bin/clang" ]; then
        echo "Xcode Command Line Tools already installed"
        return 0
    fi

    echo "Installing Xcode Command Line Tools (this can take 5-15 minutes)..."

    # `softwareupdate` only lists CLT once this sentinel exists; the trick is
    # documented across e.g. Homebrew's own install script.
    sudo touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

    local pkg
    pkg=$(softwareupdate --list 2>&1 \
        | grep -E "\\*.*Command Line Tools" \
        | grep -E "macOS|$(sw_vers -productVersion | cut -d. -f1)" \
        | tail -1 \
        | sed -E 's/^[* ]*Label:[[:space:]]*//' \
        | sed -E 's/[[:space:]]+$//')

    if [ -z "$pkg" ]; then
        # Fall back: take the most recent listed CLT package.
        pkg=$(softwareupdate --list 2>&1 \
            | grep -E "\\*.*Command Line Tools" \
            | tail -1 \
            | sed -E 's/^[* ]*Label:[[:space:]]*//' \
            | sed -E 's/[[:space:]]+$//')
    fi

    if [ -n "$pkg" ]; then
        echo "Installing package: $pkg"
        sudo softwareupdate -i "$pkg" --verbose
        sudo rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    else
        # Last-resort: trigger GUI installer and poll until it completes.
        sudo rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
        echo "Could not find CLT in softwareupdate; triggering GUI installer."
        echo "Click 'Install' in the dialog and wait — this script will resume automatically."
        xcode-select --install 2>/dev/null || true
        local waited=0
        while ! xcode-select -p >/dev/null 2>&1; do
            sleep 5
            waited=$((waited + 5))
            if [ $waited -ge 1800 ]; then
                echo "Timed out waiting for CLT install (30 min). Re-run the script after installing manually."
                exit 1
            fi
        done
    fi
}
install_xcode_clt

# ---- brew ----
if ! $skip_brew; then
    if ! command -v brew >/dev/null 2>&1; then
        echo "Brew is not installed!"
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        # Fresh install won't be in PATH yet, init from known location
        if [[ "$(uname -m)" == "arm64" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        else
            eval "$(/usr/local/bin/brew shellenv)"
        fi
    else
        # Already installed, still need to init for this session
        eval "$(brew shellenv)"
    fi
    brew_prefix="$(brew --prefix)"
    brew install git openssl@3 cmake glew glfw glm freetype assimp curl wget pkg-config
else
    echo "Skipping Homebrew install step"
    if command -v brew >/dev/null 2>&1; then
        brew_prefix="$(brew --prefix)"
    fi
fi

# ---- dirs ----
mkdir -p ~/dev/glist
mkdir -p ~/dev/glist/zbin
mkdir -p ~/dev/glist/myglistapps

# ---- github user ----
# Override with GLIST_GITHUB_USERNAME=... for fully unattended runs.
if [ -n "${GLIST_GITHUB_USERNAME:-}" ]; then
    username="$GLIST_GITHUB_USERNAME"
    echo "Using GitHub username from env: $username"
elif [ -t 0 ]; then
    echo "Enter your GitHub Username (press enter to clone from the default repo): "
    read username
fi
[ -z "${username:-}" ] && username="GlistEngine"

# ---- clone repos ----
cd ~/dev/glist || exit 1
git clone https://github.com/$username/GlistEngine || exit 1

# ---- zbin ----
cd ~/dev/glist/zbin || exit 1

# Single universal zbin for both arm64 and Intel Macs. The bundled
# GlistEngine.app launcher is a universal Mach-O that dispatches to either
# eclipsecpp-arm64/ or eclipsecpp-x86_64/ based on `uname -m`.
DIR="glistzbin-macos"
META_URL="https://raw.githubusercontent.com/GlistEngine/InstallScripts/main/metadata/zbin-macos.json"

META_JSON=$(curl -fsSL "$META_URL") || { echo "Failed to fetch metadata"; exit 1; }
REPO=$(metadata_get "$META_JSON" repo)
PATTERN=$(metadata_get "$META_JSON" pattern)
META_VERSION=$(metadata_get "$META_JSON" version)
ZIP="$PATTERN"
ZBIN_URL="https://github.com/${REPO}/releases/download/${META_VERSION}/${PATTERN}"

if [ ! -f "$ZIP" ]; then
    echo "Downloading zbin: $ZBIN_URL"
    wget --no-check-certificate --tries=inf --retry-connrefused --waitretry=1 -O "$ZIP" "$ZBIN_URL" || exit 1
fi

if [ ! -d "$DIR" ]; then
    unzip "$ZIP" -x '__MACOSX/*' '.git/*'
else
    echo "Zbin already exists, skipping unzip"
fi

cd "$DIR/eclipse" || exit 1
sudo xattr -cr eclipsecpp-arm64/Eclipse.app eclipsecpp-x86_64/Eclipse.app GlistEngine.app
sudo codesign --force --deep --sign - eclipsecpp-arm64/Eclipse.app
sudo codesign --force --deep --sign - eclipsecpp-x86_64/Eclipse.app
sudo codesign --force --deep --sign - GlistEngine.app
sudo ln -sf "$(pwd)/GlistEngine.app" "/Applications/GlistEngine.app"

# ---- debug info ----
if [ -n "$brew_prefix" ]; then
    echo "OPENSSL VER:"
    ls "$brew_prefix/Cellar/openssl@3" 2>/dev/null || true

    echo "LLVM VER:"
    ls "$brew_prefix/Cellar/llvm" 2>/dev/null || true

    (echo; echo "export PATH=\$PATH:$brew_prefix/bin") >> ~/.zprofile
    export PATH="$PATH:$brew_prefix/bin"
fi

echo "Installation completed successfully!"
