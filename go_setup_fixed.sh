#!/bin/bash

# Generic Go Installation & Version Manager for Raspberry Pi
# Automatically fetches and installs the latest Go version
# Run anytime to update to the latest version

set -e

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         Go Version Manager for Raspberry Pi & Linux         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

step() { echo -e "${BLUE}→ $1${NC}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
info() { echo -e "${YELLOW}ℹ $1${NC}"; }
error() { echo -e "${RED}✗ $1${NC}"; }

# Configuration
GO_VERSION_FILE="$HOME/.go_installed_version"
GO_INSTALL_DIR="$HOME/.local/go"
GO_DOWNLOAD_DIR="/tmp/go_download"

# Detect architecture with improved Raspberry Pi detection
ARCH=$(uname -m)
step "Detecting architecture: $ARCH"

case $ARCH in
    x86_64)
        GO_ARCH="amd64"
        ;;
    aarch64|arm64)
        # 64-bit ARM (modern Raspberry Pi OS 64-bit)
        GO_ARCH="arm64"
        info "Detected 64-bit ARM (aarch64) - using arm64 binaries"
        ;;
    armv7l)
        # 32-bit ARMv7 - use armv6l (backward compatible)
        GO_ARCH="armv6l"
        info "Detected 32-bit ARMv7 - using armv6l binaries (compatible)"
        ;;
    armv6l)
        # 32-bit ARMv6
        GO_ARCH="armv6l"
        info "Detected 32-bit ARMv6 - using armv6l binaries"
        ;;
    arm*)
        # Fallback for any other ARM architecture
        GO_ARCH="armv6l"
        info "Detected ARM architecture - using armv6l binaries (most compatible)"
        ;;
    *)
        error "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Detect OS
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case $OS in
    linux)
        GO_OS="linux"
        ;;
    darwin)
        GO_OS="darwin"
        ;;
    *)
        error "Unsupported OS: $OS"
        exit 1
        ;;
esac

success "OS: $GO_OS, Architecture: $GO_ARCH"

