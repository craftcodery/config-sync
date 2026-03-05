# NorthBuilt Config Sync

Configuration sync tools for NorthBuilt employee workstations. Each tool keeps configurations up to date via 1Password integration.

## Available Tools

| Tool | Command | Status |
|------|---------|--------|
| [AWS](docs/aws/) | `curl -fsSL https://setup.northbuilt.com/aws \| bash` | Ready |
| [SSH](docs/ssh/) | `curl -fsSL https://setup.northbuilt.com/ssh \| bash` | Coming soon |

Or visit [setup.northbuilt.com](https://setup.northbuilt.com) to see all available setup scripts.

## Prerequisites

All setup scripts require:

1. **1Password desktop app installed**
2. **1Password CLI integration enabled:**
   - Open 1Password → Settings → Developer
   - Enable "Integrate with 1Password CLI"

## How It Works

Each tool follows the same pattern:

1. **Setup** — One-time install via curl command
2. **Sync** — Hourly launchd service keeps config updated
3. **Credentials** — Fetched from 1Password on demand

## Repository Structure

```
docs/                           # Served via GitHub Pages at setup.northbuilt.com
├── index.html                  # Landing page
├── CNAME                       # Custom domain config
└── [tool]/                     # Each tool has its own directory
    ├── README.md               # Tool-specific documentation
    ├── index.html              # Setup script (curl-able)
    ├── sync.sh                 # Sync script
    └── ...                     # Other tool-specific files
```

## Security

All downloaded files are verified against SHA256 checksums before deployment. See [SECURITY.md](SECURITY.md) for:

- Branch protection setup (required: 2+ approvers)
- Checksum verification details
- Trust model and incident response

## For Administrators

See individual tool READMEs for administration guides:

- [AWS Configuration](docs/aws/README.md)
- [SSH Configuration](docs/ssh/README.md) *(coming soon)*
