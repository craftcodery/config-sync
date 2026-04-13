# Config Sync

Unified AWS CLI and SSH configuration management for employee workstations. Native macOS menu bar app that syncs configurations via 1Password integration.

## Quick Start

```bash
curl -fsSL config.yourteam.example | bash
```

This single command installs and configures both AWS CLI and SSH.

## Features

- **Native macOS App**: Menu bar app built in Swift, compiled locally
- **Unified AWS + SSH**: One setup script configures everything
- **Automatic Sync**: Configuration syncs daily at 8:00 AM Central
- **Self-Updating**: App checks for updates and can update itself from source
- **1Password Integration**: Credentials fetched securely on-demand
- **Network-Aware**: Skips sync when offline, resumes when connected
- **Notifications**: Alerts for sync failures and available updates
- **Launch at Login**: Optional automatic startup

## Prerequisites

1. **1Password desktop app installed**
2. **1Password CLI integration enabled:**
   - Open 1Password → Settings → Developer
   - Enable "Integrate with 1Password CLI"
3. **GitHub account with access to this repository**

## How It Works

1. **Setup** — One-time install via curl command
   - Installs Homebrew, AWS CLI, GitHub CLI, 1Password CLI
   - Downloads Swift source files from this repo
   - Compiles natively on your machine
   - Launches menu bar app and runs initial sync

2. **Sync** — Menu bar app syncs daily (or manually via menu)
   - Downloads latest config templates (TOML files)
   - Generates AWS config (`~/.aws/config`)
   - Creates SSH keys in 1Password if missing
   - Generates SSH host definitions and 1Password agent config
   - Configures `~/.ssh/config` with IdentityAgent and Includes
   - Preserves user-managed SSH keys in agent.toml across syncs

3. **Updates** — App checks for updates every 6 hours
   - Notifies when update available
   - Re-run setup script to update

4. **Credentials** — Fetched from 1Password on demand
   - Never stored on disk
   - MFA codes retrieved automatically

## Repository Structure

```
config-sync/
├── public/                    # Deployed to GitHub Pages
│   ├── index.html.template    # Setup script (served at root URL)
│   ├── config.json            # Branding and organization settings
│   ├── app/                   # Swift menu bar application
│   │   ├── ConfigSync.swift   # Main app entry point and AppDelegate
│   │   ├── Core/              # Shared infrastructure
│   │   │   ├── Config.swift           # Configuration constants and paths
│   │   │   ├── GitHubClient.swift     # Private repo file download utility
│   │   │   ├── TOMLParser.swift       # Lightweight TOML parsing utility
│   │   │   ├── Preferences.swift      # UserDefaults wrapper
│   │   │   ├── NetworkMonitor.swift   # Network status monitoring
│   │   │   ├── NotificationManager.swift
│   │   │   ├── OnePasswordCLI.swift   # 1Password CLI wrapper
│   │   │   ├── SyncModule.swift       # Protocol and types
│   │   │   └── UpdateManager.swift    # App update checking
│   │   ├── Modules/           # Sync module implementations
│   │   │   ├── AWSModule.swift        # AWS config sync
│   │   │   └── SSHModule.swift        # SSH + agent.toml + key management
│   │   └── Helpers/           # CLI tools
│   │       └── aws-vault-1password.swift
│   ├── config/                # Configuration files (add your own)
│   │   ├── aws-profiles.toml  # AWS profile definitions
│   │   └── ssh-hosts.toml     # SSH host definitions
│   ├── assets/                # App icons (add your own)
│   └── docs/                  # Documentation
│       └── 1password-standard.md
├── .github/workflows/
│   └── deploy.yml             # GitHub Actions deployment
└── README.md
```

## Using This Template

This is a **template repository**. All branding is centralized in `public/config.json`. Update these values and GitHub Actions will automatically inject them into setup scripts during deployment.

### 1. Fork or Use as Template

### 2. Update `public/config.json`

```json
{
  "branding": {
    "orgName": "YourCompany",
    "appName": "YourCompany Config Sync",
    "appNameShort": "Config Sync",
    "bundleId": "com.yourcompany.config-sync",
    "domain": "config.yourcompany.com",
    "localDir": ".yourcompany",
    "tagline": "Config Sync • AWS + SSH • Powered by 1Password",
    "asciiLogo": ["..."]
  },
  "github": {
    "owner": "your-github-org",
    "repo": "your-repo-name",
    "pathPrefix": "public"
  },
  "onepassword": {
    "account": "yourcompany.1password.com"
  }
}
```

### 3. Update `public/CNAME`

Set your custom domain:
```
config.yourcompany.com
```

