import Cocoa
import ServiceManagement

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var syncTimer: Timer?
    private var updateCheckTimer: Timer?
    private var isSyncing: Bool = false
    private var isFirstSync = true

    // Modules
    private let awsModule = AWSModule()
    private let sshModule = SSHModule()

    // Sync state
    private var lastAWSSyncTime: Date?
    private var lastSSHSyncTime: Date?
    private var lastAWSSyncSuccess: Bool = true
    private var lastSSHSyncSuccess: Bool = true

    // Menu items
    private var statusMenu: NSMenu!
    private var awsStatusMenuItem: NSMenuItem!
    private var sshStatusMenuItem: NSMenuItem!
    private var lastSyncMenuItem: NSMenuItem!
    private var nextSyncMenuItem: NSMenuItem!
    private var updateMenuItem: NSMenuItem!
    private var launchAtLoginMenuItem: NSMenuItem!
    private var notificationsMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--relaunched") {
            logger.notice("App relaunched after update")
        }

        NetworkMonitor.shared.start()
        NotificationManager.shared.requestPermission()
        lastAWSSyncTime = Preferences.shared.lastAWSSyncDate
        lastSSHSyncTime = Preferences.shared.lastSSHSyncDate

        setupStatusItem()
        setupMenu()

        cleanupLegacyFiles()

        Task {
            await performSync()
        }

        Task {
            await checkForUpdates()
        }

        scheduleSyncTimer()
        scheduleUpdateCheckTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NetworkMonitor.shared.stop()
    }

    private func cleanupLegacyFiles() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let launchAgentsDir = home.appendingPathComponent("Library/LaunchAgents")

        // Extract org from bundle ID (e.g., "yourteam" from "com.yourteam.config-sync")
        let bundleID = Config.bundleID
        let bundleOrg = bundleID.components(separatedBy: ".").dropFirst().first ?? ""

        // Remove legacy launchd plists
        let legacyPlists = [
            "\(bundleID).plist",
            "com.\(bundleOrg).aws-config-sync.plist",
            "com.\(bundleOrg).sync.plist",
            "com.\(bundleOrg).config-sync.plist"
        ]

        for plist in legacyPlists {
            let path = launchAgentsDir.appendingPathComponent(plist)
            if fm.fileExists(atPath: path.path) {
                // Unload the launchd service
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                process.arguments = ["unload", path.path]
                try? process.run()
                process.waitUntilExit()

                try? fm.removeItem(at: path)
                logger.notice("Removed legacy plist: \(plist)")
            }
        }

        // Remove old AWS-only directory structure
        let oldAWSDir = Config.configDir.appendingPathComponent("aws")
        if fm.fileExists(atPath: oldAWSDir.path) {
            try? fm.removeItem(at: oldAWSDir)
            logger.notice("Removed legacy AWS directory")
        }
    }

    private func scheduleSyncTimer() {
        syncTimer?.invalidate()
        let interval = Config.secondsUntilNextSync()
        syncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.performSync()
                self.scheduleSyncTimer()
            }
        }
    }

    private func scheduleUpdateCheckTimer() {
        updateCheckTimer?.invalidate()
        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: Config.updateCheckInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.checkForUpdates()
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            if let iconPath = Bundle.main.path(forResource: "MenuBarIcon", ofType: "png"),
               let icon = NSImage(contentsOfFile: iconPath) {
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            } else {
                button.title = "NB"
            }
        }
    }

    private func setupMenu() {
        statusMenu = NSMenu()

        // AWS Status
        awsStatusMenuItem = NSMenuItem(title: "AWS: Ready", action: nil, keyEquivalent: "")
        awsStatusMenuItem.isEnabled = false
        statusMenu.addItem(awsStatusMenuItem)

        // SSH Status
        sshStatusMenuItem = NSMenuItem(title: "SSH: Ready", action: nil, keyEquivalent: "")
        sshStatusMenuItem.isEnabled = false
        statusMenu.addItem(sshStatusMenuItem)

        statusMenu.addItem(NSMenuItem.separator())

        // Last sync time
        lastSyncMenuItem = NSMenuItem(title: "Last sync: Never", action: nil, keyEquivalent: "")
        lastSyncMenuItem.isEnabled = false
        statusMenu.addItem(lastSyncMenuItem)
        updateLastSyncTime()

        // Next sync time
        nextSyncMenuItem = NSMenuItem(title: "Next sync: Calculating...", action: nil, keyEquivalent: "")
        nextSyncMenuItem.isEnabled = false
        statusMenu.addItem(nextSyncMenuItem)
        updateNextSyncTime()

        // Update available (hidden by default)
        updateMenuItem = NSMenuItem(title: "Update Available", action: #selector(updateClicked), keyEquivalent: "u")
        updateMenuItem.keyEquivalentModifierMask = .command
        updateMenuItem.target = self
        updateMenuItem.isHidden = true
        statusMenu.addItem(updateMenuItem)

        statusMenu.addItem(NSMenuItem.separator())

        // Sync All
        let syncAllItem = NSMenuItem(title: "Sync All", action: #selector(syncAllClicked), keyEquivalent: "s")
        syncAllItem.keyEquivalentModifierMask = .command
        syncAllItem.target = self
        statusMenu.addItem(syncAllItem)

        // Sync AWS Only
        let syncAWSItem = NSMenuItem(title: "Sync AWS Only", action: #selector(syncAWSClicked), keyEquivalent: "")
        syncAWSItem.target = self
        statusMenu.addItem(syncAWSItem)

        // Sync SSH Only
        let syncSSHItem = NSMenuItem(title: "Sync SSH Only", action: #selector(syncSSHClicked), keyEquivalent: "")
        syncSSHItem.target = self
        statusMenu.addItem(syncSSHItem)

        statusMenu.addItem(NSMenuItem.separator())

        // Check for Updates
        let checkUpdatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdatesClicked), keyEquivalent: "")
        checkUpdatesItem.target = self
        statusMenu.addItem(checkUpdatesItem)

        // View Logs
        let viewLogsItem = NSMenuItem(title: "View Logs...", action: #selector(viewLogsClicked), keyEquivalent: "l")
        viewLogsItem.keyEquivalentModifierMask = .command
        viewLogsItem.target = self
        statusMenu.addItem(viewLogsItem)

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
        let aboutItem = NSMenuItem(title: "About Your Team Config Sync", action: #selector(aboutClicked), keyEquivalent: "")
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
    private func checkForUpdates() async {
        let versionInfo = await UpdateManager.shared.checkForUpdates()
        updateUpdateMenuItem(versionInfo: versionInfo)
    }

    @MainActor
    private func updateUpdateMenuItem(versionInfo: UpdateManager.VersionInfo?) {
        if let info = versionInfo {
            updateMenuItem.title = "Update Available (v\(info.version))"
            updateMenuItem.isHidden = false

            NotificationManager.shared.sendNotification(
                title: "Your Team Config Sync Update Available",
                body: "Version \(info.version) is ready to install"
            )
        } else {
            updateMenuItem.isHidden = true
        }
    }

    @MainActor
    private func performSync() async {
        guard !isSyncing else { return }

        isSyncing = true
        awsStatusMenuItem.title = "AWS: Syncing..."
        sshStatusMenuItem.title = "SSH: Syncing..."

        // Sync AWS
        let awsResult = await awsModule.sync()
        if !awsResult.skipped {
            lastAWSSyncTime = Date()
            Preferences.shared.lastAWSSyncDate = lastAWSSyncTime
            lastAWSSyncSuccess = awsResult.success
        }
        awsStatusMenuItem.title = "AWS: \(awsResult.message)"

        // Sync SSH
        let sshResult = await sshModule.sync()
        if !sshResult.skipped {
            lastSSHSyncTime = Date()
            Preferences.shared.lastSSHSyncDate = lastSSHSyncTime
            lastSSHSyncSuccess = sshResult.success
        }
        sshStatusMenuItem.title = "SSH: \(sshResult.message)"

        isSyncing = false

        // Handle notifications
        let allSuccess = awsResult.success && sshResult.success
        if allSuccess {
            Preferences.shared.consecutiveFailures = 0
            if isFirstSync {
                NotificationManager.shared.sendNotification(
                    title: "Your Team Config Sync",
                    body: "AWS and SSH configuration synced successfully"
                )
            }
        } else {
            Preferences.shared.consecutiveFailures += 1
            var failedModules: [String] = []
            if !awsResult.success { failedModules.append("AWS") }
            if !sshResult.success { failedModules.append("SSH") }
            NotificationManager.shared.sendNotification(
                title: "Your Team Config Sync Failed",
                body: "\(failedModules.joined(separator: ", ")) sync failed",
                isError: true
            )
        }

        isFirstSync = false
        updateLastSyncTime()
        updateNextSyncTime()
    }

    @MainActor
    private func performAWSSync() async {
        guard !isSyncing else { return }

        isSyncing = true
        awsStatusMenuItem.title = "AWS: Syncing..."

        let result = await awsModule.sync()
        if !result.skipped {
            lastAWSSyncTime = Date()
            Preferences.shared.lastAWSSyncDate = lastAWSSyncTime
            lastAWSSyncSuccess = result.success
        }
        awsStatusMenuItem.title = "AWS: \(result.message)"

        isSyncing = false
        updateLastSyncTime()
    }

    @MainActor
    private func performSSHSync() async {
        guard !isSyncing else { return }

        isSyncing = true
        sshStatusMenuItem.title = "SSH: Syncing..."

        let result = await sshModule.sync()
        if !result.skipped {
            lastSSHSyncTime = Date()
            Preferences.shared.lastSSHSyncDate = lastSSHSyncTime
            lastSSHSyncSuccess = result.success
        }
        sshStatusMenuItem.title = "SSH: \(result.message)"

        isSyncing = false
        updateLastSyncTime()
    }

    private func updateLastSyncTime() {
        let mostRecentSync = [lastAWSSyncTime, lastSSHSyncTime].compactMap { $0 }.max()

        guard let lastSync = mostRecentSync else {
            lastSyncMenuItem.title = "Last sync: Never"
            return
        }

        let elapsed = Date().timeIntervalSince(lastSync)
        if elapsed < 60 {
            lastSyncMenuItem.title = "Last sync: Just now"
        } else {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let relativeTime = formatter.localizedString(for: lastSync, relativeTo: Date())
            lastSyncMenuItem.title = "Last sync: \(relativeTime)"
        }
    }

    private func updateNextSyncTime() {
        var calendar = Calendar.current
        calendar.timeZone = Config.syncTimeZone

        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = Config.syncHour
        components.minute = Config.syncMinute
        components.second = 0

        guard let todaySyncTime = calendar.date(from: components) else {
            nextSyncMenuItem.title = "Next sync: 8:00 AM Central"
            return
        }

        let targetDate: Date
        if now >= todaySyncTime {
            targetDate = calendar.date(byAdding: .day, value: 1, to: todaySyncTime) ?? todaySyncTime
        } else {
            targetDate = todaySyncTime
        }

        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.timeZone = Config.syncTimeZone

        let isToday = calendar.isDateInToday(targetDate)
        let isTomorrow = calendar.isDateInTomorrow(targetDate)

        let timeString = timeFormatter.string(from: targetDate)
        if isToday {
            nextSyncMenuItem.title = "Next sync: Today \(timeString)"
        } else if isTomorrow {
            nextSyncMenuItem.title = "Next sync: Tomorrow \(timeString)"
        } else {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEEE"
            dayFormatter.timeZone = Config.syncTimeZone
            let dayString = dayFormatter.string(from: targetDate)
            nextSyncMenuItem.title = "Next sync: \(dayString) \(timeString)"
        }
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

    @objc private func syncAllClicked() {
        Task {
            await performSync()
        }
    }

    @objc private func syncAWSClicked() {
        Task {
            await performAWSSync()
        }
    }

    @objc private func syncSSHClicked() {
        Task {
            await performSSHSync()
        }
    }

    @objc private func checkForUpdatesClicked() {
        Task {
            awsStatusMenuItem.title = "AWS: Checking updates..."
            let versionInfo = await UpdateManager.shared.checkForUpdates()

            await MainActor.run {
                updateUpdateMenuItem(versionInfo: versionInfo)
                awsStatusMenuItem.title = "AWS: \(lastAWSSyncSuccess ? "Synced" : "Ready")"

                if versionInfo == nil {
                    let alert = NSAlert()
                    alert.messageText = "No Updates Available"
                    alert.informativeText = "You're running the latest version (v\(AppVersion.current))."
                    alert.alertStyle = .informational
                    alert.runModal()
                }
            }
        }
    }

    @objc private func updateClicked() {
        guard let versionInfo = UpdateManager.shared.latestVersion else { return }

        let alert = NSAlert()
        alert.messageText = "Update to v\(versionInfo.version)?"
        alert.informativeText = """
        \(versionInfo.releaseNotes)

        To update, re-run the setup script:
        curl -fsSL config.yourteam.example | bash
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Skip This Version")

        let response = alert.runModal()

        if response == .alertSecondButtonReturn {
            UpdateManager.shared.skipVersion(versionInfo.version)
            updateMenuItem.isHidden = true
        }
    }

    @objc private func viewLogsClicked() {
        let script = """
        tell application "Terminal"
            activate
            do script "log show --last 1h --predicate 'subsystem == \"com.yourteam.config-sync\"' --style compact"
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
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
        alert.messageText = "Your Team Config Sync"
        alert.informativeText = """
        Version \(AppVersion.current) (build \(AppVersion.build))

        Syncs AWS and SSH configuration from 1Password.

        Features:
        - Daily sync at 8:00 AM Central
        - AWS credential helper with MFA support
        - SSH keys via 1Password agent
        - Network-aware (skips when offline)
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

@main
struct ConfigSyncApp {
    static var appDelegate: AppDelegate!

    static func main() {
        autoreleasepool {
            let app = NSApplication.shared
            appDelegate = AppDelegate()
            app.delegate = appDelegate
            app.setActivationPolicy(.accessory)
            app.run()
        }
    }
}
