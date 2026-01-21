# Raspberry Pi Build Scripts

Idempotent setup scripts for rebuilding a disposable Raspberry Pi server from scratch.

## Philosophy

The Pi is **disposable** - it can be wiped and rebuilt at any time. These scripts ensure a fresh OS can be configured quickly and consistently. All scripts are idempotent (safe to rerun).

## Script Pattern

All scripts follow a consistent structure:

### Header
```bash
#!/bin/bash
# <Tool> Installation & Configuration for Raspberry Pi
# Idempotent - safe to run multiple times
# <Brief description>

set -e
```

### Output Functions
```bash
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

step() { echo -e "${BLUE}→ $1${NC}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
info() { echo -e "${YELLOW}ℹ $1${NC}"; }
error() { echo -e "${RED}✗ $1${NC}"; }
```

### Standard Features
- **Version tracking**: Store installed version in `~/.{tool}_installed_version`
- **Environment setup**: Create `~/.{tool}_env.sh` with exports, auto-add to shell configs
- **Idempotent checks**: Skip steps already completed, verify before acting
- **Service management**: Enable and start systemd services, wait for readiness
- **Verification**: Test the installation actually works before declaring success
- **Clean output**: Box header, colored steps, summary section at end

### Structure
1. Configuration variables at top
2. Helper functions (check installed, get version, etc.)
3. Install function
4. Configure function
5. Start/enable service function
6. Setup environment function
7. Verify function
8. `main()` orchestrates everything

## Current Scripts

| Script | Purpose | Version File | Env File |
|--------|---------|--------------|----------|
| `go_setup_fixed.sh` | Go language (downloads latest from go.dev) | `~/.go_installed_version` | `~/.go_env.sh` |
| `postgresql_setup.sh` | PostgreSQL database | `~/.postgresql_installed_version` | `~/.postgresql_env.sh` |
| `redis_setup.sh` | Redis cache/store | `~/.redis_installed_version` | `~/.redis_env.sh` |

## Environment Variables Set

### Go
- `GOROOT`, `GOPATH`, `PATH`, `GO111MODULE`, `GOPROXY`, `GOSUMDB`

### PostgreSQL
- `PGHOST`, `PGPORT`, `PGUSER`, `PGDATABASE`, `DATABASE_URL`

### Redis
- `REDIS_HOST`, `REDIS_PORT`, `REDIS_URL`

## Adding New Scripts

When creating a new setup script:

1. Copy the pattern from an existing script
2. Use the same color functions and output style
3. Create version tracking file in `~/`
4. Create environment file in `~/` and add to shell configs
5. Make it idempotent - check before acting
6. Include verification that actually tests functionality
7. Name it `{tool}_setup.sh`

## Usage

After fresh Pi OS install:
```bash
git clone git@github.com:achgithub/rpibuildscripts.git
cd rpibuildscripts
chmod +x *.sh
./go_setup_fixed.sh
./postgresql_setup.sh
./redis_setup.sh
```

Rerun anytime to verify/repair installations.
