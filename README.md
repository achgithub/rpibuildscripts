# Raspberry Pi Build Scripts

Idempotent setup scripts for quickly rebuilding a Raspberry Pi server from scratch.

## Why?

I treat my Raspberry Pi as **disposable infrastructure**. Rather than carefully maintaining it, I can wipe and rebuild it anytime using these scripts. Everything important lives in Git.

## Scripts

| Script | Purpose |
|--------|---------|
| `go_setup_fixed.sh` | Install/update Go (auto-fetches latest version) |
| `postgresql_setup.sh` | Install and configure PostgreSQL for development |
| `redis_setup.sh` | Install and configure Redis |
| `ssh_keys_backup.sh` | Backup/restore SSH keys with AES-256 encryption |

## Usage

After a fresh Raspberry Pi OS install:

```bash
git clone git@github.com:achgithub/rpibuildscripts.git
cd rpibuildscripts
chmod +x *.sh

./go_setup_fixed.sh
./postgresql_setup.sh
./redis_setup.sh
```

All scripts are **idempotent** - safe to run multiple times. Run them again anytime to verify or repair an installation.

## SSH Keys

To preserve SSH keys across rebuilds:

```bash
# Before wiping - backup (you'll set a password)
./ssh_keys_backup.sh backup

# Copy ~/ssh_backup/ssh_keys_backup.tar.gz.gpg somewhere safe

# After fresh install - restore
./ssh_keys_backup.sh restore
```

## Features

- **Version tracking** - Each tool tracks its installed version in `~/`
- **Environment setup** - Automatically configures shell with necessary env vars
- **Coloured output** - Clear progress indication
- **Verification** - Tests that installations actually work

## Environment Variables

After running the scripts, these are available:

- **Go**: `GOROOT`, `GOPATH`, `PATH`
- **PostgreSQL**: `DATABASE_URL`, `PGHOST`, `PGPORT`, `PGUSER`, `PGDATABASE`
- **Redis**: `REDIS_URL`, `REDIS_HOST`, `REDIS_PORT`

Source them in a new terminal or run:
```bash
source ~/.bashrc
```

## License

MIT
