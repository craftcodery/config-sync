# AWS Configuration Sync

Sets up AWS CLI on employee MacBooks with automatic 1Password credential integration.

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

After setup, a cloud icon appears in your menu bar with the following options:

| Item | Description |
|------|-------------|
| **Status** | Shows current sync status |
| **Last sync** | Time since last successful sync |
| **Sync Now** | Manually trigger a sync (Cmd+S) |
| **View Logs...** | Open Console.app for debug logs |
| **Open AWS Config** | Open ~/.aws/config in default editor |
| **Launch at Login** | Toggle automatic startup |
| **Quit** | Close the menu bar app |

### Status Icons

- **Cloud** - Idle/success
- **Rotating arrows** - Syncing in progress
- **Warning triangle** - Sync error (check logs)

## Logs

View sync logs in Console.app. Filter by subsystem:
```
com.northbuilt.sync
```

Or via command line:
```bash
log show --predicate 'subsystem == "com.northbuilt.sync"' --last 1h
```

## How It Works

1. **Setup** (`curl setup.northbuilt.com/aws | bash`)
   - Installs tools via Homebrew
   - Compiles native Swift applications
   - Creates menu bar app bundle
   - Launches menu bar app
   - Runs initial sync

2. **Menu Bar App** (runs continuously)
   - Syncs every hour automatically
   - Downloads latest AWS config from `setup.northbuilt.com/aws`
   - Compiles credential helper from source
   - Substitutes MFA serial ARNs from 1Password
   - Deploys to `~/.aws/config`

3. **AWS commands**
   - `credential_process` calls the credential helper
   - Helper fetches credentials from 1Password
   - MFA codes fetched automatically via `mfa_process`

## Architecture

```
setup.northbuilt.com/aws/ (GitHub Pages)
├── index.html                  # Setup script
├── aws-config                  # AWS config template
├── aws-vault-1password.swift   # Credential helper source
├── NorthBuiltSync.swift     # Menu bar app source
└── readability.js              # Makes script pretty in browsers

~/.northbuilt/aws/ (on employee machines)
├── NorthBuiltSync.app/      # Menu bar app (runs continuously)
│   └── Contents/
│       ├── MacOS/NorthBuiltSync
│       └── Info.plist
└── aws-vault-1password         # Compiled credential helper

~/.aws/config                   # Deployed AWS config (with substituted values)
```

## For Administrators

### Adding a New Client Profile

1. **Create 1Password entry** in the appropriate vault:
   - Item name: `AWS - Client Name`
   - Fields: `Access Key ID`, `Secret Access Key`
   - Optional: One-time password (TOTP), `MFA Serial ARN`
   - See [1password-standard.md](1password-standard.md) for details

2. **Add profile to `aws-config`:**
   ```ini
   [profile clientname]
   credential_process = __HELPER_PATH__ "AWS - Client Name" "Vault-Name"
   mfa_process = __HELPER_PATH__ "AWS - Client Name" "Vault-Name" --otp
   mfa_serial = __MFA_SERIAL:AWS - Client Name:Vault-Name__
   region = us-east-1
   ```

3. **Commit and push** — employees receive the update within an hour

### Files

| File | Purpose |
|------|---------|
| `index.html` | Setup script (dual-purpose: webpage + bash) |
| `aws-config` | AWS config template with placeholders |
| `aws-vault-1password.swift` | Credential helper source |
| `NorthBuiltSync.swift` | Menu bar app source |
| `readability.js` | Makes script pretty in browsers |
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

This macOS prompt appears when the 1Password CLI first communicates with the 1Password app.

**For the menu bar app:**
The app runs as `NorthBuilt Sync`, so macOS remembers your permission choice:

1. When the prompt appears, click **Allow**
2. The permission persists - you won't be asked again

If you clicked "Don't Allow":
1. Go to System Settings → Privacy & Security → Automation
2. Find "NorthBuilt Sync" and enable the toggle for "1Password"

**For terminal usage:**
If prompted when running `aws` commands directly:

1. Click **Allow** when prompted
2. If you clicked "Don't Allow", go to System Settings → Privacy & Security → Automation
3. Find your terminal app (Terminal, iTerm, etc.) and enable the toggle for "1Password"

### Menu bar icon not showing

1. Check if the app is running: `pgrep -f NorthBuiltSync`
2. If not running, launch it: `open ~/.northbuilt/aws/NorthBuiltSync.app`
3. Check for compilation errors in Console.app

### Sync fails with "1Password may be locked"

1. Open 1Password app to unlock it
2. Click "Sync Now" in the menu bar app
3. If it still fails, check logs in Console.app

## Migration from Previous Version

If you were using the previous bash-based system:
1. Re-run the setup script: `curl -fsSL https://setup.northbuilt.com/aws | bash`
2. The script automatically removes the old launchd service
3. The menu bar app replaces the background sync service

## Uninstalling

```bash
# Quit the menu bar app
osascript -e 'quit app "NorthBuilt Sync"'

# Remove the app and config
rm -rf ~/.northbuilt/aws

# Optionally remove AWS config
rm -f ~/.aws/config
```
