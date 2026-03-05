# AWS Configuration Sync

Sets up AWS CLI on employee MacBooks with automatic 1Password credential integration.

![Demo](demo.gif)

## Quick Start

```bash
curl -fsSL https://setup.northbuilt.com/aws | bash
```

## Prerequisites

1. **1Password desktop app installed**
2. **1Password CLI integration enabled:**
   - Open 1Password → Settings → Developer
   - Enable "Integrate with 1Password CLI"
3. **Full Disk Access for Terminal** (for initial setup):
   - System Settings → Privacy & Security → Full Disk Access
   - Add your terminal app (Terminal, iTerm, etc.)

## Using AWS

Once setup is complete, AWS commands just work:

```bash
# Default profile (NorthBuilt)
aws s3 ls

# Client profiles
aws s3 ls --profile donatefordough
aws s3 ls --profile retina
aws s3 ls --profile act
```

Credentials are fetched automatically from 1Password. MFA codes are retrieved automatically when needed.

## Available Profiles

| Profile | Client | Vault |
|---------|--------|-------|
| `default` / `northbuilt` | NorthBuilt | Employee |
| `donatefordough` | Donate For Dough | Donate For Dough |
| `retina` | Retina Consultants | Retina Consultants of Minnesota |
| `act` | ACT (Regenatrak) | Regenatrak |

## Menu Bar App

After setup, the NorthBuilt icon appears in your menu bar:

```
┌─────────────────────────────┐
│ Status: Synced              │
│ Last sync: 2 min ago        │
│ Update Available (v1.3.0)   │  ← Only shown when update ready
├─────────────────────────────┤
│ Sync Now              ⌘S    │
│ Check for Updates...        │
├─────────────────────────────┤
│ View Logs...          ⌘L    │
│ Open AWS Config       ⌘O    │
├─────────────────────────────┤
│ Notifications         ✓     │
│ Launch at Login       ✓     │
├─────────────────────────────┤
│ About NorthBuilt Sync       │
│ Quit                  ⌘Q    │
└─────────────────────────────┘
```

### Menu Items

| Item | Description |
|------|-------------|
| **Status** | Current sync status (Synced, Syncing, Error, Waiting for network) |
| **Last sync** | Time since last successful sync |
| **Update Available** | Shows when app update is ready (click to install) |
| **Sync Now** | Manually trigger a sync |
| **Check for Updates...** | Manually check for app updates |
| **View Logs...** | Opens Terminal with filtered log output |
| **Open AWS Config** | Opens ~/.aws/config in default editor |
| **Notifications** | Toggle failure/update notifications |
| **Launch at Login** | Toggle automatic startup at login |
| **About** | Shows version info |
| **Quit** | Closes the menu bar app |

### Features

| Feature | Description |
|---------|-------------|
| **Hourly Sync** | AWS config syncs automatically every hour |
| **Automatic Updates** | App checks for updates every 6 hours |
| **Self-Updating** | Updates download source, compile locally, restart automatically |
| **Network-Aware** | Skips sync when offline, resumes when connected |
| **Notifications** | Alerts on sync failures and available updates |
| **Launch at Login** | Uses macOS native SMAppService (System Settings visible) |
| **Preferences** | Settings persist across app restarts |

## Logs

View sync logs via the menu bar app (View Logs...) or manually:

```bash
# Last hour of logs
log show --predicate 'subsystem == "com.northbuilt.sync"' --last 1h --style compact

# Stream live logs
log stream --predicate 'subsystem == "com.northbuilt.sync"'
```

## How It Works

### Initial Setup

```bash
curl -fsSL https://setup.northbuilt.com/aws | bash
```

1. Installs Homebrew (if needed)
2. Installs tools: AWS CLI, jq, gum, glow, 1Password CLI
3. Downloads Swift source files
4. Compiles `aws-vault-1password` credential helper
5. Compiles `NorthBuiltSync.app` menu bar app
6. Creates app bundle with icons
7. Launches app and runs initial sync

### Hourly Sync Process

1. Check network connectivity (skip if offline)
2. Download `aws-config` template from GitHub Pages
3. Validate template (reject suspicious patterns)
4. Substitute `__HELPER_PATH__` with local path
5. Fetch MFA serial ARNs from 1Password (parallel)
6. Substitute `__MFA_SERIAL:Item:Vault__` placeholders
7. Write to `~/.aws/config` with 600 permissions
8. Update menu status

### AWS Command Flow

```
aws s3 ls
    ↓
AWS CLI reads ~/.aws/config
    ↓
credential_process = ~/.northbuilt/aws/aws-vault-1password "Item" "Vault"
    ↓
Helper calls: op item get "Item" --vault "Vault" --format json
    ↓
1Password returns credentials (prompts for auth if needed)
    ↓
Helper outputs JSON: {"Version":1,"AccessKeyId":"...","SecretAccessKey":"..."}
    ↓
AWS CLI uses credentials for API call
```

### Self-Update Process

1. App checks `version.json` every 6 hours
2. If new version available, shows "Update Available" in menu
3. User clicks update → confirmation dialog with release notes
4. App downloads new Swift source files
5. Compiles locally with `swiftc -O`
6. Backs up current binary
7. Replaces binary, helper, and icons
8. Restarts automatically

## Architecture

