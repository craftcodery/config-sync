import Cocoa
import os.log
import ServiceManagement
import UserNotifications
import Network

// MARK: - Logger

private let logger = Logger(subsystem: "com.northbuilt.sync", category: "sync")

// MARK: - Configuration

private enum Config {
    static let baseURL = "https://setup.northbuilt.com/aws"
    static let configDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".northbuilt/aws")
    static let awsConfigPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".aws/config")
    static let helperName = "aws-vault-1password"
    static let defaultSyncInterval: TimeInterval = 3600 // 1 hour
    static let opAccount = ProcessInfo.processInfo.environment["OP_ACCOUNT"] ?? "craftcodery.1password.com"
}

// MARK: - Preferences

class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let notificationsEnabled = "notificationsEnabled"
        static let syncInterval = "syncInterval"
        static let lastSyncDate = "lastSyncDate"
        static let consecutiveFailures = "consecutiveFailures"
    }

    var notificationsEnabled: Bool {
        get { defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.notificationsEnabled) }
    }

    var syncInterval: TimeInterval {
        get {
            let interval = defaults.double(forKey: Keys.syncInterval)
            return interval > 0 ? interval : Config.defaultSyncInterval
        }
        set { defaults.set(newValue, forKey: Keys.syncInterval) }
    }

    var lastSyncDate: Date? {
        get { defaults.object(forKey: Keys.lastSyncDate) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastSyncDate) }
    }

    var consecutiveFailures: Int {
        get { defaults.integer(forKey: Keys.consecutiveFailures) }
        set { defaults.set(newValue, forKey: Keys.consecutiveFailures) }
    }
}

// MARK: - Network Monitor

class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.northbuilt.sync.networkmonitor")
    private(set) var isConnected = true

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isConnected = path.status == .satisfied
            logger.notice("Network status: \(path.status == .satisfied ? "connected" : "disconnected")")
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}

