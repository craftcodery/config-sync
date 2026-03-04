# Workstation Configuration

Automated configuration management for employee workstations at NorthBuilt.

## Quick Start

Run this command on a new MacBook to set everything up:

```bash
curl -fsSL https://raw.githubusercontent.com/craftcodery/northbuilt-workstation-config/main/setup.sh | bash
```

This will:
1. Install required tools (AWS CLI, aws-vault, 1Password CLI, jq, gum, glow)
2. Clone this repository to `~/.craftcodery-config`
3. Deploy AWS configuration and helper scripts
4. Set up automatic config sync (every 4 hours)

## What Gets Installed

| Tool | Purpose |
|------|---------|
| AWS CLI v2 | AWS command-line access |
| aws-vault | STS session management, MFA handling |
| 1Password CLI | Credential/TOTP retrieval from 1Password |
| jq | JSON parsing |
| gum | Beautiful CLI prompts and spinners |
| glow | Render markdown in terminal |

## Daily Usage

### NorthBuilt AWS Account (SSO)

```bash
# First command of the day may prompt for SSO login (Touch ID)
aws s3 ls

# Explicitly login
aws sso login
```

### Client AWS Accounts

```bash
# Client without MFA
aws s3 ls --profile client-acme

# Client with MFA (TOTP fetched automatically from 1Password)
aws s3 ls --profile client-globex
```

### Check Current Identity

```bash
# NorthBuilt (default)
aws sts get-caller-identity

# Client account
aws sts get-caller-identity --profile client-acme
```

## Manual Sync

Configurations sync automatically every 4 hours. To force a sync:

```bash
~/.craftcodery-config/sync.sh
```

## View Sync Logs

```bash
cat ~/Library/Logs/craftcodery-config-sync.log
```

## Repository Structure

```
workstation-config/
├── README.md           # This file
├── setup.sh            # Initial bootstrap (run once)
├── sync.sh             # Config sync (runs automatically)
├── aws/
│   └── config          # AWS CLI configuration
├── bin/
│   └── aws-vault-1password  # Helper script for 1Password integration
└── launchd/
    └── com.craftcodery.config-sync.plist  # Scheduled sync agent
```

## Adding New Client Accounts

1. Add credentials to 1Password "Shared-AWS-Clients" vault:
   - Item name: `AWS - Client Name`
   - Username: Access Key ID
   - Password: Secret Access Key
   - One-time password: MFA secret (if required)

2. Add profile to `aws/config` in this repository:
   ```ini
   [profile client-newclient]
   credential_process = /usr/local/bin/aws-vault-1password "AWS - New Client" "Shared-AWS-Clients"
   region = us-east-1
   ```

   If MFA is required, also add:
   ```ini
   mfa_process = /usr/local/bin/aws-vault-1password "AWS - New Client" "Shared-AWS-Clients" --otp
   mfa_serial = arn:aws:iam::ACCOUNT_ID:mfa/USERNAME
   ```

3. Commit and push:
   ```bash
   git add aws/config
   git commit -m "Add AWS profile for New Client"
   git push
   ```

4. Employees will receive the update automatically within 4 hours, or can run:
   ```bash
   ~/.craftcodery-config/sync.sh
   ```

## Troubleshooting

### 1Password CLI not connected

```
Error: op account list failed
```

**Solution:** Open 1Password app → Settings → Developer → Enable "Integrate with 1Password CLI"

### SSO session expired

```
Error: SSO session associated with this profile has expired
```

**Solution:** Run `aws sso login` (will open browser for authentication)

### MFA not working

```
Error: MFA validation failed
```

**Solution:**
1. Verify TOTP is configured in 1Password entry
2. Check `mfa_serial` ARN is correct in aws/config
3. Try syncing config: `~/.craftcodery-config/sync.sh`

### Permission denied on /usr/local/bin

If sudo access is unavailable, scripts deploy to `~/.local/bin` instead. Add to PATH:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

## Support

For issues with this configuration, contact IT or open an issue in this repository.
