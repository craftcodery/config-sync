# Security

This repository contains scripts that run automatically on employee machines. Security is critical.

## Branch Protection (Required)

Configure these settings in GitHub: **Settings → Branches → Add rule** for `main`:

- [x] **Require a pull request before merging**
  - [x] Require approvals: **2**
  - [x] Dismiss stale pull request approvals when new commits are pushed
  - [x] Require approval of the most recent reviewable push
- [x] **Require status checks to pass before merging** *(if CI is configured)*
- [x] **Do not allow bypassing the above settings**

This ensures no single person can push malicious code to employee machines.

## Trust Model

**Anyone who can merge to `main` can run code on all employee machines.**

Keep this group small and trusted:
- Limit repository write access
- Require 2+ approvals for all changes
- Review changes carefully, especially to Swift source files

### Compile-From-Source Model

Unlike traditional app distribution, this system:
1. Downloads Swift **source code** (not pre-built binaries)
2. Compiles locally on each employee's machine
3. Runs the locally-compiled binary

This provides transparency - any employee can inspect the exact code running on their machine.

## Incident Response

If you suspect the repository has been compromised:

1. **Immediately** revoke write access for suspected accounts
2. Check recent commits and PRs for unauthorized changes
3. On affected machines, stop the menu bar app:
   ```bash
   osascript -e 'quit app "NorthBuilt Sync"'
   ```
4. Review `~/.aws/config` and `~/.northbuilt/aws/` for unauthorized modifications
5. Rotate any potentially exposed credentials in 1Password
6. After remediation, have users re-run setup to get clean binaries

## Security Considerations

### Downloaded Content

The sync app downloads from `setup.northbuilt.com` over HTTPS:
- `aws-config` template (hourly)
- `version.json` for update checks (every 6 hours)
- Swift source files (during updates)

The trust model assumes:
- GitHub repository access is properly controlled (2+ approvers)
- GitHub Pages serves content with integrity
- HTTPS protects against MITM attacks

### Self-Updating

The app can update itself by:
1. Checking `version.json` for new versions
2. Downloading new Swift source files
3. Compiling locally with `swiftc`
4. Replacing its own binary and restarting

**Security implications:**
- Updates go through the same review process as initial setup
- Source is always visible and auditable
- Compilation happens locally (no pre-built binaries)
- Users see notification before update installs
- Users can skip versions if concerned

### Credentials

- AWS credentials are fetched from 1Password on-demand, never stored on disk
- `~/.aws/config` contains only profile configuration and helper paths, not secrets
- The credential helper outputs secrets to stdout (required by AWS `credential_process`)
- Secrets are never logged (privacy annotations in logging code)

### Logging

- Logs are written to macOS unified logging (viewable in Console.app or Terminal)
- Logs contain sync status and error messages, but not credentials
- Item names from 1Password are marked with `privacy: .private` for redaction
- Filter: `subsystem == "com.northbuilt.sync"`

### Network Security

- All downloads use HTTPS
- App is network-aware and skips operations when offline
- No sensitive data transmitted (credentials stay local)

## Code Review Checklist

When reviewing PRs that modify Swift source files, verify:

- [ ] No hardcoded credentials or secrets
- [ ] No suspicious network requests to unknown hosts
- [ ] No file operations outside expected directories
- [ ] No shell command injection vulnerabilities
- [ ] Logging doesn't expose sensitive data
- [ ] Changes match the stated purpose of the PR
