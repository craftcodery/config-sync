import Cocoa
import os.log
import ServiceManagement

// MARK: - Logger

private let logger = Logger(subsystem: "com.northbuilt.aws-config-sync", category: "sync")

// MARK: - Configuration

private enum Config {
    static let baseURL = "https://setup.northbuilt.com/aws"
    static let configDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".northbuilt/aws")
    static let awsConfigPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".aws/config")
    static let helperName = "aws-vault-1password"
    static let syncInterval: TimeInterval = 3600 // 1 hour
    static let opAccount = ProcessInfo.processInfo.environment["OP_ACCOUNT"] ?? "craftcodery.1password.com"
}

// MARK: - OnePasswordCLI

actor OnePasswordCLI {
    enum CLIError: Error, LocalizedError {
        case notInstalled
        case notAuthenticated
        case itemNotFound(String, String)
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled: return "1Password CLI (op) not found"
            case .notAuthenticated: return "Not signed in to 1Password"
            case .itemNotFound(let item, let vault): return "Item '\(item)' not found in vault '\(vault)'"
            case .commandFailed(let msg): return msg
            }
        }
    }

    private func run(_ arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/op")
        process.arguments = arguments
        process.environment = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "OP_ACCOUNT": Config.opAccount
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw CLIError.notInstalled
        }

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus != 0 {
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw CLIError.commandFailed(errorMsg.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func checkAuthenticated() async throws {
        _ = try await run(["account", "list", "--account", Config.opAccount])
    }

    func getMFASerial(item: String, vault: String) async throws -> String? {
        let json = try await run(["item", "get", item, "--vault", vault, "--account", Config.opAccount, "--format", "json"])

        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fields = parsed["fields"] as? [[String: Any]] else {
            return nil
        }

        let labels = ["MFA Serial ARN", "mfa_serial", "MfaSerial"]
        for field in fields {
            if let label = field["label"] as? String,
               labels.contains(label),
               let value = field["value"] as? String,
               !value.isEmpty, value != "null" {
                return value
            }
        }
        return nil
    }
}

// MARK: - SyncEngine

actor SyncEngine {
    enum SyncError: Error, LocalizedError {
        case downloadFailed(String)
        case substitutionFailed(String)
        case unsubstitutedPlaceholders

        var errorDescription: String? {
            switch self {
            case .downloadFailed(let url): return "Failed to download \(url)"
            case .substitutionFailed(let msg): return msg
            case .unsubstitutedPlaceholders: return "Config has unsubstituted MFA placeholders"
            }
        }
    }

    struct SyncResult {
        let success: Bool
        let message: String
        let mfaCount: Int
        let mfaSuccess: Int
    }

    private let opCLI = OnePasswordCLI()

    func sync() async -> SyncResult {
        logger.info("Starting sync")

        do {
            // Ensure directories exist
            try FileManager.default.createDirectory(at: Config.configDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".aws"),
                withIntermediateDirectories: true
            )

            // Check 1Password authentication
            try await opCLI.checkAuthenticated()
            logger.info("1Password authenticated")

            // Helper path (installed during setup, not updated during sync)
            let helperPath = Config.configDir.appendingPathComponent(Config.helperName)

            // Download AWS config template
            let configTemplate = try await downloadString(from: "\(Config.baseURL)/aws-config")
            logger.info("Downloaded aws-config template")

            // Security: Validate config template before substitution
            // Reject configs containing shell commands or suspicious patterns
            let suspiciousPatterns = ["curl ", "wget ", "/bin/sh", "/bin/bash", "&&", "||", "; "]
            for pattern in suspiciousPatterns {
                if configTemplate.contains(pattern) {
                    logger.error("Config template contains suspicious pattern, aborting sync")
                    return SyncResult(
                        success: false,
                        message: "Config validation failed",
                        mfaCount: 0,
                        mfaSuccess: 0
                    )
                }
            }

            // Substitute __HELPER_PATH__
            var config = configTemplate.replacingOccurrences(of: "__HELPER_PATH__", with: helperPath.path)

            // Find and substitute MFA serial placeholders
            let mfaPattern = try NSRegularExpression(pattern: "__MFA_SERIAL:([^:]+):([^_]+)__")
            let matches = mfaPattern.matches(in: config, range: NSRange(config.startIndex..., in: config))

            var placeholders: [(full: String, item: String, vault: String)] = []
            for match in matches {
                if let fullRange = Range(match.range, in: config),
                   let itemRange = Range(match.range(at: 1), in: config),
                   let vaultRange = Range(match.range(at: 2), in: config) {
                    let full = String(config[fullRange])
                    let item = String(config[itemRange])
                    let vault = String(config[vaultRange])
                    if !placeholders.contains(where: { $0.full == full }) {
                        placeholders.append((full, item, vault))
                    }
                }
            }

            logger.info("Found \(placeholders.count) MFA placeholders")

            // Fetch MFA serials in parallel
            var mfaSuccess = 0
            await withTaskGroup(of: (String, String?).self) { group in
                for placeholder in placeholders {
                    group.addTask {
                        do {
                            let serial = try await self.opCLI.getMFASerial(item: placeholder.item, vault: placeholder.vault)
                            return (placeholder.full, serial)
                        } catch {
                            // Use privacy: .private to redact item names in logs
                            logger.error("Failed to fetch MFA for item: \(placeholder.item, privacy: .private)")
                            return (placeholder.full, nil)
                        }
                    }
                }

                for await (placeholder, serial) in group {
                    if let serial = serial {
                        config = config.replacingOccurrences(of: placeholder, with: serial)
                        mfaSuccess += 1
                        logger.info("Substituted MFA serial for placeholder")
                    }
                }
            }

            // Check for unsubstituted placeholders
            if config.contains("__MFA_SERIAL:") {
                logger.error("Config has unsubstituted MFA placeholders")
                return SyncResult(
                    success: false,
                    message: "1Password may be locked",
                    mfaCount: placeholders.count,
                    mfaSuccess: mfaSuccess
                )
            }

            // Write config
            try config.write(to: Config.awsConfigPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Config.awsConfigPath.path)
            logger.info("Deployed ~/.aws/config")

            return SyncResult(
                success: true,
                message: "Sync complete",
                mfaCount: placeholders.count,
                mfaSuccess: mfaSuccess
            )

        } catch {
            logger.error("Sync failed: \(error.localizedDescription)")
            return SyncResult(
                success: false,
                message: error.localizedDescription,
                mfaCount: 0,
                mfaSuccess: 0
            )
        }
    }

    private func downloadString(from urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw SyncError.downloadFailed(urlString)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SyncError.downloadFailed(urlString)
        }

        guard let string = String(data: data, encoding: .utf8) else {
            throw SyncError.downloadFailed(urlString)
        }

        return string
    }

}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var syncTimer: Timer?
    private var lastSyncTime: Date?
    private var lastSyncSuccess: Bool = true
    private var isSyncing: Bool = false
    private let syncEngine = SyncEngine()

    private var statusMenu: NSMenu!
    private var statusMenuItem: NSMenuItem!
    private var lastSyncMenuItem: NSMenuItem!
    private var launchAtLoginMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupMenu()

        // Initial sync
        Task {
            await performSync()
        }

        // Schedule hourly sync
        syncTimer = Timer.scheduledTimer(withTimeInterval: Config.syncInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.performSync()
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: "AWS Sync")
        }
    }

    private func setupMenu() {
        statusMenu = NSMenu()

        // Status
        statusMenuItem = NSMenuItem(title: "Status: Ready", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        statusMenu.addItem(statusMenuItem)

        // Last sync time
        lastSyncMenuItem = NSMenuItem(title: "Last sync: Never", action: nil, keyEquivalent: "")
        lastSyncMenuItem.isEnabled = false
        statusMenu.addItem(lastSyncMenuItem)

        statusMenu.addItem(NSMenuItem.separator())

        // Sync Now
        let syncNowItem = NSMenuItem(title: "Sync Now", action: #selector(syncNowClicked), keyEquivalent: "s")
        syncNowItem.keyEquivalentModifierMask = .command
        syncNowItem.target = self
        statusMenu.addItem(syncNowItem)

        statusMenu.addItem(NSMenuItem.separator())

        // View Logs
        let viewLogsItem = NSMenuItem(title: "View Logs...", action: #selector(viewLogsClicked), keyEquivalent: "l")
        viewLogsItem.keyEquivalentModifierMask = .command
        viewLogsItem.target = self
        statusMenu.addItem(viewLogsItem)

        // Open AWS Config
        let openConfigItem = NSMenuItem(title: "Open AWS Config", action: #selector(openConfigClicked), keyEquivalent: "o")
        openConfigItem.keyEquivalentModifierMask = .command
        openConfigItem.target = self
        statusMenu.addItem(openConfigItem)

        statusMenu.addItem(NSMenuItem.separator())

        // Launch at Login
        launchAtLoginMenuItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginMenuItem.target = self
        updateLaunchAtLoginState()
        statusMenu.addItem(launchAtLoginMenuItem)

        statusMenu.addItem(NSMenuItem.separator())

        // About
        let aboutItem = NSMenuItem(title: "About NorthBuilt AWS Sync", action: #selector(aboutClicked), keyEquivalent: "")
        aboutItem.target = self
        statusMenu.addItem(aboutItem)

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        statusMenu.addItem(quitItem)

        statusItem.menu = statusMenu
    }

    @MainActor
    private func performSync() async {
        guard !isSyncing else { return }

        isSyncing = true
        updateStatusIcon(syncing: true)
        statusMenuItem.title = "Status: Syncing..."

        let result = await syncEngine.sync()

        isSyncing = false
        lastSyncTime = Date()
        lastSyncSuccess = result.success

        updateStatusIcon(syncing: false)
        updateLastSyncTime()

        if result.success {
            statusMenuItem.title = "Status: Synced"
        } else {
            statusMenuItem.title = "Status: \(result.message)"
        }
    }

    private func updateStatusIcon(syncing: Bool) {
        guard let button = statusItem.button else { return }

        if syncing {
            button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Syncing")
        } else if lastSyncSuccess {
            button.image = NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: "AWS Sync")
        } else {
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Sync Error")
        }
    }

    private func updateLastSyncTime() {
        guard let lastSync = lastSyncTime else {
            lastSyncMenuItem.title = "Last sync: Never"
            return
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let relativeTime = formatter.localizedString(for: lastSync, relativeTo: Date())
        lastSyncMenuItem.title = "Last sync: \(relativeTime)"
    }

    private func updateLaunchAtLoginState() {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            launchAtLoginMenuItem.state = (status == .enabled) ? .on : .off
        } else {
            launchAtLoginMenuItem.isEnabled = false
            launchAtLoginMenuItem.title = "Launch at Login (macOS 13+)"
        }
    }

    @objc private func syncNowClicked() {
        Task {
            await performSync()
        }
    }

    @objc private func viewLogsClicked() {
        // Open Console.app with filter for our subsystem
        let script = """
        tell application "Console"
            activate
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }

        // Also show a notification about how to filter
        let alert = NSAlert()
        alert.messageText = "View Logs"
        alert.informativeText = "Console.app opened. Filter by subsystem:\ncom.northbuilt.aws-config-sync"
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func openConfigClicked() {
        NSWorkspace.shared.open(Config.awsConfigPath)
    }

    @objc private func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                let service = SMAppService.mainApp
                if service.status == .enabled {
                    try service.unregister()
                } else {
                    try service.register()
                }
                updateLaunchAtLoginState()
            } catch {
                logger.error("Failed to toggle launch at login: \(error.localizedDescription)")

                let alert = NSAlert()
                alert.messageText = "Error"
                alert.informativeText = "Could not change launch at login setting: \(error.localizedDescription)"
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    @objc private func aboutClicked() {
        let alert = NSAlert()
        alert.messageText = "NorthBuilt AWS Sync"
        alert.informativeText = """
        Version 1.0

        Syncs AWS configuration from 1Password.

        Runs hourly in the background.
        """
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func quitClicked() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
