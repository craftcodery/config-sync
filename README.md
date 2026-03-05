# NorthBuilt Config Sync

Automated AWS configuration sync for NorthBuilt employee workstations.

## Quick Start

**Run this single command on your MacBook:**

```bash
curl -fsSL https://setup.northbuilt.com | bash
```

Or visit [setup.northbuilt.com](https://setup.northbuilt.com) in your browser to see the script.

## Prerequisites

Before running setup, ensure:

1. **1Password app is installed** and you're signed in
2. **1Password CLI integration is enabled:**
   - Open 1Password → Settings → Developer
   - Enable "Integrate with 1Password CLI"

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

## Manual Sync

Configurations sync automatically every hour. To force a sync:

```bash
~/.northbuilt/sync.sh
```

## Logs

```bash
cat ~/Library/Logs/northbuilt-config-sync.log
```

## How It Works

1. **Setup** (`curl setup.northbuilt.com | bash`)
   - Installs tools via Homebrew
   - Downloads sync script to `~/.northbuilt/`
   - Runs initial sync
   - Sets up hourly launchd service

2. **Sync** (runs hourly)
   - Downloads latest AWS config from `setup.northbuilt.com`
   - Downloads latest helper script
   - Substitutes MFA serial ARNs from 1Password
   - Deploys to `~/.aws/config`

3. **AWS commands**
   - `credential_process` calls the helper script
   - Helper fetches credentials from 1Password
   - MFA codes fetched automatically via `mfa_process`

## Architecture

```
setup.northbuilt.com (GitHub Pages)
├── index.html        # Setup script
├── sync.sh           # Sync script
├── aws-config        # AWS config template
└── aws-vault-1password  # Credential helper

~/.northbuilt/ (on employee machines)
├── sync.sh           # Downloaded sync script
└── aws-vault-1password  # Downloaded helper

~/.aws/config         # Deployed AWS config (with substituted values)
```

## For Administrators

### Adding a New Client Profile

1. **Create 1Password entry** in the appropriate vault:
   - Item name: `AWS - Client Name`
   - Fields: `Access Key ID`, `Secret Access Key`
   - Optional: One-time password (TOTP), `MFA Serial ARN`

2. **Add profile to `docs/aws-config`:**
   ```ini
   [profile clientname]
   credential_process = __HELPER_PATH__ "AWS - Client Name" "Vault-Name"
   mfa_process = __HELPER_PATH__ "AWS - Client Name" "Vault-Name" --otp
   mfa_serial = __MFA_SERIAL:AWS - Client Name:Vault-Name__
   region = us-east-1
   ```

3. **Commit and push** — employees receive the update within an hour

### Files in This Repo

```
docs/                    # Served via GitHub Pages at setup.northbuilt.com
├── index.html           # Setup script (dual-purpose: webpage + bash)
├── readability.js       # Makes script pretty in browsers
├── sync.sh              # Sync script (downloaded by setup)
├── aws-config           # AWS config template
├── aws-vault-1password  # Credential helper script
└── CNAME                # Custom domain config
```

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

### MFA not working

Ensure the 1Password entry has:
- One-time password (TOTP) configured
- `MFA Serial ARN` field with the ARN value
