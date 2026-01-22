#!/bin/bash

# PostgreSQL Installation & Configuration for Raspberry Pi
# Idempotent - safe to run multiple times
# Installs PostgreSQL, configures for local development, and verifies installation
#
# This script handles PostgreSQL installation via apt, creates a development
# user and database, and ensures proper configuration for local development.

set -e

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║       PostgreSQL Setup for Raspberry Pi & Linux             ║"
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
PG_VERSION_FILE="$HOME/.postgresql_installed_version"
PG_ENV_FILE="$HOME/.postgresql_env.sh"
DEFAULT_DB_USER="$USER"
DEFAULT_DB_NAME="devdb"

# Function to check if PostgreSQL is installed
check_postgresql_installed() {
    if command -v psql &> /dev/null && command -v pg_isready &> /dev/null; then
        return 0
    fi
    return 1
}

# Function to get installed PostgreSQL version
get_installed_version() {
    if check_postgresql_installed; then
        psql --version 2>/dev/null | head -n 1 | awk '{print $3}' | cut -d. -f1,2
    else
        echo ""
    fi
}

# Function to check if PostgreSQL service is running
check_postgresql_running() {
    if pg_isready &> /dev/null; then
        return 0
    fi
    return 1
}

# Function to install PostgreSQL
install_postgresql() {
    step "Updating package lists"
    sudo apt-get update

    step "Installing PostgreSQL and contrib packages"
    sudo apt-get install -y postgresql postgresql-contrib

    if check_postgresql_installed; then
        success "PostgreSQL installed successfully"
        return 0
    else
        error "PostgreSQL installation failed"
        return 1
    fi
}

# Function to start PostgreSQL service
start_postgresql() {
    step "Ensuring PostgreSQL service is running"

    if check_postgresql_running; then
        success "PostgreSQL is already running"
        return 0
    fi

    sudo systemctl enable postgresql
    sudo systemctl start postgresql

    # Wait for PostgreSQL to be ready
    local max_attempts=30
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if pg_isready &> /dev/null; then
            success "PostgreSQL service started"
            return 0
        fi
        sleep 1
        attempt=$((attempt + 1))
    done

    error "PostgreSQL failed to start within timeout"
    return 1
}

# Function to configure PostgreSQL for development
configure_postgresql() {
    step "Configuring PostgreSQL for local development"

    # Get PostgreSQL version for config paths
    local pg_version=$(psql --version | awk '{print $3}' | cut -d. -f1)
    local pg_hba="/etc/postgresql/${pg_version}/main/pg_hba.conf"
    local pg_conf="/etc/postgresql/${pg_version}/main/postgresql.conf"

    # Check if user already exists
    if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DEFAULT_DB_USER'" 2>/dev/null | grep -q 1; then
        info "Database user '$DEFAULT_DB_USER' already exists"
    else
        step "Creating database user '$DEFAULT_DB_USER'"
        sudo -u postgres createuser --superuser "$DEFAULT_DB_USER" 2>/dev/null || true
        success "Database user created"
    fi

    # Check if default database exists
    if sudo -u postgres psql -lqt 2>/dev/null | cut -d \| -f 1 | grep -qw "$DEFAULT_DB_NAME"; then
        info "Database '$DEFAULT_DB_NAME' already exists"
    else
        step "Creating default database '$DEFAULT_DB_NAME'"
        sudo -u postgres createdb -O "$DEFAULT_DB_USER" "$DEFAULT_DB_NAME" 2>/dev/null || true
        success "Database created"
    fi

    # Configure pg_hba.conf for local development (trust local connections)
    # This is for development only - not for production!
    if [ -f "$pg_hba" ]; then
        # Check if we've already configured local trust
        if ! sudo grep -q "# Added by postgresql_setup.sh" "$pg_hba"; then
            step "Configuring local authentication (development mode)"

            # Backup original
            sudo cp "$pg_hba" "${pg_hba}.backup"

            # Add local trust for the user (insert before other rules)
            sudo sed -i "/^# TYPE/a # Added by postgresql_setup.sh - local development\nlocal   all             $DEFAULT_DB_USER                                trust" "$pg_hba"

            # Reload PostgreSQL to apply changes
            sudo systemctl reload postgresql
            success "Local authentication configured"
        else
            info "Local authentication already configured"
        fi
    fi

    success "PostgreSQL configured for development"
}

