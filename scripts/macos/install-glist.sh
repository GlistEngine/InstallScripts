version="0.2.0"
echo "Installation script version $version"

# ---- args ----
skip_brew=false
for arg in "$@"; do
  case "$arg" in
    --skip-brew) skip_brew=true ;;
  esac
done

brew_prefix=""

# ---- brew ----
if ! $skip_brew; then
    if ! command -v brew >/dev/null 2>&1; then
        echo "Brew is not installed!"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    brew_prefix="$(brew --prefix)"
    eval "$("$brew_prefix/bin/brew" shellenv)"

    brew install git openssl@3 libomp llvm cmake glew glfw glm freetype assimp curl wget pkg-config
else
    echo "Skipping Homebrew install step"
    if command -v brew >/dev/null 2>&1; then
        brew_prefix="$(brew --prefix)"
    fi
fi

# ---- macOS stuff ----
sudo spctl --master-disable
xcode-select --install || true

# ---- dirs ----
mkdir -p ~/dev/glist
mkdir -p ~/dev/glist/zbin
mkdir -p ~/dev/glist/myglistapps

# ---- github user ----
echo "Enter your GitHub Username (press enter to clone from the default repo): "
read username
[ -z "$username" ] && username="GlistEngine"

# ---- clone repos ----
cd ~/dev/glist || exit 1
git clone https://github.com/$username/GlistEngine || exit 1

cd ~/dev/glist/myglistapps || exit 1
git clone https://github.com/$username/GlistApp || exit 1

# ---- zbin ----
cd ~/dev/glist/zbin || exit 1

if [[ "$(uname -m)" == "arm64" ]]; then
    ZIP="glistzbin-macos.zip"
    DIR="glistzbin-macos"
    URL_FILE="https://raw.githubusercontent.com/GlistEngine/InstallScripts/main/url/zbin-macos"
    ECLIPSE_FILE="https://raw.githubusercontent.com/GlistEngine/InstallScripts/main/url/eclipse-macos"
else
    ZIP="glistzbin-macos-x86_64.zip"
    DIR="glistzbin-macos-x86_64"
    URL_FILE="https://raw.githubusercontent.com/GlistEngine/InstallScripts/main/url/zbin-macos-intel"
    ECLIPSE_FILE="https://raw.githubusercontent.com/GlistEngine/InstallScripts/main/url/eclipse-macos-intel"
fi

if [ ! -f "$ZIP" ]; then
    echo "Downloading zbin"
    URL=$(curl -fsSL "$URL_FILE")
    wget --tries=inf --retry-connrefused --waitretry=1 -O "$ZIP" "$URL" || exit 1
fi

if [ ! -d "$DIR" ]; then
    unzip "$ZIP" -x '__MACOSX/*' '.git/*'
else
    echo "Zbin already exists, skipping unzip"
fi

ECLIPSE_FOLDER=$(curl -fsSL "$ECLIPSE_FILE")

cd "$DIR/eclipse/$ECLIPSE_FOLDER" || exit 1
sudo xattr -cr Eclipse.app
sudo codesign --force --deep --sign - Eclipse.app
sudo ln -sf "$(pwd)/Eclipse.app" "/Applications/GlistEngine Eclipse"

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
