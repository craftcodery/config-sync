import Foundation

// MARK: - SSH Module
//
// Manages SSH configuration by:
//   1. Ensuring SSH keys exist in 1Password (creating if missing)
//   2. Generating ~/.ssh/config.d/<org>-hosts with host definitions
//   3. Generating ~/.config/1Password/ssh/agent.toml (preserving user keys)
//   4. Ensuring ~/.ssh/config has the required IdentityAgent and Include entries

actor SSHModule: SyncModule {
    nonisolated var name: String { "SSH" }

    private let opCLI = OnePasswordCLI()
    private let github = GitHubClient()

    // MARK: - Errors

    enum SSHError: Error, LocalizedError {
        case configGenerationFailed(String)
        case sshConfigCorrupted(String)

        var errorDescription: String? {
            switch self {
            case .configGenerationFailed(let reason): return "SSH config generation failed: \(reason)"
            case .sshConfigCorrupted(let reason): return "SSH config corrupted: \(reason)"
            }
        }
    }

    // MARK: - Data Structures

    private struct SSHSettings {
        var vault: String = "Employee"
        var keyType: String = "ed25519"
        var account: String = Config.opAccount
    }

    private struct HostEntry {
        var alias: String = ""
        var hostname: String = ""
        var user: String = ""
        var itemTitle: String = ""
        var description: String = ""
        var addKeyURL: String = ""

        var isValid: Bool {
            !alias.isEmpty && !hostname.isEmpty && !user.isEmpty && !itemTitle.isEmpty
        }
    }

    // MARK: - Sync

    func sync() async -> SyncResult {
        guard NetworkMonitor.shared.isConnected else {
            logger.notice("SSH sync skipped: no network")
            return .skipped("No network")
        }

        logger.notice("Starting SSH sync")

        do {
            try FileManager.default.createDirectory(at: Config.sshConfigDir, withIntermediateDirectories: true)

            try await opCLI.checkAuthenticated()
            logger.notice("1Password authenticated")

            let hostsToml = try await github.download(filePath: "config/ssh-hosts.toml")
            logger.notice("Downloaded ssh-hosts.toml")

            // Parse configuration
            let settings = parseSettings(hostsToml)
            let hosts = parseHosts(hostsToml)
            logger.notice("Parsed \(hosts.count) SSH host entries")

            // Ensure SSH keys exist in 1Password (create if missing)
            for host in hosts {
                await ensureKeyExists(host: host, settings: settings)
            }

            // Generate and deploy config files
            let (sshConfig, agentConfig) = generateConfigs(hosts: hosts, settings: settings)

            try deploySshHostConfig(sshConfig)
            try deployAgentToml(agentConfig)
            try ensureMainSshConfig()

            return .success("SSH synced")

        } catch {
            logger.error("SSH sync failed: \(error.localizedDescription)")
            return .failure(error.localizedDescription)
        }
    }

    // MARK: - TOML Parsing

    private func parseSettings(_ toml: String) -> SSHSettings {
        let raw = TOMLParser.parseSettings(toml)
        var settings = SSHSettings()
        if let vault = raw["vault"] { settings.vault = vault }
        if let keyType = raw["key_type"] { settings.keyType = keyType }
        if let account = raw["account"] { settings.account = account }
        logger.notice("SSH settings: vault=\(settings.vault), keyType=\(settings.keyType)")
        return settings
    }

    private func parseHosts(_ toml: String) -> [HostEntry] {
        let entries = TOMLParser.parseArrayOfTables(toml, section: "hosts")
        return entries.map { entry in
            HostEntry(
                alias: entry["alias"] ?? "",
                hostname: entry["hostname"] ?? "",
                user: entry["user"] ?? "",
                itemTitle: entry["item_title"] ?? "",
                description: entry["description"] ?? "",
                addKeyURL: entry["add_key_url"] ?? ""
            )
        }
    }

    // MARK: - SSH Key Management

    private func ensureKeyExists(host: HostEntry, settings: SSHSettings) async {
        guard !host.itemTitle.isEmpty else { return }

        let exists = await opCLI.itemExists(title: host.itemTitle, vault: settings.vault)
        if exists {
            logger.notice("Found SSH key: \(host.itemTitle)")
            return
        }

        logger.notice("Creating SSH key: \(host.itemTitle)")
        do {
            try await opCLI.createSSHKey(
                title: host.itemTitle,
                vault: settings.vault,
                keyType: settings.keyType,
                alias: host.alias,
                description: host.description
            )
            logger.notice("Created SSH key: \(host.itemTitle)")

            // Notify user if they need to add the public key somewhere
            if let publicKey = try? await opCLI.getPublicKey(title: host.itemTitle, vault: settings.vault),
               !host.addKeyURL.isEmpty {
                logger.notice("ACTION REQUIRED: Add public key for \(host.description) at \(host.addKeyURL)")
                logger.notice("Public key: \(publicKey)")

                NotificationManager.shared.sendNotification(
                    title: "SSH Key Created: \(host.itemTitle)",
                    body: "Add the public key to \(host.description). Check logs for details."
                )
            }
        } catch {
            logger.error("Failed to create SSH key \(host.itemTitle): \(error.localizedDescription)")
        }
    }

    // MARK: - Config Generation

    private func generateConfigs(hosts: [HostEntry], settings: SSHSettings) -> (sshConfig: String, agentConfig: String) {
        var sshConfig = "# \(Config.orgName) SSH Host Definitions\n"
        sshConfig += "# Generated by \(Config.orgName) Config Sync\n"
        sshConfig += "# DO NOT EDIT - regenerate by re-running sync\n\n"

        var agentConfig = "\(Config.agentTomlBeginMarker)\n\n"

        for host in hosts {
            guard host.isValid else {
                logger.warning("Skipping incomplete SSH host: \(host.alias.isEmpty ? "(no alias)" : host.alias)")
                continue
            }

            sshConfig += "Host \(host.alias)\n"
            sshConfig += "    HostName \(host.hostname)\n"
            sshConfig += "    User \(host.user)\n\n"

            let label = host.description.isEmpty ? host.alias : host.description
            agentConfig += "# \(label)\n"
            agentConfig += "[[ssh-keys]]\n"
            agentConfig += "item = \"\(host.itemTitle)\"\n"
            agentConfig += "vault = \"\(settings.vault)\"\n"
            agentConfig += "account = \"\(settings.account)\"\n\n"
        }

        return (sshConfig, agentConfig)
    }

    // MARK: - File Deployment

    /// Deploy SSH host config to ~/.ssh/config.d/<org>-hosts
    private func deploySshHostConfig(_ sshConfig: String) throws {
        let path = Config.sshConfigDir.appendingPathComponent(Config.sshHostsConfigName)
        try sshConfig.write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        logger.notice("Deployed SSH host config")
    }

    /// Deploy agent.toml, preserving user-managed keys outside the managed markers.
    private func deployAgentToml(_ agentConfig: String) throws {
        let agentDir = Config.agentTomlPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)

        let managedSection = agentConfig + Config.agentTomlEndMarker + "\n"
        let finalConfig: String

        if FileManager.default.fileExists(atPath: Config.agentTomlPath.path),
           let existing = try? String(contentsOf: Config.agentTomlPath, encoding: .utf8),
           let beginRange = existing.range(of: Config.agentTomlBeginMarker),
           let endRange = existing.range(of: Config.agentTomlEndMarker) {
            // Preserve content before BEGIN and after END markers
            let beforeMarker = String(existing[existing.startIndex..<beginRange.lowerBound])
            let afterEnd = existing[endRange.upperBound...]
            let afterMarker: String
            if let newlineIndex = afterEnd.firstIndex(of: "\n") {
                afterMarker = String(afterEnd[afterEnd.index(after: newlineIndex)...])
            } else {
                afterMarker = ""
            }
            finalConfig = beforeMarker + managedSection + afterMarker
            logger.notice("Preserved user-managed keys in agent.toml")
        } else {
            // New file or legacy file without markers
            finalConfig = "# 1Password SSH Agent Configuration\n"
                + "# https://developer.1password.com/docs/ssh/agent/config\n\n"
                + managedSection
        }

        try finalConfig.write(to: Config.agentTomlPath, atomically: true, encoding: .utf8)
        logger.notice("Deployed agent.toml")
    }

    /// Ensure ~/.ssh/config has 1Password IdentityAgent and required Include directives.
    private func ensureMainSshConfig() throws {
        let configPath = Config.sshConfigPath
        let fm = FileManager.default

        if !fm.fileExists(atPath: configPath.path) {
            let content = "Host *\n"
                + "    IdentityAgent \"\(Config.onePasswordAgentSocket)\"\n\n"
                + "\(Config.sshInclude1Password)\n"
                + "\(Config.sshIncludeConfigDir)\n"
            try content.write(to: configPath, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configPath.path)
            logger.notice("Created main SSH config")
            return
        }

        var existing = try String(contentsOf: configPath, encoding: .utf8)
        var updated = false

        // Ensure 1Password IdentityAgent is present
        if !existing.contains("IdentityAgent") || !existing.lowercased().contains("1password") {
            let agentBlock = "Host *\n    IdentityAgent \"\(Config.onePasswordAgentSocket)\"\n\n"
            existing = agentBlock + existing
            updated = true
            logger.notice("Added 1Password IdentityAgent to SSH config")
        }

        // Ensure Include for 1Password config
        if !existing.contains(Config.sshInclude1Password) {
            if !existing.hasSuffix("\n") { existing += "\n" }
            existing += "\n\(Config.sshInclude1Password)\n"
            updated = true
            logger.notice("Added 1Password Include to SSH config")
        }

        // Ensure Include for config.d
        if !existing.contains("Include ~/.ssh/config.d") {
            if !existing.hasSuffix("\n") { existing += "\n" }
            existing += "\(Config.sshIncludeConfigDir)\n"
            updated = true
            logger.notice("Added config.d Include to SSH config")
        }

        if updated {
            try existing.write(to: configPath, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configPath.path)
        }
    }
}
