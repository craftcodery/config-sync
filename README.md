# Config Sync

A template repository for employee workstation configuration management. Native macOS menu bar apps that keep configurations up to date via 1Password integration.

<!-- Update this URL after configuring your domain in config.json -->
![Demo](https://config.yourteam.example/aws/demo.gif)

## Overview

This repository provides a complete system for automatically distributing and maintaining configurations (AWS CLI, SSH, etc.) across employee MacBooks. Key features:

- **Native macOS Apps**: Menu bar apps built in Swift, compiled locally
- **Automatic Sync**: Configuration syncs daily at 8:00 AM Central
- **Self-Updating**: Apps check for updates and can update themselves from source
- **1Password Integration**: Credentials fetched securely on-demand
- **Network-Aware**: Skips sync when offline, resumes when connected
- **Notifications**: Alerts for sync failures and available updates
- **Launch at Login**: Optional automatic startup

## Available Tools

| Tool | Status |
|------|--------|
| [AWS](docs/aws/) | Ready |
| [SSH](docs/ssh/) | Coming soon |

## Getting Started

This is a **template repository**. To use it for your organization:

### 1. Create Your Repository

Fork or use this repository as a template to create your own copy.

### 2. Update Branding

Edit `docs/config.json` with your organization's values:

```json
{
  "branding": {
    "orgName": "YourCompany",
    "appName": "YourCompany Config Sync",
    "appNameShort": "Config Sync",
    "bundleId": "com.yourcompany.config-sync",
    "domain": "config.yourcompany.com",
    "localDir": ".yourcompany",
    "tagline": "AWS Config Sync • Powered by 1Password",
    "asciiLogo": [
      "Line 1 of your ASCII art...",
      "Line 2...",
      "..."
    ]
  },
  "github": {
    "owner": "your-github-org",
    "repo": "your-repo-name"
  },
  "onepassword": {
    "account": "yourcompany.1password.com"
  }
}
```

### 3. Update Domain

Edit `docs/CNAME` with your custom domain:
```
config.yourcompany.com
```

### 4. Configure AWS Profiles

Edit `docs/aws/aws-config` with your AWS profiles and 1Password item references.

### 5. Set Up GitHub Pages

In your repository Settings → Pages:
- Source: **GitHub Actions** (not "Deploy from branch")
- Custom domain: `config.yourcompany.com`

### 6. Configure DNS

Point your domain to GitHub Pages:
```
config.yourcompany.com  CNAME  your-github-org.github.io
```

## Prerequisites

All setup scripts require:

1. **1Password desktop app installed**
2. **1Password CLI integration enabled:**
   - Open 1Password → Settings → Developer
   - Enable "Integrate with 1Password CLI"
3. **Automation permission for 1Password** (one-time approval):
   - When you see "op would like to access data from other apps", click **Allow**

## How It Works

Each tool follows the same pattern:

1. **Setup** — One-time install via curl command
   - Downloads Swift source files
   - Compiles natively on your machine
   - Creates menu bar app bundle
   - Launches and runs initial sync

2. **Sync** — Menu bar app syncs daily (or manually via menu)
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
docs/                           # Served via GitHub Pages
├── index.html                  # Landing page
├── CNAME                       # Custom domain config
├── config.json                 # Centralized branding configuration (single source of truth)
└── [tool]/                     # Each tool has its own directory
    ├── README.md               # Tool-specific documentation
    ├── index.html.template     # Setup script template (processed by GitHub Actions)
    ├── *.swift                 # Swift source files (compiled during setup)
    └── *.icns, *.png           # App and menu bar icons

.github/workflows/
└── deploy.yml                  # Processes templates, generates demo, deploys to GitHub Pages
```

## Template Processing

GitHub Actions (`deploy.yml`) automatically processes templates before deployment:

1. Reads `config.json` for all branding values
2. Replaces `{{PLACEHOLDER}}` tokens in `*.template` files
3. Generates final HTML files
4. Deploys to GitHub Pages

This means you only need to edit `config.json` — the setup scripts are automatically branded for your organization.

### Placeholders

| Placeholder | Source | Description |
|-------------|--------|-------------|
| `{{ORG_NAME}}` | `config.json` | Your organization name |
| `{{DOMAIN}}` | `config.json` | Your domain |
| `{{GITHUB_OWNER}}` | `config.json` | Your GitHub org |
| `{{GITHUB_REPO}}` | `config.json` | Your repo name |
| `{{ASCII_LOGO_LINE_XX}}` | `config.json` | Your ASCII art logo (lines 01-12) |
| `{{TAGLINE}}` | `config.json` | Your tagline |

## Files to Customize

| File | What to change |
|------|----------------|
| `docs/config.json` | All branding values including ASCII logo (required) |
| `docs/CNAME` | Your custom domain (required) |
| `docs/aws/aws-config` | Your AWS profiles and 1Password items |
| `docs/aws/AppIcon.icns` | Your app icon |
| `docs/aws/MenuBarIcon.png` | Your menu bar icon |

## Creating Your ASCII Logo

1. Go to [patorjk.com/software/taag](https://patorjk.com/software/taag/)
2. Enter your organization name
3. Select the "ANSI Shadow" font
4. Copy each line into the `asciiLogo` array in `config.json`
5. The logo should be 12 lines (pad with empty strings if needed)

## Releasing Updates

1. Make changes to Swift source files
2. Commit with descriptive message
3. Push to main
4. GitHub Actions deploys updated files to GitHub Pages
5. Users receive update notification within 6 hours (apps check for source changes via `gh api`)

## Security

See [SECURITY.md](SECURITY.md) for:

- Branch protection setup
- Trust model and incident response
- Self-update security considerations

## Documentation

- [AWS Configuration](docs/aws/README.md)
- [SSH Configuration](docs/ssh/README.md) *(coming soon)*
- [1Password Credential Standard](docs/aws/1password-standard.md)
