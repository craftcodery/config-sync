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
- `AWS - Acme Corp`
- `AWS - Donate For Dough`
- `AWS - NorthBuilt Production`
- `AWS - Team Honey Badger`

## Vault Organization

Store AWS credentials in the **client/project-specific vault** where the item relates to that client's infrastructure.

| Vault | Use Case |
|-------|----------|
| `Shared` | Internal NorthBuilt AWS accounts |
| `[Client Name]` | Client-specific AWS credentials |
| `Engineering` | Development/deployment keys |

## Creating a New AWS Credential Entry

### Step 1: Create New Login Item

1. Click **+ New Item**
2. Select **Login**
3. Name it following the convention: `AWS - [Client Name]`

### Step 2: Fill Console Credentials (built-in fields)

Use the default `username` and `password` fields for console login:

1. **username**: Enter the IAM username
2. **password**: Enter the console login password

These enable browser autofill on the AWS sign-in page.

### Step 3: Add Programmatic Access Keys (Required for CLI)

Add these as separate text fields for CLI automation:

1. Click **+ Add More** → **Text**
2. Label: `Access Key ID`
3. Value: The AWS access key (e.g., `AKIAIOSFODNN7EXAMPLE`)

4. Click **+ Add More** → **Text**
5. Label: `Secret Access Key`
6. Value: The 40-character secret key

**Where to get access keys:** AWS Console → IAM → Users → [Username] → Security credentials → Create access key

### Step 4: Add MFA (If Required)

1. Click **+ Add More**
2. Select **One-Time Password**
3. Scan QR code or enter TOTP secret from AWS

### Step 5: Add Metadata Fields

1. Click **+ Add More** → **Text**
2. Add fields for:
   - `AWS Account ID`: The 12-digit account number
   - `MFA Serial ARN`: `arn:aws:iam::[ACCOUNT_ID]:mfa/[MFA_DEVICE_NAME]`

### Step 6: Save

Save the item in the appropriate vault.

## Example Entry

```
Title: AWS - Donate For Dough
Vault: Donate For Dough

Fields:
  # Built-in fields (for browser autofill on AWS Console)
  username:          Borthbuilt
  password:          ●●●●●●●●●●●●

  # Programmatic access (used by aws-vault-1password)
  Access Key ID:     AKIAUMWXUEIRD4PRWMUX
  Secret Access Key: ●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●●

  # MFA (used by both console and CLI)
  One-Time Password: ●●●●●● (TOTP configured)

  # Metadata
  AWS Account ID:    302173659682
  MFA Serial ARN:    arn:aws:iam::302173659682:mfa/1Password
```

**Key points:**
- `username`/`password` = Console login (browser autofill)
- `Access Key ID`/`Secret Access Key` = CLI automation (aws-vault-1password)
- These are different credentials and both are needed

## Updating Existing Entries

For existing AWS entries that don't follow this standard:

### If the entry only has console credentials (no access keys):

1. **Keep `username`/`password`** as-is (for browser autofill)
2. **Generate programmatic access keys:**
   - Log into AWS Console using the existing credentials
   - Go to IAM → Users → [Username] → Security credentials
   - Click "Create access key" → Select "Command Line Interface (CLI)"
   - Copy both values before closing the dialog (you can't see the secret again)
3. **Add the access keys to 1Password:**
   - Add text field `Access Key ID` with the access key (starts with `AKIA`)
   - Add text field `Secret Access Key` with the 40-character secret
4. Ensure TOTP is configured if MFA is required

### If the entry has access keys in `username`/`password` fields:

This is wrong - those fields should have console credentials for browser autofill.

1. Note down the access key values
2. Replace `username` with the IAM username (for console login)
3. Replace `password` with the console password
4. Add text field `Access Key ID` with the access key
5. Add text field `Secret Access Key` with the secret key

### Validate after updating:

```bash
aws-vault-1password "AWS - Client Name" "Vault-Name" --validate
```

## AWS Config Integration

Once credentials are stored following this standard, add to `aws/config`:

```ini
# Without MFA
[profile client-name]
credential_process = __HELPER_PATH__ "AWS - Client Name" "Vault-Name"
region = us-east-1

# With MFA
[profile client-name]
credential_process = __HELPER_PATH__ "AWS - Client Name" "Vault-Name"
mfa_process = __HELPER_PATH__ "AWS - Client Name" "Vault-Name" --otp
mfa_serial = arn:aws:iam::123456789012:mfa/northbuilt-support
region = us-east-1
```

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
aws-vault-1password "AWS - Client Name" "Vault-Name" --validate
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