```
setup.northbuilt.com/aws/ (GitHub Pages)
├── index.html                  # Setup script (bash)
├── version.json                # Version info for auto-updates
├── aws-config                  # AWS config template with placeholders
├── aws-vault-1password.swift   # Credential helper source (~340 lines)
├── NorthBuiltSync.swift        # Menu bar app source (~1150 lines)
├── AppIcon.icns                # App icon (Finder, Activity Monitor)
├── MenuBarIcon.png             # Menu bar icon (18x18 @2x)
├── 1password-standard.md       # 1Password entry documentation
├── demo.gif                    # Animated demo for README
├── demo.tape                   # VHS tape file (regenerate with: vhs demo.tape)
└── readability.js              # Makes script pretty in browsers

~/.northbuilt/aws/ (on employee machines)
├── NorthBuiltSync.app/         # Menu bar app bundle
│   └── Contents/
│       ├── MacOS/NorthBuiltSync    # Compiled binary
│       ├── Resources/
│       │   ├── AppIcon.icns
│       │   └── MenuBarIcon.png
│       └── Info.plist
└── aws-vault-1password         # Compiled credential helper

~/.aws/config                   # Deployed AWS config (synced hourly)
```

## For Administrators

### Adding a New Client Profile

1. **Create 1Password entry** in the appropriate vault:
   - Item name: `AWS - Client Name`
   - Fields: `Access Key ID`, `Secret Access Key`
   - Optional: One-time password (TOTP), `MFA Serial ARN`
   - See [1password-standard.md](1password-standard.md) for field details

2. **Add profile to `aws-config`:**
   ```ini
   [profile clientname]
   credential_process = __HELPER_PATH__ "AWS - Client Name" "Vault-Name"
   mfa_process = __HELPER_PATH__ "AWS - Client Name" "Vault-Name" --otp
   mfa_serial = __MFA_SERIAL:AWS - Client Name:Vault-Name__
   region = us-east-1
   ```

3. **Commit and push** — employees receive the config update within an hour

### Releasing App Updates

1. Make changes to `NorthBuiltSync.swift` or `aws-vault-1password.swift`
2. Update `version.json`:
   ```json
   {
     "version": "1.3.0",
     "build": 4,
     "releaseDate": "2026-03-06",
     "releaseNotes": "Description of changes for users."
   }
   ```
3. Commit and push (requires 2+ approvals)
4. Employees receive update notification within 6 hours

### Files Reference

| File | Purpose |
|------|---------|
| `index.html` | Setup script (dual-purpose: webpage + bash) |
| `version.json` | Version info for auto-updates |
| `aws-config` | AWS config template with placeholders |
| `aws-vault-1password.swift` | Credential helper source |
| `NorthBuiltSync.swift` | Menu bar app source |
| `AppIcon.icns` | App icon (multi-resolution) |
| `MenuBarIcon.png` | Menu bar icon (36x36 for retina) |
| `demo.gif` | Animated demo for README |
| `demo.tape` | VHS source file for regenerating demo |
| `readability.js` | Syntax highlighting for browser viewing |
| `1password-standard.md` | 1Password entry format documentation |

## Troubleshooting

### "1Password CLI needs to be connected"

1. Open 1Password app
2. Go to Settings → Developer
3. Enable "Integrate with 1Password CLI"
4. Re-run setup

### Credentials not working

Check the 1Password entry has the correct field labels:
- `Access Key ID` (not `username`)
- `Secret Access Key` (not `password`)

Run validation:
```bash
~/.northbuilt/aws/aws-vault-1password "AWS - Client Name" "Vault-Name" --validate
```

### MFA not working

Ensure the 1Password entry has:
- One-time password (TOTP) configured
- `MFA Serial ARN` field with the ARN value

### "op would like to access data from other apps"

This macOS prompt appears when 1Password CLI first communicates with the 1Password app.

**For the menu bar app:**
1. When the prompt appears, click **Allow**
2. The permission persists - you won't be asked again

If you clicked "Don't Allow":
1. Go to System Settings → Privacy & Security → Automation
2. Find "NorthBuilt Sync" and enable the toggle for "1Password"

**For terminal usage:**
1. Click **Allow** when prompted
2. If you clicked "Don't Allow", find your terminal app in Automation settings

### Menu bar icon not showing

1. Check if the app is running: `pgrep -f NorthBuiltSync`
2. If not running, launch it: `open ~/.northbuilt/aws/NorthBuiltSync.app`
3. On MacBooks with notch: Cmd-drag menu bar icons to reorder (move NorthBuilt left)
4. Check logs: View Logs... from another menu bar app or Terminal

### Sync fails with "1Password may be locked"

1. Open 1Password app to unlock it
2. Click "Sync Now" in the menu bar app
3. If it still fails, check logs

### Sync fails with "Waiting for network"

The app detected no network connectivity. It will automatically retry when connection is restored.

### Update fails

1. Check logs for specific error
2. If compilation failed, ensure Xcode Command Line Tools are installed:
   ```bash
   xcode-select --install
   ```
3. Try manual update by re-running setup script

## Migration

### From Previous Bash-Based System

1. Re-run the setup script: `curl -fsSL https://setup.northbuilt.com/aws | bash`
2. The script automatically removes the old launchd service
3. The menu bar app replaces the background sync service

### From NorthBuiltAWSSync to NorthBuiltSync

The app was renamed. Re-running setup will:
1. Remove old `NorthBuiltAWSSync.app`
2. Install new `NorthBuiltSync.app`
3. Preserve your settings

## Uninstalling

```bash
# Quit the menu bar app
osascript -e 'quit app "NorthBuilt Sync"'

# Remove the app and config
rm -rf ~/.northbuilt/aws

# Optionally remove AWS config
rm -f ~/.aws/config

# Remove shell profile additions (optional)
# Edit ~/.zshrc and remove OP_ACCOUNT and PATH lines
```
