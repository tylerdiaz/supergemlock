#!/bin/bash

# supergemlock installer script
# Detects platform and installs appropriate binary

set -e

REPO="tylerdiaz/supergemlock"
INSTALL_DIR="/usr/local/bin"
TEMP_DIR=$(mktemp -d)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Cleanup on exit
trap "rm -rf $TEMP_DIR" EXIT

echo "supergemlock Installer"
echo "====================="
echo ""

# Detect OS and Architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$OS" in
    darwin)
        OS="darwin"
        ;;
    linux)
        OS="linux"
        ;;
    mingw*|msys*|cygwin*)
        echo -e "${RED}Windows is not supported by this installer. Please download manually.${NC}"
        exit 1
        ;;
    *)
        echo -e "${RED}Unsupported operating system: $OS${NC}"
        exit 1
        ;;
esac

case "$ARCH" in
    x86_64|amd64)
        ARCH="x64"
        ;;
    aarch64|arm64)
        ARCH="arm64"
        ;;
    *)
        echo -e "${RED}Unsupported architecture: $ARCH${NC}"
        exit 1
        ;;
esac

PLATFORM="${OS}-${ARCH}"
echo "Detected platform: $PLATFORM"

# Check for required tools
if ! command -v curl &> /dev/null; then
    echo -e "${RED}curl is required but not installed.${NC}"
    exit 1
fi

if ! command -v tar &> /dev/null; then
    echo -e "${RED}tar is required but not installed.${NC}"
    exit 1
fi

# Get latest release
echo ""
echo "Fetching latest release..."
LATEST_RELEASE=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$LATEST_RELEASE" ]; then
    echo -e "${RED}Failed to fetch latest release.${NC}"
    exit 1
fi

echo "Latest version: $LATEST_RELEASE"

# Download binary
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$LATEST_RELEASE/supergemlock-${PLATFORM}.tar.gz"
echo "Downloading from: $DOWNLOAD_URL"

cd "$TEMP_DIR"
if ! curl -L -o supergemlock.tar.gz "$DOWNLOAD_URL"; then
    echo -e "${RED}Failed to download supergemlock.${NC}"
    exit 1
fi

# Extract
echo "Extracting..."
if ! tar xzf supergemlock.tar.gz; then
    echo -e "${RED}Failed to extract archive.${NC}"
    exit 1
fi

# Check if we need sudo
if [ -w "$INSTALL_DIR" ]; then
    SUDO=""
else
    SUDO="sudo"
    echo -e "${YELLOW}Installation requires sudo access.${NC}"
fi

# Install
echo ""
echo "Installing to $INSTALL_DIR..."
$SUDO mv supergemlock "$INSTALL_DIR/"
$SUDO mv bundle "$INSTALL_DIR/supergemlock_bundle"
$SUDO chmod +x "$INSTALL_DIR/supergemlock"
$SUDO chmod +x "$INSTALL_DIR/supergemlock_bundle"

# Verify installation
if command -v supergemlock &> /dev/null; then
    echo -e "${GREEN}✓ supergemlock installed successfully!${NC}"
    echo ""
    supergemlock --version || echo "Version: $LATEST_RELEASE"
else
    echo -e "${RED}Installation failed. Please check your PATH.${NC}"
    exit 1
fi

# Show next steps
echo ""
echo "Next steps:"
echo "1. Test supergemlock:"
echo "   $ supergemlock"
echo ""
echo "2. Use as bundler replacement:"
echo "   $ alias bundle='supergemlock_bundle'"
echo "   $ bundle install"
echo ""
echo "3. Add to your shell profile for permanent alias:"
echo "   $ echo \"alias bundle='supergemlock_bundle'\" >> ~/.bashrc"
echo ""
echo -e "${GREEN}Installation complete! Happy resolving at 20-60x speed!${NC}"

# Offer to set up alias
echo ""
read -p "Would you like to set up the bundle alias now? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    SHELL_PROFILE=""
    
    if [ -n "$BASH_VERSION" ]; then
        SHELL_PROFILE="$HOME/.bashrc"
    elif [ -n "$ZSH_VERSION" ]; then
        SHELL_PROFILE="$HOME/.zshrc"
    fi
    
    if [ -n "$SHELL_PROFILE" ]; then
        echo "alias bundle='supergemlock_bundle'" >> "$SHELL_PROFILE"
        echo -e "${GREEN}✓ Alias added to $SHELL_PROFILE${NC}"
        echo "Run 'source $SHELL_PROFILE' to use it in this session."
    else
        echo "Please add this to your shell profile manually:"
        echo "  alias bundle='supergemlock_bundle'"
    fi
fi