version="0.1.2"
echo "Installation script version $version"

# Execute the brew command
brew --version
# Check if the brew command was successfully executed
if [[ "$?" -ne 0 ]] ; then
    echo "Brew is not installed!"
    # Install brew
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add brew to path
    (echo; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"') >> ~/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi
# Install the required packages
brew install git openssl@3 libomp llvm cmake glew glfw glm freetype assimp curl git wget pkg-config
sudo spctl --master-disable

# todo check if command line tools are properly installed and delete if required!
#sudo rm -rf /Library/Developer/CommandLineTools
# Install Xcode
xcode-select --install

# Create the required directories
mkdir -p ~/dev/glist
mkdir -p ~/dev/glist/zbin
mkdir -p ~/dev/glist/myglistapps

# Clone the required repositories
# Get the GitHub Username
echo "Enter your GitHub Username (press enter to clone from the default repo): "
read username
if [ -z "$username" ]; then
    username="GlistEngine"
fi

# Clone the GlistEngine repository
cd ~/dev/glist
git clone https://github.com/$username/GlistEngine
if [[ "$?" -ne 0 ]] ; then
    echo "Failed to clone the repository!"
    exit 
fi

# Clone the GlistApp repository
cd ~/dev/glist/myglistapps
git clone https://github.com/$username/GlistApp
if [[ "$?" -ne 0 ]] ; then
    echo "Failed to clone the repository!"
    exit 
fi

# Download the zbin
cd ~/dev/glist/zbin

if [[ $(uname -p) == 'arm' ]]; then
    if [ ! -f "glistzbin-macos.zip" ]; then
    echo "Downloading zbin for arm architecture"
        URL=$(curl https://raw.githubusercontent.com/GlistEngine/InstallScripts/main/url/zbin-macos)
        wget -O glistzbin-macos.zip $URL
        if [[ "$?" -ne 0 ]] ; then
            echo "Failed to download zbin!"
            exit 
        fi
    fi
    if [ ! -f "glistzbin-macos" ]; then
        echo "Unzipping zbin"
        unzip "glistzbin-macos.zip" -x '__MACOSX/*' '.git/*'
    else 
        echo "Zbin already exists, skipping"
    fi
    ECLIPSE_FOLDER=$(curl https://raw.githubusercontent.com/GlistEngine/InstallScripts/main/url/eclipse-macos)
    cd ~/dev/glist/zbin/glistzbin-macos/eclipse/$ECLIPSE_FOLDER
    echo "Signing Eclipse"
    sudo xattr -cr Eclipse.app
    sudo codesign --force --deep --sign - Eclipse.app
    echo "Creating a shortcut to Eclipse in Applications folder"
    sudo ln -s ~/dev/glist/zbin/glistzbin-macos/eclipse/$ECLIPSE_FOLDER/Eclipse.app "/Applications/GlistEngine Eclipse"
    echo "OPENSSL VER:"
    ls /opt/homebrew/Cellar/openssl@3
    echo "LLVM VER:"
    ls /opt/homebrew/Cellar/llvm
    # add to path
    (echo; echo 'export PATH=$PATH:/opt/homebrew/bin') >> ~/.zprofile
    export PATH=$PATH:/opt/homebrew/bin
else 
    if [ ! -f "glistzbin-macos-x86_64.zip" ]; then
        echo "Downloading zbin for intel architecture"
        URL=$(curl https://raw.githubusercontent.com/GlistEngine/InstallScripts/main/url/zbin-macos-intel)
        wget -O glistzbin-macos-x86_64.zip $URL
        if [[ "$?" -ne 0 ]] ; then
            echo "Failed to download zbin!"
            exit 
        fi
    fi
    if [ ! -f "glistzbin-macos-x86_64" ]; then
          echo "Unzipping zbin"
          unzip "glistzbin-macos-x86_64.zip" -x '__MACOSX/*' '.git/*'
    else 
        echo "Zbin already exists, skipping"
    fi
    ECLIPSE_FOLDER=$(curl https://raw.githubusercontent.com/GlistEngine/InstallScripts/main/url/eclipse-macos-intel)
    cd ~/dev/glist/zbin/glistzbin-macos-x86_64/eclipse/$ECLIPSE_FOLDER
    echo "Signing Eclipse"
    sudo xattr -cr Eclipse.app
    sudo codesign --force --deep --sign - Eclipse.app
    echo "Creating a shortcut to Eclipse in Applications folder"
    sudo ln -s ~/dev/glist/zbin/glistzbin-macos-x86_64/eclipse/$ECLIPSE_FOLDER/Eclipse.app "/Applications/GlistEngine Eclipse"
    echo "OPENSSL VER:"
    ls /usr/local/Cellar/openssl@3
    echo "LLVM VER:"
    ls /usr/local/Cellar/llvm
    # add to path
    (echo; echo 'export PATH=$PATH:/usr/local/bin') >> ~/.zprofile
    export PATH=$PATH:/usr/local/bin
fi
echo "Installation completed successfully!"

