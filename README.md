# NorthBuilt Config Sync

Configuration sync tools for NorthBuilt employee workstations. Native macOS menu bar apps that keep configurations up to date via 1Password integration.

![Demo](docs/aws/demo.gif)

## Available Tools

| Tool | Command | Status |
|------|---------|--------|
| [AWS](docs/aws/) | `curl -fsSL https://setup.northbuilt.com/aws \| bash` | Ready |
| [SSH](docs/ssh/) | `curl -fsSL https://setup.northbuilt.com/ssh \| bash` | Coming soon |

Or visit [setup.northbuilt.com](https://setup.northbuilt.com) to see all available setup scripts.

## Features

- **Native macOS Apps**: Menu bar apps built in Swift, compiled locally
- **Automatic Sync**: Configuration syncs hourly in the background
- **Self-Updating**: Apps check for updates and can update themselves from source
- **1Password Integration**: Credentials fetched securely on-demand
- **Network-Aware**: Skips sync when offline, resumes when connected
- **Notifications**: Alerts for sync failures and available updates
- **Launch at Login**: Optional automatic startup

## Prerequisites

All setup scripts require:

1. **1Password desktop app installed**
2. **1Password CLI integration enabled:**
   - Open 1Password → Settings → Developer
   - Enable "Integrate with 1Password CLI"
3. **Automation permission for 1Password** (one-time approval):
   - When you see "op would like to access data from other apps", click **Allow**
   - This grants permission to the sync app (`NorthBuilt Sync`) - the choice persists
   - If you clicked "Don't Allow", go to System Settings → Privacy & Security → Automation and enable the toggle for "1Password" under "NorthBuilt Sync"

## How It Works

Each tool follows the same pattern:

1. **Setup** — One-time install via curl command
   - Downloads Swift source files
   - Compiles natively on your machine
   - Creates menu bar app bundle
   - Launches and runs initial sync

2. **Sync** — Menu bar app syncs hourly (or manually via menu)
   - Downloads latest config template
   - Substitutes values from 1Password
   - Deploys to appropriate location

3. **Updates** — App checks for updates every 6 hours
   - Notifies when update available
   - Downloads new source, compiles, restarts automatically
   - Maintains "compile from source" trust model

4. **Credentials** — Fetched from 1Password on demand
   - Never stored on disk
   - MFA codes retrieved automatically

## Repository Structure

```
docs/                           # Served via GitHub Pages at setup.northbuilt.com
├── index.html                  # Landing page
├── CNAME                       # Custom domain config
└── [tool]/                     # Each tool has its own directory
    ├── README.md               # Tool-specific documentation
    ├── index.html              # Setup script (curl-able)
    ├── version.json            # Version info for auto-updates
    ├── *.swift                 # Swift source files (compiled during setup)
    └── *.icns, *.png           # App and menu bar icons
```

## Security

See [SECURITY.md](SECURITY.md) for:

- Branch protection setup (required: 2+ approvers)
- Trust model and incident response
- Self-update security considerations

## For Administrators

See individual tool READMEs for administration guides:

- [AWS Configuration](docs/aws/README.md)
- [SSH Configuration](docs/ssh/README.md) *(coming soon)*

### Releasing Updates

1. Make changes to Swift source files
2. Update `version.json` with new version number and release notes
3. Commit and push (requires 2+ approvals)
4. Users receive update notification within 6 hours