### 4. Add Configuration Files

Create `public/config/aws-profiles.toml` with your AWS profiles:

```toml
[[profiles]]
name = "default"
region = "us-east-1"
output = "json"
item_title = "AWS - YourCompany"
vault = "Employee"
has_mfa = true
```

Create `public/config/ssh-hosts.toml` with your SSH hosts:

```toml
[settings]
vault = "Employee"
key_type = "rsa4096"
account = "yourcompany.1password.com"

[[hosts]]
alias = "server-prod"
hostname = "server.example.com"
user = "deploy"
item_title = "SSH Key - Production"
description = "Production server"
add_key_url = "https://server.example.com/admin/keys"
```

### 5. Add App Icons

Add your icons to `public/assets/`:
- `AppIcon.icns` — macOS app icon
- `MenuBarIcon.png` — Menu bar icon (18x18 recommended)

### 6. Configure GitHub Pages

In your repository Settings → Pages:
- Source: **GitHub Actions**
- Custom domain: `config.yourcompany.com`

### 7. Configure DNS

```
config.yourcompany.com  CNAME  your-github-org.github.io
```

## Configuration Files

### aws-profiles.toml

Defines AWS profiles with 1Password item references:

```toml
[[profiles]]
name = "default"
region = "us-east-1"
output = "json"
item_title = "AWS - YourCompany"
vault = "Employee"
has_mfa = true
```

### ssh-hosts.toml

Defines SSH hosts with 1Password SSH key references:

```toml
[settings]
vault = "Employee"
key_type = "rsa4096"
account = "yourcompany.1password.com"

[[hosts]]
alias = "server-prod"
hostname = "server.example.com"
user = "deploy"
item_title = "SSH Key - Production"
description = "Production server"
add_key_url = "https://server.example.com/admin/keys"
```

## Files Generated on User Machine

```
~/.yourteam/
├── app/
│   ├── aws-vault-1password              # Credential helper
│   └── Your Team Config Sync.app/       # Menu bar app bundle
├── config/
│   ├── aws-profiles.toml
│   └── ssh-hosts.toml
└── logs/
    └── setup-*.log

~/.aws/config                             # AWS CLI configuration
~/.ssh/config.d/yourteam-hosts            # SSH host definitions
~/.config/1Password/ssh/agent.toml        # 1Password SSH agent config
```

## Development

### Modifying the Swift App

The app is compiled from source during setup. To test changes locally:

```bash
# Compile all modules together
swiftc -O -o ConfigSync \
    public/app/Core/*.swift \
    public/app/Modules/*.swift \
    public/app/ConfigSync.swift
```

### Module Structure

- **Core/Config.swift** — Configuration constants, paths, and branding values
- **Core/GitHubClient.swift** — Shared utility for downloading files from private repo via `gh api`
- **Core/TOMLParser.swift** — Lightweight parser for the TOML subset used by config files
- **Core/Preferences.swift** — UserDefaults wrapper for app state
- **Core/NetworkMonitor.swift** — Network connectivity monitoring
- **Core/NotificationManager.swift** — macOS notification handling
- **Core/OnePasswordCLI.swift** — 1Password CLI wrapper (`op` commands, key creation)
- **Core/SyncModule.swift** — Protocol and result types for sync modules
- **Core/UpdateManager.swift** — GitHub release checking
- **Modules/AWSModule.swift** — AWS config sync (generates `~/.aws/config`)
- **Modules/SSHModule.swift** — SSH config sync (keys, host config, agent.toml, `~/.ssh/config`)
- **ConfigSync.swift** — Main app, AppDelegate, menu UI, and legacy cleanup

### Deployment

Push to `main` branch triggers GitHub Actions deployment to GitHub Pages.

## Security

See [SECURITY.md](SECURITY.md) for:
- Branch protection setup (required: 2+ approvers)
- Trust model and incident response
- Self-update security considerations

## Template Processing

GitHub Actions (`deploy.yml`) automatically processes templates before deployment:

1. Reads `public/config.json` for all branding values
2. Replaces `{{PLACEHOLDER}}` tokens in `*.template` files
3. Generates final HTML files
4. Deploys to GitHub Pages

This means you only need to edit `config.json` — the setup scripts are automatically branded for your organization.

### Placeholders