# Function to get latest Go version
get_latest_go_version() {
    # Primary method: Use the VERSION endpoint
    local version=$(curl -s https://go.dev/VERSION?m=text 2>/dev/null | head -n 1)
    
    # Verify it looks correct (should start with "go")
    if [[ ! "$version" =~ ^go[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        # Fallback: Try parsing from download page
        version=$(curl -s https://go.dev/dl/ 2>/dev/null | grep -oP 'go[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)
    fi
    
    if [ -z "$version" ] || [[ ! "$version" =~ ^go[0-9] ]]; then
        version="go1.23.4"
    fi
    
    echo "$version"
}

# Function to get currently installed version
get_installed_version() {
    if [ -f "$GO_VERSION_FILE" ]; then
        cat "$GO_VERSION_FILE"
    else
        echo ""
    fi
}

# Function to remove old Go installation
remove_old_go() {
    local old_version=$1
    
    if [ -d "$GO_INSTALL_DIR" ]; then
        step "Removing old Go installation ($old_version)"
        rm -rf "$GO_INSTALL_DIR"
        success "Old Go installation removed"
    fi
    
    # Clean up old downloads
    if [ -d "$GO_DOWNLOAD_DIR" ]; then
        rm -rf "$GO_DOWNLOAD_DIR"
    fi
}

# Function to download and install Go
install_go() {
    local version=$1
    local filename="${version}.${GO_OS}-${GO_ARCH}.tar.gz"
    local download_url="https://go.dev/dl/${filename}"
    
    step "Downloading Go ${version} for ${GO_OS}/${GO_ARCH}"
    info "URL: $download_url"
    
    # Create download directory
    mkdir -p "$GO_DOWNLOAD_DIR"
    
    # Download with progress - prefer wget, fallback to curl
    local download_success=0
    
    if command -v wget &> /dev/null; then
        if wget --spider "$download_url" 2>/dev/null; then
            wget -q --show-progress -O "$GO_DOWNLOAD_DIR/${filename}" "$download_url" && download_success=1
        else
            error "Download URL not accessible: $download_url"
            info "This might be due to network issues or invalid architecture"
            return 1
        fi
    elif command -v curl &> /dev/null; then
        # Test if URL exists first
        if curl --output /dev/null --silent --head --fail "$download_url"; then
            curl -# -L -o "$GO_DOWNLOAD_DIR/${filename}" "$download_url" && download_success=1
        else
            error "Download URL not accessible: $download_url"
            info "This might be due to network issues or invalid architecture"
            return 1
        fi
    else
        error "Neither wget nor curl found. Please install one of them:"
        info "Run: sudo apt-get update && sudo apt-get install wget"
        return 1
    fi
    
    if [ $download_success -eq 0 ]; then
        error "Failed to download Go"
        return 1
    fi
    
    success "Download complete"
    
    # Verify download
    if [ ! -f "$GO_DOWNLOAD_DIR/${filename}" ]; then
        error "Downloaded file not found"
        return 1
    fi
    
    local file_size=$(stat -f%z "$GO_DOWNLOAD_DIR/${filename}" 2>/dev/null || stat -c%s "$GO_DOWNLOAD_DIR/${filename}" 2>/dev/null)
    if [ "$file_size" -lt 10000 ]; then
        error "Downloaded file is too small (${file_size} bytes) - download may have failed"
        return 1
    fi
    
    # Extract
    step "Installing Go to $GO_INSTALL_DIR"
    mkdir -p "$GO_INSTALL_DIR"
    
    if ! tar -C "$GO_INSTALL_DIR" --strip-components=1 -xzf "$GO_DOWNLOAD_DIR/${filename}"; then
        error "Failed to extract Go archive"
        info "The archive may be corrupted or incompatible"
        return 1
    fi
    
    success "Go ${version} installed successfully"
    
    # Save version info
    echo "$version" > "$GO_VERSION_FILE"
    
    # Cleanup download
    rm -rf "$GO_DOWNLOAD_DIR"
    
    return 0
}

# Function to setup Go environment
setup_go_environment() {
    local go_bin="$GO_INSTALL_DIR/bin"
    
    step "Setting up Go environment"
    
    # Create environment setup script in user's home directory
    cat > "$HOME/.go_env.sh" << 'EOF'
#!/bin/bash
# Go Environment Setup
# Managed by Go installation script

export GOROOT="$HOME/.local/go"
export GOPATH="$HOME/go"
export PATH="$GOROOT/bin:$GOPATH/bin:$PATH"

# Go module settings
export GO111MODULE=on
export GOPROXY=https://proxy.golang.org,direct
export GOSUMDB=sum.golang.org
EOF

    chmod +x "$HOME/.go_env.sh"
    
    # Source it for current session
    source "$HOME/.go_env.sh"
    
    # Create GOPATH directories if they don't exist
    mkdir -p "$HOME/go"/{bin,pkg,src}
    
    success "Go environment configured"
    
    # Update shell config if needed
    update_shell_config
}

# Function to update shell configuration
update_shell_config() {
    local shell_configs=()
    local updated=0
    
    # Check common shell config files
    [ -f "$HOME/.bashrc" ] && shell_configs+=("$HOME/.bashrc")
    [ -f "$HOME/.zshrc" ] && shell_configs+=("$HOME/.zshrc")
    [ -f "$HOME/.profile" ] && shell_configs+=("$HOME/.profile")
    
    for shell_config in "${shell_configs[@]}"; do
        # Check if already configured
        if ! grep -q ".go_env.sh" "$shell_config"; then
            info "Adding Go environment to $(basename $shell_config)"
            echo "" >> "$shell_config"
            echo "# Go Environment (managed by Go installation script)" >> "$shell_config"
            echo "[ -f \"\$HOME/.go_env.sh\" ] && source \"\$HOME/.go_env.sh\"" >> "$shell_config"
            updated=1
        fi
    done
    
    if [ $updated -eq 1 ]; then
        success "Shell configuration updated"
        info "Run 'source ~/.bashrc' (or your shell config) to apply changes in current terminal"
    else
        info "Shell configuration already set up"
    fi
}

# Function to verify Go installation
verify_go_installation() {
    step "Verifying Go installation"
    
    # Source environment
    source "$HOME/.go_env.sh"
    
    # Check if go binary exists
    if [ ! -f "$GO_INSTALL_DIR/bin/go" ]; then
        error "Go binary not found at $GO_INSTALL_DIR/bin/go"
        return 1
    fi
    
    # Check if go binary is executable
    if [ ! -x "$GO_INSTALL_DIR/bin/go" ]; then
        error "Go binary is not executable"
        info "Fixing permissions..."
        chmod +x "$GO_INSTALL_DIR/bin/go"
    fi
    
    # Try to run go version
    if ! "$GO_INSTALL_DIR/bin/go" version &> /dev/null; then
        error "Go binary cannot be executed"
        info "This might indicate wrong architecture or corrupted download"
        
        # Check file type
        local file_type=$(file "$GO_INSTALL_DIR/bin/go" 2>/dev/null || echo "unknown")
        info "Binary type: $file_type"
        
        if echo "$file_type" | grep -q "ELF.*ARM"; then
            info "Binary is ARM - this is correct for Raspberry Pi"
        elif echo "$file_type" | grep -q "x86"; then
            error "Binary is x86 - WRONG architecture for Raspberry Pi!"
            error "You may have downloaded the wrong version"
            return 1
        fi
        
        return 1
    fi
    
    # Get version
    INSTALLED_VERSION=$("$GO_INSTALL_DIR/bin/go" version | awk '{print $3}')
    success "Go version: $INSTALLED_VERSION"
    
    # Test go env
    echo ""
    info "Go environment:"
    "$GO_INSTALL_DIR/bin/go" env GOROOT
    "$GO_INSTALL_DIR/bin/go" env GOPATH
    "$GO_INSTALL_DIR/bin/go" env GOARCH
    "$GO_INSTALL_DIR/bin/go" env GOOS
    
    return 0
}

# Main execution
main() {
    echo ""
    
    # Check for required tools
    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        error "Neither curl nor wget found. Installing wget..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y wget
        else
            error "Cannot install wget automatically. Please install it manually."
            exit 1
        fi
    fi
    
    # Get versions
    step "Fetching latest Go version from golang.org..."
    LATEST_VERSION=$(get_latest_go_version)
    INSTALLED_VERSION=$(get_installed_version)
    
    if [ -z "$LATEST_VERSION" ]; then
        error "Failed to fetch latest Go version"
        info "Using fallback version: go1.23.4"
        LATEST_VERSION="go1.23.4"
    fi
    
    info "Latest available Go version: $LATEST_VERSION"
    
    if [ -n "$INSTALLED_VERSION" ]; then
        info "Currently installed version: $INSTALLED_VERSION"
    else
        info "No previous Go installation found"
    fi
    
    echo ""
    
    # Check if update is needed
    if [ "$LATEST_VERSION" != "$INSTALLED_VERSION" ]; then
        if [ -n "$INSTALLED_VERSION" ]; then
            step "Update available: $INSTALLED_VERSION → $LATEST_VERSION"
        else
            step "Installing Go for the first time"
        fi
        
        # Remove old installation
        if [ -n "$INSTALLED_VERSION" ]; then
            remove_old_go "$INSTALLED_VERSION"
        fi
        
        # Install new version
        if ! install_go "$LATEST_VERSION"; then
            error "Installation failed"
            exit 1
        fi
        
        # Setup environment
        setup_go_environment
        
        # Verify
        if ! verify_go_installation; then
            error "Verification failed"
            exit 1
        fi
        
        echo ""
        success "Go ${LATEST_VERSION} is ready!"
        
    else
        success "Go ${INSTALLED_VERSION} is already the latest version"
        
        # Still verify and setup environment
        if [ -d "$GO_INSTALL_DIR" ]; then
            setup_go_environment
            if ! verify_go_installation; then
                info "Verification failed, attempting reinstall..."
                remove_old_go "$INSTALLED_VERSION"
                if ! install_go "$LATEST_VERSION"; then
                    error "Reinstallation failed"
                    exit 1
                fi
                setup_go_environment
                verify_go_installation || exit 1
            fi
        else
            info "Go installation directory not found, installing..."
            if ! install_go "$LATEST_VERSION"; then
                error "Installation failed"
                exit 1
            fi
            setup_go_environment
            verify_go_installation || exit 1
        fi
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    success "Go setup complete!"
    echo ""
    info "Installation location: $GO_INSTALL_DIR"
    info "Version tracking file: $GO_VERSION_FILE"
    info "Environment script: $HOME/.go_env.sh"
    info "GOPATH: $HOME/go"
    echo ""
    info "To use Go in your current terminal:"
    echo "  source ~/.go_env.sh"
    echo ""
    info "Or restart your terminal (Go is already configured in your shell)"
    echo ""
    info "Run this script anytime to update to the latest Go version"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Run main function
main