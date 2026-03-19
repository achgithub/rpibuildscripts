#!/bin/bash

# Node.js & pnpm Installation & Version Manager for Raspberry Pi
# Automatically installs Node.js LTS and pnpm package manager
# Safe to run multiple times (idempotent)
#
# This script handles Node.js installation via NodeSource APT repository
# and pnpm installation via npm, ensuring proper environment setup.

set -e

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║    Node.js & pnpm Setup for Raspberry Pi & Linux           ║"
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
NODEJS_VERSION_FILE="$HOME/.nodejs_installed_version"
PNPM_VERSION_FILE="$HOME/.pnpm_installed_version"
NODEJS_MAJOR_VERSION="20"  # LTS version

# Detect architecture
ARCH=$(uname -m)
step "Detecting architecture: $ARCH"

case $ARCH in
    x86_64)
        NODE_ARCH="x64"
        ;;
    aarch64|arm64)
        NODE_ARCH="arm64"
        info "Detected 64-bit ARM (aarch64)"
        ;;
    armv7l)
        NODE_ARCH="armv7l"
        info "Detected 32-bit ARMv7"
        ;;
    armv6l)
        NODE_ARCH="armv6l"
        info "Detected 32-bit ARMv6"
        ;;
    *)
        error "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

success "Architecture: $NODE_ARCH"

# Check if Node.js is already installed
check_nodejs_installed() {
    if command -v node &> /dev/null; then
        local installed_version=$(node --version 2>/dev/null)
        if [ -n "$installed_version" ]; then
            echo "$installed_version"
            return 0
        fi
    fi
    return 1
}

# Check if pnpm is already installed
check_pnpm_installed() {
    if command -v pnpm &> /dev/null; then
        local installed_version=$(pnpm --version 2>/dev/null)
        if [ -n "$installed_version" ]; then
            echo "$installed_version"
            return 0
        fi
    fi
    return 1
}

# Install Node.js using NodeSource repository
install_nodejs() {
    step "Installing Node.js v${NODEJS_MAJOR_VERSION} LTS"

    # Update apt
    info "Updating package manager..."
    sudo apt-get update -qq || true

    # Install NodeSource repository setup script
    info "Setting up NodeSource repository..."
    curl -fsSL "https://deb.nodesource.com/setup_${NODEJS_MAJOR_VERSION}.x" | sudo -E bash - > /dev/null 2>&1 || {
        error "Failed to setup NodeSource repository"
        info "Attempting fallback: direct apt install"
        sudo apt-get install -y nodejs
        return
    }

    # Install Node.js
    info "Installing Node.js..."
    sudo apt-get install -y nodejs || {
        error "Failed to install Node.js"
        return 1
    }

    # Verify installation
    if ! command -v node &> /dev/null; then
        error "Node.js installation failed - binary not in PATH"
        return 1
    fi

    local version=$(node --version 2>/dev/null)
    if [ -z "$version" ]; then
        error "Node.js installation failed - cannot execute node binary"
        return 1
    fi

    success "Node.js installed: $version"
}

# Install pnpm globally via npm
install_pnpm() {
    step "Installing pnpm"

    # First ensure npm is working
    if ! command -v npm &> /dev/null; then
        error "npm not found - Node.js installation may have failed"
        return 1
    fi

    local npm_version=$(npm --version 2>/dev/null)
    if [ -z "$npm_version" ]; then
        error "npm binary exists but cannot be executed"
        return 1
    fi

    info "Current npm version: $npm_version"

    # Create user npm directory if it doesn't exist
    mkdir -p "$HOME/.npm-global/bin"

    # Configure npm to use user directory to avoid permission issues
    npm config set prefix "$HOME/.npm-global" --userconfig="$HOME/.npmrc"

    # Install pnpm globally to user directory
    info "Installing pnpm globally to $HOME/.npm-global..."
    npm install -g pnpm@latest || {
        error "Failed to install pnpm via npm"
        return 1
    }

    # Ensure pnpm is in PATH
    export PATH="$HOME/.npm-global/bin:$PATH"

    if ! command -v pnpm &> /dev/null; then
        error "pnpm installation failed - binary not in PATH"
        return 1
    fi

    local pnpm_version=$(pnpm --version 2>/dev/null)
    if [ -z "$pnpm_version" ]; then
        error "pnpm installation failed - cannot execute pnpm binary"
        return 1
    fi

    success "pnpm installed: $pnpm_version"
}

