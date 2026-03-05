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
- Review changes carefully, especially to scripts

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

## Security Considerations

### Downloaded Content
The sync app downloads `aws-config` from `setup.northbuilt.com` over HTTPS. The trust model assumes:
- GitHub repository access is properly controlled (2+ approvers)
- GitHub Pages serves content integrity
- HTTPS protects against MITM attacks

### Credentials
- AWS credentials are fetched from 1Password on-demand, never stored on disk
- `~/.aws/config` contains only profile configuration and helper paths, not secrets
- The credential helper outputs secrets to stdout (required by AWS credential_process)

### Logging
- Logs are written to macOS unified logging (viewable in Console.app)
- Logs contain sync status and error messages, but not credentials
- Filter: `subsystem == "com.northbuilt.sync"`
