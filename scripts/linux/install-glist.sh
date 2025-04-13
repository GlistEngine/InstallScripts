#!/bin/bash
version="0.1.2"
echo "Installation script version $version"

# Determine package manager
if command -v apt >/dev/null; then
    PKG_INSTALL="sudo apt install -y"
    UPDATE_CMD="sudo apt update"
elif command -v yum >/dev/null; then
    PKG_INSTALL="sudo yum install -y"
    UPDATE_CMD="sudo yum update"
else
    echo "Unsupported package manager. Install dependencies manually."
    exit 1
fi

$UPDATE_CMD

# Install required packages
$PKG_INSTALL git openssl libomp-dev llvm cmake libglew-dev libglfw3-dev libglm-dev libfreetype6-dev libassimp-dev curl wget pkg-config unzip

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

echo "Installation completed successfully!"
