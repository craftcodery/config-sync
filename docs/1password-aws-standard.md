# 1Password AWS Credential Standard

This document defines the standard format for storing AWS IAM credentials in 1Password across the organization.

## Why Standardize?

- Enables automated credential retrieval via `aws-vault-1password` helper
- Ensures consistent security practices
- Makes onboarding new clients/projects straightforward
- Reduces human error in credential management

## Item Structure

### Required Fields

| Field Type | Label | Description |
|------------|-------|-------------|
| **Username** | `Access Key ID` | The AWS Access Key ID (starts with `AKIA...`) |
| **Password** | `Secret Access Key` | The AWS Secret Access Key |

### Optional Fields

| Field Type | Label | Description |
|------------|-------|-------------|
| **One-Time Password** | (TOTP) | MFA authenticator secret for accounts requiring MFA |
| **Text** | `AWS Account ID` | The 12-digit AWS account number |
| **Text** | `IAM Username` | The IAM user name |
| **Text** | `MFA Serial ARN` | Full ARN of the MFA device (for aws config) |
| **Text** | `Region` | Default AWS region for this account |
| **Notes** | | Any additional context about the account |

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

### Step 1: In 1Password, Create New Item

1. Click **+ New Item**
2. Select **Login** (or **API Credential** if available)
3. Name it following the convention: `AWS - [Client Name]`

### Step 2: Fill Required Fields

1. **Username field:**
   - Click the field label "username"
   - Rename it to `Access Key ID`
   - Enter the Access Key ID (e.g., `AKIAIOSFODNN7EXAMPLE`)

2. **Password field:**
   - Click the field label "password"
   - Rename it to `Secret Access Key`
   - Enter the Secret Access Key

### Step 3: Add MFA (If Required)

1. Click **+ Add More**
2. Select **One-Time Password**
3. Scan QR code or enter TOTP secret from AWS

### Step 4: Add Metadata Fields

1. Click **+ Add More** → **Text**
2. Add fields for:
   - `AWS Account ID`: The 12-digit account number
   - `IAM Username`: The IAM user name
   - `MFA Serial ARN`: `arn:aws:iam::[ACCOUNT_ID]:mfa/[USERNAME]`
   - `Region`: Default region (e.g., `us-east-1`)

### Step 5: Save

Save the item in the appropriate vault.

## Example Entry

```
Title: AWS - Donate For Dough
Vault: Donate For Dough

Fields:
  Access Key ID:     AKIAIOSFODNN7EXAMPLE
  Secret Access Key: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
  One-Time Password: ●●●●●● (TOTP configured)
  AWS Account ID:    123456789012
  IAM Username:      northbuilt-support
  MFA Serial ARN:    arn:aws:iam::123456789012:mfa/northbuilt-support
  Region:            us-east-1
```

## Updating Existing Entries

For existing AWS entries that don't follow this standard:

1. Open the item in 1Password
2. Rename the `username` field to `Access Key ID`
3. Rename the `password` field to `Secret Access Key`
4. Add missing metadata fields
5. Ensure TOTP is configured if MFA is required

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

The helper script also accepts legacy labels (`username`, `password`) for backwards compatibility.

### MFA not working

1. Verify TOTP is configured in 1Password (shows rotating 6-digit code)
2. Check `mfa_serial` ARN matches the IAM user's MFA device
3. Ensure time sync is correct on your machine
