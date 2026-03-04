# NorthBuilt Workstation Configuration

Automated AWS configuration for NorthBuilt employee workstations.

## Quick Start

**Run this single command on your MacBook:**

```bash
curl -fsSL https://raw.githubusercontent.com/craftcodery/northbuilt-workstation-config/main/setup.sh | bash
```

That's it! The setup script will:

1. Install required tools (AWS CLI, 1Password CLI, jq, gum, glow)
2. Configure 1Password integration
3. Deploy AWS configuration with all client profiles
4. Set up automatic hourly sync

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
aws sts get-caller-identity

# Client profiles
aws sts get-caller-identity --profile donatefordough
aws sts get-caller-identity --profile retina
aws sts get-caller-identity --profile act
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
~/.craftcodery-config/sync.sh
```

## Logs

```bash
# Sync logs
cat ~/Library/Logs/craftcodery-config-sync.log

# Launchd service logs
cat ~/Library/Logs/craftcodery-config-sync-launchd.log
```

## Troubleshooting

### "1Password CLI needs to be connected"

1. Open 1Password app
2. Go to Settings → Developer
3. Enable "Integrate with 1Password CLI"
4. Re-run setup

### "Could not retrieve item from vault"

You may not have access to the vault. Contact IT to request access.

### MFA not working

1. Check the 1Password entry has a one-time password configured
2. Verify `MFA Serial ARN` field is set in the 1Password entry
3. Run sync to update: `~/.craftcodery-config/sync.sh`

### Credentials not working

Validate the 1Password entry is properly configured:

```bash
aws-vault-1password "AWS - Client Name" "Vault Name" --validate
```

## For Administrators

### Adding a New Client Profile

1. **Create 1Password entry** following [docs/1password-aws-standard.md](docs/1password-aws-standard.md)

2. **Validate the entry:**
   ```bash
   aws-vault-1password "AWS - New Client" "Vault-Name" --validate
   ```

3. **Add profile to `aws/config`:**
   ```ini
   [profile newclient]
   credential_process = __HELPER_PATH__ "AWS - New Client" "Vault-Name"
   mfa_process = __HELPER_PATH__ "AWS - New Client" "Vault-Name" --otp
   mfa_serial = __MFA_SERIAL:AWS - New Client:Vault-Name__
   region = us-east-1
   ```

4. **Commit and push** — employees receive the update within an hour

### Repository Structure

```
├── README.md                 # This file
├── setup.sh                  # One-time setup script
├── sync.sh                   # Config sync (runs hourly)
├── aws/
│   └── config                # AWS CLI configuration template
├── bin/
│   └── aws-vault-1password   # 1Password credential helper
├── docs/
│   └── 1password-aws-standard.md  # 1Password entry format
└── launchd/
    └── com.craftcodery.config-sync.plist  # (Template only)
```

### How It Works

1. **setup.sh** installs tools, clones this repo, runs initial sync, and sets up the hourly sync service

2. **sync.sh** pulls latest config from GitHub and deploys to `~/.aws/config`, substituting:
   - `__HELPER_PATH__` → path to helper script
   - `__MFA_SERIAL:Item:Vault__` → MFA ARN from 1Password

3. **aws-vault-1password** fetches credentials from 1Password when AWS CLI needs them

4. **launchd** runs sync.sh every hour to keep configs up to date

## Support

For issues, contact IT or open an issue in this repository.
