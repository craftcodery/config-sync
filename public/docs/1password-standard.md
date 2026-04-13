# 1Password AWS Credential Standard

This document defines the standard format for storing AWS IAM credentials in 1Password across the organization.

## Why Standardize?

- Enables automated credential retrieval via `aws-vault-1password` helper
- Ensures consistent security practices
- Makes onboarding new clients/projects straightforward
- Reduces human error in credential management

## Item Structure

Each 1Password entry stores **both** console login credentials AND programmatic access keys. This allows a single entry to serve both human logins (with browser autofill) and CLI automation.

### Console Credentials (built-in fields, for browser autofill)

| Field | Description |
|-------|-------------|
| `username` | IAM username for AWS Console login |
| `password` | Password for AWS Console login |

These are the default fields in a Login item. 1Password browser extension will autofill these on the AWS sign-in page.

### Programmatic Access Keys (required for CLI)

| Field Type | Label | Description |
|------------|-------|-------------|
| **Text** | `Access Key ID` | The AWS Access Key ID (starts with `AKIA...`) |
| **Text** | `Secret Access Key` | The AWS Secret Access Key (40 characters) |

These must be added as separate text fields. The `aws-vault-1password` helper script uses these fields (not `username`/`password`).

### Metadata Fields (optional)

| Field Type | Label | Description |
|------------|-------|-------------|
| **One-Time Password** | (TOTP) | MFA authenticator secret for accounts requiring MFA |
| **Text** | `AWS Account ID` | The 12-digit AWS account number |
| **Text** | `MFA Serial ARN` | Full ARN of the MFA device (for aws config) |
| **Text** | `Region` | Default AWS region for this account |
| **Notes** | | Any additional context about the account |

### Important: Console Credentials vs Access Keys

**These are NOT the same thing:**

| Credential Type | Purpose | Format |
|-----------------|---------|--------|
| Console Username/Password | Human login to AWS Console via browser | Any username + password |
| Access Key ID / Secret Access Key | Programmatic CLI/API access | `AKIA...` + 40-char secret |

The `aws-vault-1password` helper script **only uses Access Key ID and Secret Access Key**. Console credentials are stored for human reference but are not used by the automation.

To get programmatic access keys:
1. Log into AWS Console with Console Username/Password
2. Go to IAM → Users → [Username] → Security credentials
3. Create access key → Choose "Command Line Interface (CLI)"
4. Copy the Access Key ID and Secret Access Key to 1Password

## Naming Convention

**Format:** `AWS - [Client/Project Name]`

**Examples:**
- `AWS - Your Team`
- `AWS - Example Client`
- `AWS - Production`

## AWS Config Integration

Once credentials are stored following this standard, add to `public/config/aws-profiles.toml`:

```toml
[[profiles]]
name = "client-name"
region = "us-east-1"
output = "json"
item_title = "AWS - Client Name"
vault = "Employee"
has_mfa = true
```

The setup script generates the appropriate AWS config with credential_process directives.

## Security Best Practices

1. **Rotate keys regularly** - AWS recommends rotating access keys every 90 days
2. **Use least privilege** - Only grant necessary permissions to IAM users
3. **Enable MFA** - Always enable MFA on IAM users with console or CLI access
4. **Audit access** - Regularly review who has access to credential vaults
5. **Never commit keys** - Use this 1Password integration instead of storing keys in code

## Troubleshooting

### Helper script can't find credentials

Ensure field labels match exactly:
- `Access Key ID` (not `access_key_id` or `Username`)
- `Secret Access Key` (not `secret_access_key` or `Password`)

**Important:** The script does NOT use `username` or `password` fields. Those are reserved for console login credentials (for browser autofill). You must have separate text fields labeled `Access Key ID` and `Secret Access Key`.

Run validation to diagnose issues:
```bash
~/.yourteam/app/aws-vault-1password "AWS - Client Name" "Vault-Name" --validate
```

### Access Key ID doesn't look like an AWS key

If you see this warning, the `Access Key ID` field contains console login credentials instead of an actual AWS access key.

AWS access keys:
- Start with `AKIA` (IAM user key) or `ASIA` (temporary/STS key)
- Are exactly 20 characters

To fix:
1. Log into AWS Console with the console credentials
2. Go to IAM → Users → [Username] → Security credentials
3. Create a new access key for CLI use
4. Update the 1Password entry with the new Access Key ID and Secret Access Key

### MFA not working

1. Verify TOTP is configured in 1Password (shows rotating 6-digit code)
2. Check `mfa_serial` ARN matches the IAM user's MFA device
3. Ensure time sync is correct on your machine