# Function to setup environment variables
setup_environment() {
    step "Setting up environment variables"

    cat > "$PG_ENV_FILE" << EOF
#!/bin/bash
# PostgreSQL Environment Setup
# Managed by postgresql_setup.sh

export PGHOST=localhost
export PGPORT=5432
export PGUSER=$DEFAULT_DB_USER
export PGDATABASE=$DEFAULT_DB_NAME

# Connection string for applications
export DATABASE_URL="postgresql://$DEFAULT_DB_USER@localhost:5432/$DEFAULT_DB_NAME"
EOF

    chmod +x "$PG_ENV_FILE"

    # Update shell configs
    local shell_configs=()
    [ -f "$HOME/.bashrc" ] && shell_configs+=("$HOME/.bashrc")
    [ -f "$HOME/.zshrc" ] && shell_configs+=("$HOME/.zshrc")
    [ -f "$HOME/.profile" ] && shell_configs+=("$HOME/.profile")

    for shell_config in "${shell_configs[@]}"; do
        if ! grep -q ".postgresql_env.sh" "$shell_config"; then
            info "Adding PostgreSQL environment to $(basename $shell_config)"
            echo "" >> "$shell_config"
            echo "# PostgreSQL Environment (managed by postgresql_setup.sh)" >> "$shell_config"
            echo "[ -f \"\$HOME/.postgresql_env.sh\" ] && source \"\$HOME/.postgresql_env.sh\"" >> "$shell_config"
        fi
    done

    success "Environment configured"
}

# Function to verify PostgreSQL installation
verify_installation() {
    step "Verifying PostgreSQL installation"

    echo ""

    # Check version
    local version=$(get_installed_version)
    if [ -z "$version" ]; then
        error "PostgreSQL not found"
        return 1
    fi
    success "PostgreSQL version: $version"

    # Check service
    if check_postgresql_running; then
        success "PostgreSQL service: running"
    else
        error "PostgreSQL service: not running"
        return 1
    fi

    # Check connection
    if psql -U "$DEFAULT_DB_USER" -d "$DEFAULT_DB_NAME" -c "SELECT 1;" &> /dev/null; then
        success "Database connection: working"
    else
        info "Database connection: requires password or configuration"
    fi

    # Show connection info
    echo ""
    info "Connection details:"
    echo "  Host: localhost"
    echo "  Port: 5432"
    echo "  User: $DEFAULT_DB_USER"
    echo "  Database: $DEFAULT_DB_NAME"

    # Save version
    echo "$version" > "$PG_VERSION_FILE"

    return 0
}

# Function to show update instructions
show_update_instructions() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    info "How to Update PostgreSQL"
    echo ""
    info "As per best practice, run apt commands manually to update system packages:"
    echo ""
    echo "  sudo apt-get update"
    echo "  sudo apt-get upgrade postgresql postgresql-contrib"
    echo ""
    info "After updating, rerun this script to verify/reconfigure:"
    echo ""
    echo "  ./postgresql_setup.sh"
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
        info "PostgreSQL $INSTALLED_VERSION is already installed"
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

        # Ensure service is running
        start_postgresql

        # Ensure configuration is correct
        configure_postgresql

        # Setup environment
        setup_environment

    else
        step "Installing PostgreSQL"

        # Install PostgreSQL
        if ! install_postgresql; then
            error "Installation failed"
            exit 1
        fi

        # Start service
        if ! start_postgresql; then
            error "Failed to start PostgreSQL"
            exit 1
        fi

        # Configure for development
        configure_postgresql

        # Setup environment
        setup_environment
    fi

    # Verify installation
    echo ""
    if ! verify_installation; then
        error "Verification failed"
        exit 1
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    success "PostgreSQL setup complete!"
    echo ""
    info "Version tracking file: $PG_VERSION_FILE"
    info "Environment script: $PG_ENV_FILE"
    echo ""
    info "Quick commands:"
    echo "  psql                    # Connect to default database"
    echo "  psql -d $DEFAULT_DB_NAME    # Connect to dev database"
    echo "  sudo systemctl status postgresql  # Check service status"
    echo ""
    info "To use PostgreSQL environment in current terminal:"
    echo "  source ~/.postgresql_env.sh"
    echo ""
    info "Run this script anytime to verify/repair PostgreSQL setup"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Run main function
main
