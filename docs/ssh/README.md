# SSH Configuration Sync

Sets up SSH config on employee MacBooks with automatic 1Password key management.

> **Status:** Coming soon

## Quick Start

```bash
curl -fsSL https://setup.northbuilt.com/ssh | bash
```

## Prerequisites

1. **1Password desktop app installed**
2. **1Password CLI integration enabled:**
   - Open 1Password → Settings → Developer
   - Enable "Integrate with 1Password CLI"

## Planned Features

- [ ] SSH config deployment from central template
- [ ] SSH keys stored in 1Password
- [ ] Automatic key agent integration
- [ ] Per-client/project host configurations
- [ ] Hourly sync service (same pattern as AWS)

## How It Will Work

1. **Setup** (`curl setup.northbuilt.com/ssh | bash`)
   - Installs tools via Homebrew
   - Downloads sync script to `~/.northbuilt/ssh/`
   - Runs initial sync
   - Sets up hourly launchd service

2. **Sync** (runs hourly)
   - Downloads latest SSH config from `setup.northbuilt.com/ssh`
   - Deploys to `~/.ssh/config`

3. **SSH commands**
   - 1Password SSH agent provides keys
   - Config includes host aliases for common servers

## Architecture

```
setup.northbuilt.com/ssh/ (GitHub Pages)
├── index.html              # Setup script
├── sync.sh                 # Sync script
└── ssh-config              # SSH config template

~/.northbuilt/ssh/ (on employee machines)
└── sync.sh                 # Downloaded sync script

~/.ssh/config               # Deployed SSH config
```

## For Administrators

### Adding a New Host

*Documentation coming soon*

## Files

| File | Purpose |
|------|---------|
| `index.html` | Setup script (dual-purpose: webpage + bash) |
| `sync.sh` | Sync script (downloaded by setup) |
| `ssh-config` | SSH config template |
