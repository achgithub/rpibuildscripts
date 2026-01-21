#!/bin/bash

# SSH Keys Backup & Restore for Raspberry Pi
# Encrypts SSH keys with GPG for safe storage
# Use 'backup' to save keys, 'restore' to recover them after a wipe
#
# The encrypted backup can be safely stored in git or cloud storage.
# You'll need to remember the encryption password.

set -e

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        SSH Keys Backup & Restore (Encrypted)                ║"
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
SSH_DIR="$HOME/.ssh"
BACKUP_DIR="${BACKUP_DIR:-$HOME/ssh_backup}"
BACKUP_FILE="ssh_keys_backup.tar.gz.gpg"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_FILE"

# Show usage
usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  backup     Encrypt and backup SSH keys"
    echo "  restore    Restore SSH keys from encrypted backup"
    echo "  check      Check if backup exists and SSH dir status"
    echo ""
    echo "Environment variables:"
    echo "  BACKUP_DIR   Directory for backup file (default: ~/ssh_backup)"
    echo ""
    echo "Examples:"
    echo "  $0 backup                    # Backup to default location"
    echo "  BACKUP_DIR=/mnt/usb $0 backup   # Backup to USB drive"
    echo ""
}

# Check for required tools
check_dependencies() {
    if ! command -v gpg &> /dev/null; then
        error "GPG is not installed"
        info "Install with: sudo apt-get install gnupg"
        exit 1
    fi
}

# Backup SSH keys
do_backup() {
    step "Starting SSH keys backup"

    # Check if SSH directory exists and has keys
    if [ ! -d "$SSH_DIR" ]; then
        error "SSH directory not found: $SSH_DIR"
        exit 1
    fi

    # Check for private keys
    local key_count=$(find "$SSH_DIR" -maxdepth 1 -type f -name "id_*" ! -name "*.pub" 2>/dev/null | wc -l)
    if [ "$key_count" -eq 0 ]; then
        error "No SSH private keys found in $SSH_DIR"
        info "Looking for files like id_rsa, id_ed25519, etc."
        exit 1
    fi

    success "Found $key_count private key(s)"

    # List what will be backed up
    info "Files to backup:"
    ls -la "$SSH_DIR"/ 2>/dev/null | grep -E "^-" | awk '{print "  " $NF}'

    echo ""

    # Create backup directory
    mkdir -p "$BACKUP_DIR"

    # Warn if backup already exists
    if [ -f "$BACKUP_PATH" ]; then
        info "Existing backup found at $BACKUP_PATH"
        read -p "Overwrite? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Backup cancelled"
            exit 0
        fi
    fi

    step "Creating encrypted backup"
    info "You will be prompted to enter an encryption password"
    info "REMEMBER THIS PASSWORD - you'll need it to restore"
    echo ""

    # Create tarball and encrypt with GPG
    # Using symmetric encryption (password-based)
    tar -czf - -C "$HOME" .ssh 2>/dev/null | gpg --symmetric --cipher-algo AES256 -o "$BACKUP_PATH"

    if [ -f "$BACKUP_PATH" ]; then
        local size=$(ls -lh "$BACKUP_PATH" | awk '{print $5}')
        success "Backup created: $BACKUP_PATH ($size)"
        echo ""
        info "Store this file safely. You can copy it to:"
        echo "  - USB drive"
        echo "  - Cloud storage"
        echo "  - Another machine"
        echo ""
        info "The file is AES-256 encrypted - safe to store anywhere"
    else
        error "Backup failed"
        exit 1
    fi
}

# Restore SSH keys
do_restore() {
    step "Starting SSH keys restore"

    # Check if backup exists
    if [ ! -f "$BACKUP_PATH" ]; then
        error "Backup not found: $BACKUP_PATH"
        info "Set BACKUP_DIR if your backup is elsewhere:"
        echo "  BACKUP_DIR=/mnt/usb $0 restore"
        exit 1
    fi

    local size=$(ls -lh "$BACKUP_PATH" | awk '{print $5}')
    success "Found backup: $BACKUP_PATH ($size)"

    # Warn if SSH directory already has keys
    if [ -d "$SSH_DIR" ]; then
        local existing_keys=$(find "$SSH_DIR" -maxdepth 1 -type f -name "id_*" ! -name "*.pub" 2>/dev/null | wc -l)
        if [ "$existing_keys" -gt 0 ]; then
            info "Existing SSH keys found in $SSH_DIR"
            read -p "Overwrite existing keys? (y/N) " -n 1 -r
            echo ""
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                info "Restore cancelled"
                exit 0
            fi
            # Backup existing keys just in case
            step "Backing up existing keys to ${SSH_DIR}.old"
            rm -rf "${SSH_DIR}.old"
            cp -r "$SSH_DIR" "${SSH_DIR}.old"
        fi
    fi

    step "Decrypting and restoring SSH keys"
    info "Enter the password you used during backup"
    echo ""

    # Create SSH directory if needed
    mkdir -p "$SSH_DIR"

    # Decrypt and extract
    if gpg --decrypt "$BACKUP_PATH" 2>/dev/null | tar -xzf - -C "$HOME"; then
        success "SSH keys restored"
    else
        error "Restore failed - wrong password or corrupted backup"
        exit 1
    fi

    # Fix permissions (critical for SSH)
    step "Setting correct permissions"
    chmod 700 "$SSH_DIR"
    chmod 600 "$SSH_DIR"/id_* 2>/dev/null || true
    chmod 644 "$SSH_DIR"/*.pub 2>/dev/null || true
    chmod 600 "$SSH_DIR"/config 2>/dev/null || true
    chmod 600 "$SSH_DIR"/known_hosts 2>/dev/null || true

    success "Permissions fixed"

    # Verify
    echo ""
    info "Restored keys:"
    ls -la "$SSH_DIR"/ 2>/dev/null | grep -E "^-" | awk '{print "  " $NF}'

    echo ""
    success "SSH keys restored successfully"
    info "Test with: ssh -T git@github.com"
}

# Check status
do_check() {
    step "Checking SSH backup status"
    echo ""

    # Check SSH directory
    if [ -d "$SSH_DIR" ]; then
        local key_count=$(find "$SSH_DIR" -maxdepth 1 -type f -name "id_*" ! -name "*.pub" 2>/dev/null | wc -l)
        success "SSH directory exists: $SSH_DIR"
        info "Private keys found: $key_count"
        if [ "$key_count" -gt 0 ]; then
            echo ""
            info "Keys:"
            find "$SSH_DIR" -maxdepth 1 -type f -name "id_*" ! -name "*.pub" -exec basename {} \; | while read key; do
                echo "  $key"
            done
        fi
    else
        info "SSH directory not found: $SSH_DIR"
    fi

    echo ""

    # Check backup
    if [ -f "$BACKUP_PATH" ]; then
        local size=$(ls -lh "$BACKUP_PATH" | awk '{print $5}')
        local date=$(ls -lh "$BACKUP_PATH" | awk '{print $6, $7, $8}')
        success "Backup exists: $BACKUP_PATH"
        info "Size: $size"
        info "Date: $date"
    else
        info "No backup found at: $BACKUP_PATH"
    fi
}

# Main
main() {
    local command="${1:-}"

    check_dependencies

    case "$command" in
        backup)
            do_backup
            ;;
        restore)
            do_restore
            ;;
        check)
            do_check
            ;;
        *)
            usage
            exit 1
            ;;
    esac

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

main "$@"