// MARK: - Notification Manager

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() {
        super.init()
    }

    func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                logger.notice("Notification permission granted")
            } else if let error = error {
                logger.error("Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    func sendNotification(title: String, body: String, isError: Bool = false) {
        guard Preferences.shared.notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = isError ? .default : nil

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                logger.error("Failed to send notification: \(error.localizedDescription)")
            }
        }
    }

    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
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
        case networkUnavailable

        var errorDescription: String? {
            switch self {
            case .downloadFailed(let url): return "Failed to download \(url)"
            case .substitutionFailed(let msg): return msg
            case .unsubstitutedPlaceholders: return "Config has unsubstituted MFA placeholders"
            case .networkUnavailable: return "No network connection"
            }
        }
    }

    struct SyncResult {
        let success: Bool
        let message: String
        let mfaCount: Int
        let mfaSuccess: Int
        let skipped: Bool
    }

    private let opCLI = OnePasswordCLI()

    func sync() async -> SyncResult {
        // Check network connectivity first
        guard NetworkMonitor.shared.isConnected else {
            logger.notice("Sync skipped: no network connection")
            return SyncResult(
                success: true,
                message: "Waiting for network",
                mfaCount: 0,
                mfaSuccess: 0,
                skipped: true
            )
        }

        logger.notice("Starting sync")

        do {
            // Ensure directories exist
            try FileManager.default.createDirectory(at: Config.configDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".aws"),
                withIntermediateDirectories: true
            )

            // Check 1Password authentication
            try await opCLI.checkAuthenticated()
            logger.notice("1Password authenticated")

            // Helper path (installed during setup, not updated during sync)
            let helperPath = Config.configDir.appendingPathComponent(Config.helperName)

            // Download AWS config template
            let configTemplate = try await downloadString(from: "\(Config.baseURL)/aws-config")
            logger.notice("Downloaded aws-config template")

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
                        mfaSuccess: 0,
                        skipped: false
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

            logger.notice("Found \(placeholders.count) MFA placeholders")

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
                        logger.notice("Substituted MFA serial for placeholder")
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
                    mfaSuccess: mfaSuccess,
                    skipped: false
                )
            }

            // Write config
            try config.write(to: Config.awsConfigPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Config.awsConfigPath.path)
            logger.notice("Deployed ~/.aws/config")

            return SyncResult(
                success: true,
                message: "Sync complete",
                mfaCount: placeholders.count,
                mfaSuccess: mfaSuccess,
                skipped: false
            )

        } catch {
            logger.error("Sync failed: \(error.localizedDescription)")
            return SyncResult(
                success: false,
                message: error.localizedDescription,
                mfaCount: 0,
                mfaSuccess: 0,
                skipped: false
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
    private var isFirstSync = true

    private var statusMenu: NSMenu!
    private var statusMenuItem: NSMenuItem!
    private var lastSyncMenuItem: NSMenuItem!
    private var launchAtLoginMenuItem: NSMenuItem!
    private var notificationsMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start network monitoring
        NetworkMonitor.shared.start()

        // Request notification permission
        NotificationManager.shared.requestPermission()

        // Restore last sync time from preferences
        lastSyncTime = Preferences.shared.lastSyncDate

        setupStatusItem()
        setupMenu()

        // Initial sync
        Task {
            await performSync()
        }

        // Schedule sync based on preference
        scheduleSyncTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NetworkMonitor.shared.stop()
    }

    private func scheduleSyncTimer() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: Preferences.shared.syncInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.performSync()
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            // Load custom icon from app bundle Resources
            if let iconPath = Bundle.main.path(forResource: "MenuBarIcon", ofType: "png"),
               let icon = NSImage(contentsOfFile: iconPath) {
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            } else {
                // Fallback to text if image not found
                button.title = "NB"
            }
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
        updateLastSyncTime()

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

        // Notifications toggle
        notificationsMenuItem = NSMenuItem(title: "Notifications", action: #selector(toggleNotifications), keyEquivalent: "")
        notificationsMenuItem.target = self
        notificationsMenuItem.state = Preferences.shared.notificationsEnabled ? .on : .off
        statusMenu.addItem(notificationsMenuItem)

        // Launch at Login
        launchAtLoginMenuItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginMenuItem.target = self
        updateLaunchAtLoginState()
        statusMenu.addItem(launchAtLoginMenuItem)

        statusMenu.addItem(NSMenuItem.separator())

        // About
        let aboutItem = NSMenuItem(title: "About NorthBuilt Sync", action: #selector(aboutClicked), keyEquivalent: "")
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
        statusMenuItem.title = "Status: Syncing..."

        let result = await syncEngine.sync()

        isSyncing = false

        // Don't update last sync time if sync was skipped
        if !result.skipped {
            lastSyncTime = Date()
            Preferences.shared.lastSyncDate = lastSyncTime
            lastSyncSuccess = result.success

            // Handle notifications
            if result.success {
                Preferences.shared.consecutiveFailures = 0

                // Only notify on first successful sync after launch
                if isFirstSync {
                    NotificationManager.shared.sendNotification(
                        title: "NorthBuilt Sync",
                        body: "AWS configuration synced successfully"
                    )
                }
            } else {
                Preferences.shared.consecutiveFailures += 1

                // Notify on failure (always)
                NotificationManager.shared.sendNotification(
                    title: "NorthBuilt Sync Failed",
                    body: result.message,
                    isError: true
                )
            }

            isFirstSync = false
        }

        updateLastSyncTime()

        if result.skipped {
            statusMenuItem.title = "Status: \(result.message)"
        } else if result.success {
            statusMenuItem.title = "Status: Synced"
        } else {
            statusMenuItem.title = "Status: \(result.message)"
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
        // Show logs in Terminal using the log command
        let script = """
        tell application "Terminal"
            activate
            do script "log show --last 1h --predicate 'subsystem == \"com.northbuilt.sync\"' --style compact"
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    @objc private func openConfigClicked() {
        NSWorkspace.shared.open(Config.awsConfigPath)
    }

    @objc private func toggleNotifications() {
        Preferences.shared.notificationsEnabled.toggle()
        notificationsMenuItem.state = Preferences.shared.notificationsEnabled ? .on : .off

        if Preferences.shared.notificationsEnabled {
            NotificationManager.shared.requestPermission()
        }
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
        alert.messageText = "NorthBuilt Sync"
        alert.informativeText = """
        Version 1.1

        Syncs AWS configuration from 1Password.

        Features:
        - Hourly background sync
        - Network-aware (skips when offline)
        - Failure notifications
        - Launch at Login support
        """
        alert.alertStyle = .informational
        alert.runModal()
    }

    @objc private func quitClicked() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Main

// Global reference to prevent delegate from being deallocated
private var appDelegate: AppDelegate!

autoreleasepool {
    let app = NSApplication.shared
    appDelegate = AppDelegate()
    app.delegate = appDelegate
    app.setActivationPolicy(.accessory)
    app.run()
}
