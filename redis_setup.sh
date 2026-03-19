#!/bin/bash

# Redis Installation & Configuration for Raspberry Pi
# Idempotent - safe to run multiple times
# Installs Redis, configures for local development, and verifies installation
#
# This script handles Redis installation via apt, configures it for local
# development use, and ensures the service is running properly.

set -e

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          Redis Setup for Raspberry Pi & Linux               ║"
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
REDIS_VERSION_FILE="$HOME/.redis_installed_version"
REDIS_ENV_FILE="$HOME/.redis_env.sh"
REDIS_PORT=6379

# Function to check if Redis is installed
check_redis_installed() {
    if command -v redis-server &> /dev/null && command -v redis-cli &> /dev/null; then
        return 0
    fi
    return 1
}

# Function to get installed Redis version
get_installed_version() {
    if check_redis_installed; then
        redis-server --version 2>/dev/null | awk '{print $3}' | cut -d= -f2
    else
        echo ""
    fi
}

# Function to check if Redis service is running
check_redis_running() {
    if redis-cli ping &> /dev/null; then
        return 0
    fi
    return 1
}

# Function to install Redis
install_redis() {
    step "Updating package lists"
    sudo apt-get update

    step "Installing Redis server"
    sudo apt-get install -y redis-server redis-tools

    if check_redis_installed; then
        success "Redis installed successfully"
        return 0
    else
        error "Redis installation failed"
        return 1
    fi
}

# Function to configure Redis for development
configure_redis() {
    step "Configuring Redis for local development"

    local redis_conf="/etc/redis/redis.conf"

    if [ ! -f "$redis_conf" ]; then
        info "Redis config not found at expected location, checking alternatives"
        # Try alternate locations
        if [ -f "/etc/redis.conf" ]; then
            redis_conf="/etc/redis.conf"
        else
            info "Using default Redis configuration"
            return 0
        fi
    fi

    # Check if we've already configured
    if sudo grep -q "# Configured by redis_setup.sh" "$redis_conf"; then
        info "Redis already configured for development"
        return 0
    fi

    # Backup original
    sudo cp "$redis_conf" "${redis_conf}.backup"

    step "Applying development configuration"

    # Enable supervised systemd (for proper service management)
    sudo sed -i 's/^supervised no/supervised systemd/' "$redis_conf" 2>/dev/null || true

    # Bind to localhost only (security)
    # This is usually the default, but let's ensure it
    if ! sudo grep -q "^bind 127.0.0.1" "$redis_conf"; then
        sudo sed -i 's/^bind .*/bind 127.0.0.1 ::1/' "$redis_conf" 2>/dev/null || true
    fi

    # Add marker that we've configured this
    echo "" | sudo tee -a "$redis_conf" > /dev/null
    echo "# Configured by redis_setup.sh" | sudo tee -a "$redis_conf" > /dev/null

    success "Redis configured for development"
    return 0
}

# Function to start Redis service
start_redis() {
    step "Ensuring Redis service is running"

    if check_redis_running; then
        success "Redis is already running"
        return 0
    fi

    sudo systemctl enable redis-server
    sudo systemctl restart redis-server

    # Wait for Redis to be ready
    local max_attempts=30
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if check_redis_running; then
            success "Redis service started"
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done

    error "Redis failed to start within timeout"
    return 1
}

# Function to setup environment variables
setup_environment() {
    step "Setting up environment variables"

    cat > "$REDIS_ENV_FILE" << EOF
#!/bin/bash
# Redis Environment Setup
# Managed by redis_setup.sh

export REDIS_HOST=localhost
export REDIS_PORT=$REDIS_PORT

# Connection URL for applications
export REDIS_URL="redis://localhost:$REDIS_PORT"
EOF

    chmod +x "$REDIS_ENV_FILE"

    # Update shell configs
    local shell_configs=()
    [ -f "$HOME/.bashrc" ] && shell_configs+=("$HOME/.bashrc")
    [ -f "$HOME/.zshrc" ] && shell_configs+=("$HOME/.zshrc")
    [ -f "$HOME/.profile" ] && shell_configs+=("$HOME/.profile")

    for shell_config in "${shell_configs[@]}"; do
        if ! grep -q ".redis_env.sh" "$shell_config"; then
            info "Adding Redis environment to $(basename $shell_config)"
            echo "" >> "$shell_config"
            echo "# Redis Environment (managed by redis_setup.sh)" >> "$shell_config"
            echo "[ -f \"\$HOME/.redis_env.sh\" ] && source \"\$HOME/.redis_env.sh\"" >> "$shell_config"
        fi
    done

    success "Environment configured"
}