# Setup environment variables
setup_environment() {
    step "Setting up environment"

    # Create Node.js environment setup script
    cat > "$HOME/.nodejs_env.sh" << 'EOF'
#!/bin/bash
# Node.js & pnpm Environment Setup
# Managed by Node.js installation script

# Node.js is typically in standard PATH, but ensure NPM_CONFIG is set
export NPM_CONFIG_PREFIX="$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$PATH"

# pnpm configuration
export PNPM_HOME="$HOME/.pnpm"
export PATH="$PNPM_HOME:$PATH"

# Optional: pnpm store location
export PNPM_STORE_DIR="$HOME/.pnpm-store"
EOF

    chmod +x "$HOME/.nodejs_env.sh"

    # Source it for current session
    source "$HOME/.nodejs_env.sh"

    # Create directories if they don't exist
    mkdir -p "$HOME/.npm-global/bin"
    mkdir -p "$HOME/.pnpm"
    mkdir -p "$HOME/.pnpm-store"

    success "Node.js environment configured"

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
        if ! grep -q ".nodejs_env.sh" "$shell_config"; then
            info "Adding Node.js environment to $(basename $shell_config)"
            echo "" >> "$shell_config"
            echo "# Node.js & pnpm Environment (managed by Node.js installation script)" >> "$shell_config"
            echo "[ -f \"\$HOME/.nodejs_env.sh\" ] && source \"\$HOME/.nodejs_env.sh\"" >> "$shell_config"
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

# Verify Node.js and pnpm installation
verify_installation() {
    step "Verifying installation"

    # Source environment
    source "$HOME/.nodejs_env.sh"

    local all_good=1

    # Check Node.js
    if command -v node &> /dev/null; then
        local node_version=$(node --version)
        success "Node.js: $node_version"
    else
        error "Node.js: NOT FOUND"
        all_good=0
    fi

    # Check npm
    if command -v npm &> /dev/null; then
        local npm_version=$(npm --version)
        success "npm: $npm_version"
    else
        error "npm: NOT FOUND"
        all_good=0
    fi

    # Check pnpm
    if command -v pnpm &> /dev/null; then
        local pnpm_version=$(pnpm --version)
        success "pnpm: $pnpm_version"

        # Store version
        echo "$pnpm_version" > "$PNPM_VERSION_FILE"
    else
        error "pnpm: NOT FOUND"
        all_good=0
    fi

    if [ $all_good -eq 1 ]; then
        success "All tools verified successfully"
        return 0
    else
        error "Verification failed"
        return 1
    fi
}

# Main orchestration
main() {
    echo ""

    # Check existing Node.js installation
    local existing_node
    existing_node=$(check_nodejs_installed) || true

    if [ -n "$existing_node" ]; then
        info "Node.js already installed: $existing_node"
    else
        step "Node.js not found, installing..."
        install_nodejs || {
            error "Failed to install Node.js"
            exit 1
        }
    fi

    echo ""

    # Check existing pnpm installation (pnpm requires Node.js)
    local existing_pnpm
    existing_pnpm=$(check_pnpm_installed) || true

    if [ -n "$existing_pnpm" ]; then
        info "pnpm already installed: v$existing_pnpm"
    else
        step "pnpm not found, installing..."
        install_pnpm || {
            error "Failed to install pnpm"
            exit 1
        }
    fi

    echo ""

    # Setup environment
    setup_environment

    echo ""

    # Verify everything
    verify_installation || {
        error "Installation verification failed"
        exit 1
    }

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║            Node.js & pnpm Setup Complete!                   ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Next steps:"
    echo "  1. Source your shell config: source ~/.bashrc"
    echo "  2. Verify: node --version && npm --version && pnpm --version"
    echo "  3. Test pnpm: pnpm install (in an activity-hub directory)"
    echo ""
}

main
