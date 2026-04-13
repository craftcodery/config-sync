import Foundation
import os.log

// MARK: - Logger

let logger = Logger(subsystem: "com.yourteam.config-sync", category: "sync")

// MARK: - Version

enum AppVersion {
    static let current = "2.0.0"
    static let build = 6
}

// MARK: - Configuration
//
// Central configuration for the Config Sync app. All organization-specific
// values are defined here and get sed-replaced during setup when the bash
// script compiles the Swift source. See index.html.template Phase 6.
//
// Template placeholders → sed replacements:
//   "Your Team"                    → $ORG_NAME
//   "Your Team Config Sync"        → $APP_NAME
//   "com.yourteam.config-sync"    → $BUNDLE_ID
//   "config.yourteam.example"         → $DOMAIN
//   ".yourteam"                   → $LOCAL_DIR
//   "your-org/config-sync" → $GITHUB_OWNER/$GITHUB_REPO
//   "your-team.1password.com"     → $OP_ACCOUNT_VALUE

enum Config {

    // MARK: - Branding

    static let orgName = "Your Team"
    static let bundleID = "com.yourteam.config-sync"

    // MARK: - GitHub

    static let githubOwner = "your-org"
    static let githubRepo = "config-sync"
    static let githubPathPrefix = "public"
    static let githubReleasesURL = "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest"

    // MARK: - Paths

    static let configDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".yourteam")
    static let awsConfigPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".aws/config")
    static let sshConfigPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
    static let sshConfigDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config.d")
    static let agentTomlPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/1Password/ssh/agent.toml")

    // MARK: - 1Password

    static let opAccount = ProcessInfo.processInfo.environment["OP_ACCOUNT"] ?? "your-team.1password.com"
    static let onePasswordAgentSocket = "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

    // MARK: - SSH

    static let sshHostsConfigName = "\(orgName.lowercased())-hosts"
    static let sshInclude1Password = "Include ~/.ssh/1Password/config"
    static let sshIncludeConfigDir = "Include ~/.ssh/config.d/*"

    // MARK: - Agent TOML Markers
    //
    // Used to delineate the managed section of agent.toml. Keys added by the
    // user outside these markers (e.g., personal GitHub signing keys) are
    // preserved across syncs.

    static let agentTomlBeginMarker = "# --- BEGIN Config Sync managed keys ---"
    static let agentTomlEndMarker = "# --- END Config Sync managed keys ---"

    // MARK: - AWS

    static let helperName = "aws-vault-1password"

    // MARK: - Sync Schedule

    static let syncHour = 8
    static let syncMinute = 0
    static let syncTimeZone = TimeZone(identifier: "America/Chicago")!
    static let updateCheckInterval: TimeInterval = 21600

    /// Calculate seconds until the next daily sync.
    static func secondsUntilNextSync() -> TimeInterval {
        let now = Date()
        var calendar = Calendar.current
        calendar.timeZone = syncTimeZone

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = syncHour
        components.minute = syncMinute
        components.second = 0

        guard let todaySyncTime = calendar.date(from: components) else {
            return 86400
        }

        let targetDate: Date
        if now >= todaySyncTime {
            targetDate = calendar.date(byAdding: .day, value: 1, to: todaySyncTime) ?? todaySyncTime.addingTimeInterval(86400)
        } else {
            targetDate = todaySyncTime
        }

        let interval = targetDate.timeIntervalSince(now)
        logger.notice("Next sync scheduled in \(Int(interval / 3600)) hours \(Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)) minutes")
        return max(interval, 60)
    }
}
