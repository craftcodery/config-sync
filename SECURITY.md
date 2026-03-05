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
3. On affected machines, stop the sync service:
   ```bash
   launchctl unload ~/Library/LaunchAgents/com.northbuilt.aws-config-sync.plist
   ```
4. Review `~/.aws/config` and `~/.northbuilt/aws/` for unauthorized modifications
5. Rotate any potentially exposed credentials in 1Password