# Function to verify Redis installation
verify_installation() {
    step "Verifying Redis installation"

    echo ""

    # Check version
    local version=$(get_installed_version)
    if [ -z "$version" ]; then
        error "Redis not found"
        return 1
    fi
    success "Redis version: $version"

    # Check service
    if check_redis_running; then
        success "Redis service: running"
    else
        error "Redis service: not running"
        return 1
    fi

    # Test PING/PONG
    local pong=$(redis-cli ping 2>/dev/null)
    if [ "$pong" = "PONG" ]; then
        success "Redis PING: PONG"
    else
        error "Redis PING failed"
        return 1
    fi

    # Get Redis info
    local used_memory=$(redis-cli info memory 2>/dev/null | grep "used_memory_human" | cut -d: -f2 | tr -d '\r')
    local connected_clients=$(redis-cli info clients 2>/dev/null | grep "connected_clients" | cut -d: -f2 | tr -d '\r')

    echo ""
    info "Redis status:"
    echo "  Host: localhost"
    echo "  Port: $REDIS_PORT"
    echo "  Memory used: ${used_memory:-unknown}"
    echo "  Connected clients: ${connected_clients:-unknown}"

    # Save version
    echo "$version" > "$REDIS_VERSION_FILE"

    return 0
}

# Function to run basic Redis test
run_basic_test() {
    step "Running basic functionality test"

    # Set a test key
    redis-cli SET "_redis_setup_test" "success" EX 10 > /dev/null 2>&1

    # Get the test key
    local result=$(redis-cli GET "_redis_setup_test" 2>/dev/null)

    if [ "$result" = "success" ]; then
        success "Read/Write test: passed"
        # Clean up
        redis-cli DEL "_redis_setup_test" > /dev/null 2>&1
        return 0
    else
        error "Read/Write test: failed"
        return 1
    fi
}

# Function to show update instructions
show_update_instructions() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    info "How to Update Redis"
    echo ""
    info "As per best practice, run apt commands manually to update system packages:"
    echo ""
    echo "  sudo apt-get update"
    echo "  sudo apt-get upgrade redis-server redis-tools"
    echo ""
    info "After updating, rerun this script to verify/reconfigure:"
    echo ""
    echo "  ./redis_setup.sh"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    exit 0
}

# Main execution
main() {
    echo ""

    # Check if running on supported system
    if ! command -v apt-get &> /dev/null; then
        error "This script requires apt-get (Debian/Ubuntu/Raspberry Pi OS)"
        exit 1
    fi

    # Check current installation status
    INSTALLED_VERSION=$(get_installed_version)

    if [ -n "$INSTALLED_VERSION" ]; then
        info "Redis $INSTALLED_VERSION is already installed"
        echo ""
        echo "What would you like to do?"
        echo "  1) Verify and repair existing installation (default)"
        echo "  2) Show update instructions"
        echo ""
        read -p "Enter choice [1-2]: " choice

        case "$choice" in
            2)
                show_update_instructions
                ;;
            1|"")
                # Continue with verification/repair
                ;;
            *)
                error "Invalid choice"
                exit 1
                ;;
        esac

        # Ensure configuration is correct
        configure_redis

        # Ensure service is running
        start_redis

        # Setup environment
        setup_environment

    else
        step "Installing Redis"

        # Install Redis
        if ! install_redis; then
            error "Installation failed"
            exit 1
        fi

        # Configure for development
        configure_redis

        # Start service
        if ! start_redis; then
            error "Failed to start Redis"
            exit 1
        fi

        # Setup environment
        setup_environment
    fi

    # Verify installation
    echo ""
    if ! verify_installation; then
        error "Verification failed"
        exit 1
    fi

    # Run basic test
    echo ""
    if ! run_basic_test; then
        error "Basic test failed"
        exit 1
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    success "Redis setup complete!"
    echo ""
    info "Version tracking file: $REDIS_VERSION_FILE"
    info "Environment script: $REDIS_ENV_FILE"
    echo ""
    info "Quick commands:"
    echo "  redis-cli                  # Connect to Redis CLI"
    echo "  redis-cli ping             # Test connection"
    echo "  redis-cli info             # Get server info"
    echo "  sudo systemctl status redis-server  # Check service status"
    echo ""
    info "To use Redis environment in current terminal:"
    echo "  source ~/.redis_env.sh"
    echo ""
    info "Run this script anytime to verify/repair Redis setup"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Run main function
main
