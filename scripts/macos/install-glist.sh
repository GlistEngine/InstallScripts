version="0.5.0"
echo "Installation script version $version"

# ---- helper: pull values from metadata JSON ----
# jq-free, BSD-grep-friendly extraction. Each "key" maps to a JSON string field.
metadata_get() {
    local json="$1"
    local key="$2"
    printf '%s' "$json" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -1
}

# ---- args ----
# Each can also come from the environment, for runs that cannot pass flags
# (Glist Studio sets them):
#   --skip-brew                                      leave Homebrew and its packages alone
#   --github-user NAME   GLIST_GITHUB_USERNAME=NAME  clone NAME's forks (default: GlistEngine)
#   --unattended         GLIST_UNATTENDED=1          ask nothing; sudo may still ask for a password
#   --no-eclipse         GLIST_NO_ECLIPSE=1          skip Eclipse: no Gatekeeper change, signing or /Applications link
skip_brew=false
username="${GLIST_GITHUB_USERNAME:-}"
unattended="${GLIST_UNATTENDED:-}"
no_eclipse="${GLIST_NO_ECLIPSE:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-brew) skip_brew=true ;;
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

brew_prefix=""

clt_installed() {
    xcode-select -p >/dev/null 2>&1 && [ -f "$(xcode-select -p)/usr/bin/clang" ]
}

# ---- sudo: prompt once, keep alive for the rest of the script ----
# Saves us from getting prompted again mid-install (e.g. before codesign). Only
# needed for the Command Line Tools, a first Homebrew install and Eclipse, so a
# Mac that has the first two and skips Eclipse is not asked for a password.
if ! clt_installed || { ! $skip_brew && ! command -v brew >/dev/null 2>&1; } || [ -z "$no_eclipse" ]; then
    sudo -v || fail "Administrator access is needed"
    ( while true; do sudo -n true; sleep 60; kill -0 $$ 2>/dev/null || exit; done ) >/dev/null 2>&1 &
    sudo_keeper_pid=$!
    trap 'kill $sudo_keeper_pid 2>/dev/null' EXIT
fi

# ---- Xcode Command Line Tools (BEFORE brew, since Homebrew's installer would
# otherwise pop the GUI CLT installer itself) ----
# We only need CLT (clang, git, make) for cmake-driven builds. Full Xcode is
# only required for iOS targeting and is left to the user — install via
# `brew install xcodes && xcodes install --latest` if needed.
install_xcode_clt() {
    if clt_installed; then
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
                fail "Timed out waiting for the Command Line Tools (30 min). Install them, then run this again."
            fi
        done
    fi
}
step "Xcode Command Line Tools"
install_xcode_clt

# ---- brew ----
step "Homebrew and libraries"
if ! $skip_brew; then
    if ! command -v brew >/dev/null 2>&1; then
        echo "Brew is not installed!"
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || fail "Could not install Homebrew"
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
    brew install git openssl@3 cmake glew glfw glm freetype assimp curl wget pkg-config ninja vulkan-loader vulkan-headers molten-vk vulkan-tools shaderc glslang \
        || fail "Could not install the Homebrew packages"
else
    echo "Skipping Homebrew install step"
    if command -v brew >/dev/null 2>&1; then
        brew_prefix="$(brew --prefix)"
    fi
fi

if [ -n "$brew_prefix" ]; then
    echo "OPENSSL VER:"
    ls "$brew_prefix/Cellar/openssl@3" 2>/dev/null || true

    echo "LLVM VER:"
    ls "$brew_prefix/Cellar/llvm" 2>/dev/null || true

    # Once, rather than a new line on every run.
    if ! grep -qs "export PATH=\$PATH:$brew_prefix/bin" ~/.zprofile; then
        (echo; echo "export PATH=\$PATH:$brew_prefix/bin") >> ~/.zprofile
    fi
    export PATH="$PATH:$brew_prefix/bin"
fi

# ---- dirs ----
step "Folders"
mkdir -p ~/dev/glist ~/dev/glist/zbin ~/dev/glist/myglistapps || fail "Could not create ~/dev/glist"

# ---- github user ----
if [ -z "$username" ] && [ -z "$unattended" ] && [ -t 0 ]; then
    echo "Enter your GitHub Username (press enter to clone from the default repo): "
    read username
fi
[ -z "${username:-}" ] && username="GlistEngine"
echo "Cloning from: $username"

# ---- clone repos ----
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

# ---- zbin ----
step "Glist tools (zbin)"
cd ~/dev/glist/zbin || fail "Could not open ~/dev/glist/zbin"

# Single universal zbin for both arm64 and Intel Macs. The bundled
# GlistEngine.app launcher is a universal Mach-O that dispatches to either
# eclipsecpp-arm64/ or eclipsecpp-x86_64/ based on `uname -m`.
DIR="glistzbin-macos"
META_URL="https://raw.githubusercontent.com/GlistEngine/InstallScripts/main/metadata/zbin-macos.json"

META_JSON=$(curl -fsSL "$META_URL") || fail "Could not fetch the zbin metadata"
REPO=$(metadata_get "$META_JSON" repo)
PATTERN=$(metadata_get "$META_JSON" pattern)
META_VERSION=$(metadata_get "$META_JSON" version)
ZIP="$PATTERN"
ZBIN_URL="https://github.com/${REPO}/releases/download/${META_VERSION}/${PATTERN}"

if [ ! -f "$ZIP" ]; then
    echo "Downloading zbin: $ZBIN_URL"
    wget --no-check-certificate --tries=inf --retry-connrefused --waitretry=1 -O "$ZIP" "$ZBIN_URL" || fail "Could not download the zbin"
fi

if [ ! -d "$DIR" ]; then
    unzip -q "$ZIP" -x '__MACOSX/*' '.git/*' || fail "Could not unzip the zbin"
else
    echo "Zbin already exists, skipping unzip"
fi

# ---- Eclipse ----
step "Eclipse"
if [ -n "$no_eclipse" ]; then
    echo "Skipped (--no-eclipse)"
else
    # Required so the ad-hoc-signed Eclipse + launcher .apps can be opened. Newer
    # macOS versions changed the flag name; try both, ignore failures.
    sudo spctl --master-disable 2>/dev/null || sudo spctl --global-disable 2>/dev/null || true

    cd "$DIR/eclipse" || fail "Could not open the zbin's eclipse folder"
    sudo xattr -cr eclipsecpp-arm64/Eclipse.app eclipsecpp-x86_64/Eclipse.app GlistEngine.app
    sudo codesign --force --deep --sign - eclipsecpp-arm64/Eclipse.app
    sudo codesign --force --deep --sign - eclipsecpp-x86_64/Eclipse.app
    sudo codesign --force --deep --sign - GlistEngine.app
    sudo ln -sf "$(pwd)/GlistEngine.app" "/Applications/GlistEngine.app"
fi

echo ""
echo "==> Done: Glist Engine is installed in ~/dev/glist"