| Placeholder | Source | Description |
|-------------|--------|-------------|
| `{{ORG_NAME}}` | `config.json` | Your organization name |
| `{{APP_NAME}}` | `config.json` | Full app name |
| `{{APP_NAME_SHORT}}` | `config.json` | Short app name |
| `{{BUNDLE_ID}}` | `config.json` | macOS bundle identifier |
| `{{DOMAIN}}` | `config.json` | Your domain |
| `{{LOCAL_DIR}}` | `config.json` | Local config directory name |
| `{{TAGLINE}}` | `config.json` | Your tagline |
| `{{OP_ACCOUNT}}` | `config.json` | 1Password account |
| `{{GITHUB_OWNER}}` | `config.json` | Your GitHub org |
| `{{GITHUB_REPO}}` | `config.json` | Your repo name |
| `{{ASCII_LOGO_LINE_XX}}` | `config.json` | Your ASCII art logo (lines 01-12) |

## For Administrators

### Adding a New AWS Profile

1. **Create 1Password entry** in the appropriate vault:
   - Item name: `AWS - Client Name`
   - Fields: `Access Key ID`, `Secret Access Key`
   - Optional: One-time password (TOTP), `MFA Serial ARN`
   - See [1password-standard.md](public/docs/1password-standard.md) for field details

2. **Add profile to `public/config/aws-profiles.toml`:**
   ```toml
   [[profiles]]
   name = "clientname"
   region = "us-east-1"
   output = "json"
   item_title = "AWS - Client Name"
   vault = "Employee"
   has_mfa = true
   ```

3. **Commit and push** — employees receive the config update within a day

### Adding a New SSH Host

1. **Create SSH key in 1Password** (or let the setup script create it)

2. **Add host to `public/config/ssh-hosts.toml`:**
   ```toml
   [[hosts]]
   alias = "server-prod"
   hostname = "server.example.com"
   user = "deploy"
   item_title = "SSH Key - Production"
   description = "Production server"
   add_key_url = "https://server.example.com/admin/keys"
   ```

3. **Commit and push** — employees receive the config update within a day

## Logs

View sync logs via the menu bar app (View Logs...) or manually:

```bash
# Last hour of logs
log show --predicate 'subsystem == "com.yourteam.config-sync"' --last 1h --style compact

# Stream live logs
log stream --predicate 'subsystem == "com.yourteam.config-sync"'
```

## Troubleshooting

### "1Password CLI needs to be connected"

1. Open 1Password app
2. Go to Settings → Developer
3. Enable "Integrate with 1Password CLI"
4. Re-run setup

### AWS credentials not working

Check the 1Password entry has the correct field labels:
- `Access Key ID` (not `username`)
- `Secret Access Key` (not `password`)

Run validation:
```bash
~/.yourteam/app/aws-vault-1password "AWS - Client Name" "Vault-Name" --validate
```

### MFA not working

Ensure the 1Password entry has:
- One-time password (TOTP) configured
- `MFA Serial ARN` field with the ARN value

### SSH key not found

1. Check if the key exists in 1Password
2. Verify the `item_title` in ssh-hosts.toml matches the 1Password item name
3. The setup script will offer to create missing keys

### "op would like to access data from other apps"

This macOS prompt appears when 1Password CLI first communicates with the 1Password app.

**For the menu bar app:**
1. When the prompt appears, click **Allow**
2. The permission persists - you won't be asked again

If you clicked "Don't Allow":
1. Go to System Settings → Privacy & Security → Automation
2. Find "Your Team Config Sync" and enable the toggle for "1Password"

### Menu bar icon not showing

1. Check if the app is running: `pgrep -f ConfigSync`
2. If not running, launch it: `open ~/.yourteam/app/Your\ Team\ Config\ Sync.app`
3. On MacBooks with notch: Cmd-drag menu bar icons to reorder (move icon left)

### Sync fails with "Waiting for network"

The app detected no network connectivity. It will automatically retry when connection is restored.

### Update fails

1. Check logs for specific error
2. If compilation failed, ensure Xcode Command Line Tools are installed:
   ```bash
   xcode-select --install
   ```
3. Try manual update by re-running setup script

## Uninstalling

```bash
# Quit the menu bar app
osascript -e 'quit app "Your Team Config Sync"'

# Remove the app and config
rm -rf ~/.yourteam

# Optionally remove AWS config
rm -f ~/.aws/config

# Optionally remove SSH config
rm -f ~/.ssh/config.d/yourteam-hosts

# Remove shell profile additions (optional)
# Edit ~/.zshrc and remove OP_ACCOUNT and PATH lines
```

## Creating Your ASCII Logo

1. Go to [patorjk.com/software/taag](https://patorjk.com/software/taag/)
2. Enter your organization name
3. Select the "ANSI Shadow" font
4. Copy each line into the `asciiLogo` array in `config.json`
5. The logo should be 12 lines (pad with empty strings if needed)
