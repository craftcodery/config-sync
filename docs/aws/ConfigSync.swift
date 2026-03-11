import Cocoa
import os.log
import ServiceManagement
import UserNotifications
import Network

// MARK: - Logger

private let logger = Logger(subsystem: "com.acme.config-sync", category: "sync")

// MARK: - Version

private enum AppVersion {
    static let current = "1.3.0"
    static let build = 5
}

// MARK: - Configuration

private enum Config {
    static let baseURL = "https://config.acme.example/aws"
    static let githubReleasesURL = "https://api.github.com/repos/your-org/config-sync/releases/latest"
    static let configDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".acme/aws")
    static let awsConfigPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".aws/config")
    static let helperName = "aws-vault-1password"
    static let syncHour = 8 // 8:00 AM
    static let syncMinute = 0
    static let syncTimeZone = TimeZone(identifier: "America/Chicago")! // Central Time
    static let updateCheckInterval: TimeInterval = 21600 // 6 hours
    static let opAccount = ProcessInfo.processInfo.environment["OP_ACCOUNT"] ?? "your-team.1password.com"

    /// Calculate seconds until next scheduled sync time (8am Central)
    static func secondsUntilNextSync() -> TimeInterval {
        let now = Date()
        var calendar = Calendar.current
        calendar.timeZone = syncTimeZone

        // Create date components for today at sync time
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = syncHour
        components.minute = syncMinute
        components.second = 0

        guard let todaySyncTime = calendar.date(from: components) else {
            // Fallback to 24 hours if calculation fails
            return 86400
        }

        // If we're past today's sync time, schedule for tomorrow
        let targetDate: Date
        if now >= todaySyncTime {
            targetDate = calendar.date(byAdding: .day, value: 1, to: todaySyncTime) ?? todaySyncTime.addingTimeInterval(86400)
        } else {
            targetDate = todaySyncTime
        }

        let interval = targetDate.timeIntervalSince(now)
        logger.notice("Next sync scheduled in \(Int(interval / 3600)) hours \(Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)) minutes")
        return max(interval, 60) // Minimum 1 minute to prevent rapid firing
    }
}

// MARK: - Preferences

class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let notificationsEnabled = "notificationsEnabled"
        static let lastSyncDate = "lastSyncDate"
        static let consecutiveFailures = "consecutiveFailures"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let skippedVersion = "skippedVersion"
    }

    var notificationsEnabled: Bool {
        get { defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.notificationsEnabled) }
    }

    var lastSyncDate: Date? {
        get { defaults.object(forKey: Keys.lastSyncDate) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastSyncDate) }
    }

    var consecutiveFailures: Int {
        get { defaults.integer(forKey: Keys.consecutiveFailures) }
        set { defaults.set(newValue, forKey: Keys.consecutiveFailures) }
    }

    var lastUpdateCheck: Date? {
        get { defaults.object(forKey: Keys.lastUpdateCheck) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastUpdateCheck) }
    }

    var skippedVersion: String? {
        get { defaults.string(forKey: Keys.skippedVersion) }
        set { defaults.set(newValue, forKey: Keys.skippedVersion) }
    }
}

// MARK: - Network Monitor

class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.acme.config-sync.networkmonitor")
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
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                logger.error("Failed to send notification: \(error.localizedDescription)")
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - Update Manager

class UpdateManager {
    static let shared = UpdateManager()

    struct VersionInfo {
        let version: String
        let releaseDate: String
        let releaseNotes: String
        let assets: Assets

        struct Assets {
            let appURL: URL
            let helperURL: URL
            let iconURL: URL
            let menuBarIconURL: URL
        }

        /// Parse from GitHub Releases API response
        static func from(githubRelease data: Data) throws -> VersionInfo {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let body = json["body"] as? String,
                  let publishedAt = json["published_at"] as? String,
                  let assetsArray = json["assets"] as? [[String: Any]] else {
                throw UpdateError.parseError
            }

            // Strip 'v' prefix from tag
            let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            // Parse release date (just the date part)
            let releaseDate = String(publishedAt.prefix(10))

            // Find asset URLs by name
            func findAssetURL(name: String) -> URL? {
                for asset in assetsArray {
                    if let assetName = asset["name"] as? String,
                       assetName == name,
                       let urlString = asset["browser_download_url"] as? String,
                       let url = URL(string: urlString) {
                        return url
                    }
                }
                return nil
            }

            guard let appURL = findAssetURL(name: "ConfigSync.swift"),
                  let helperURL = findAssetURL(name: "aws-vault-1password.swift"),
                  let iconURL = findAssetURL(name: "AppIcon.icns"),
                  let menuBarIconURL = findAssetURL(name: "MenuBarIcon.png") else {
                throw UpdateError.parseError
            }

            return VersionInfo(
                version: version,
                releaseDate: releaseDate,
                releaseNotes: body,
                assets: Assets(
                    appURL: appURL,
                    helperURL: helperURL,
                    iconURL: iconURL,
                    menuBarIconURL: menuBarIconURL
                )
            )
        }
    }

    enum UpdateError: Error, LocalizedError {
        case networkError(String)
        case parseError
        case downloadFailed(String)
        case compilationFailed(String)
        case installationFailed(String)

        var errorDescription: String? {
            switch self {
            case .networkError(let msg): return "Network error: \(msg)"
            case .parseError: return "Failed to parse version info"
            case .downloadFailed(let file): return "Failed to download \(file)"
            case .compilationFailed(let msg): return "Compilation failed: \(msg)"
            case .installationFailed(let msg): return "Installation failed: \(msg)"
            }
        }
    }

    enum UpdateStatus {
        case checking
        case upToDate
        case available(VersionInfo)
        case downloading
        case compiling
        case installing
        case failed(Error)
    }

    private(set) var status: UpdateStatus = .upToDate
    private(set) var latestVersion: VersionInfo?

    var updateAvailable: Bool {
        if case .available = status { return true }
        return false
    }

    var isUpdateInProgress: Bool {
        switch status {
        case .downloading, .compiling, .installing:
            return true
        default:
            return false
        }
    }

    func checkForUpdates() async -> VersionInfo? {
        guard NetworkMonitor.shared.isConnected else {
            logger.notice("Update check skipped: no network")
            return nil
        }

        status = .checking
        logger.notice("Checking for updates...")

        do {
            let versionInfo = try await fetchVersionInfo()
            latestVersion = versionInfo
            Preferences.shared.lastUpdateCheck = Date()

            if isNewerVersion(versionInfo.version) {
                // Check if user skipped this version
                if Preferences.shared.skippedVersion == versionInfo.version {
                    logger.notice("Update v\(versionInfo.version) available but skipped by user")
                    status = .upToDate
                    return nil
                }

                logger.notice("Update available: v\(versionInfo.version)")
                status = .available(versionInfo)
                return versionInfo
            } else {
                logger.notice("App is up to date (v\(AppVersion.current))")
                status = .upToDate
                return nil
            }
        } catch {
            logger.error("Update check failed: \(error.localizedDescription)")
            status = .failed(error)
            return nil
        }
    }

    private func fetchVersionInfo() async throws -> VersionInfo {
        guard let url = URL(string: Config.githubReleasesURL) else {
            throw UpdateError.networkError("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ConfigSync/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw UpdateError.networkError("HTTP error")
        }

        return try VersionInfo.from(githubRelease: data)
    }

    private func isNewerVersion(_ remoteVersion: String) -> Bool {
        let remote = remoteVersion.split(separator: ".").compactMap { Int($0) }
        let local = AppVersion.current.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(remote.count, local.count) {
            let r = i < remote.count ? remote[i] : 0
            let l = i < local.count ? local[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }

    func performUpdate(progressHandler: @escaping (String) -> Void) async throws {
        guard let versionInfo = latestVersion else {
            throw UpdateError.networkError("No version info available")
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ConfigSync-update-\(UUID().uuidString)")

        do {
            // Create temp directory
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            logger.notice("Update temp directory: \(tempDir.path)")

            // Download source files from GitHub Release assets
            status = .downloading
            progressHandler("Downloading update...")

            let appSourcePath = tempDir.appendingPathComponent("ConfigSync.swift")
            try await downloadFile(from: versionInfo.assets.appURL, to: appSourcePath)
            logger.notice("Downloaded app source")

            // Download helper source
            let helperSourcePath = tempDir.appendingPathComponent("aws-vault-1password.swift")
            try await downloadFile(from: versionInfo.assets.helperURL, to: helperSourcePath)
            logger.notice("Downloaded helper source")

            // Download icons
            let iconPath = tempDir.appendingPathComponent("AppIcon.icns")
            try await downloadFile(from: versionInfo.assets.iconURL, to: iconPath)

            let menuBarIconPath = tempDir.appendingPathComponent("MenuBarIcon.png")
            try await downloadFile(from: versionInfo.assets.menuBarIconURL, to: menuBarIconPath)
            logger.notice("Downloaded icons")

            // Compile app
            status = .compiling
            progressHandler("Compiling update...")

            let compiledAppPath = tempDir.appendingPathComponent("ConfigSync")
            try await compileSwift(source: appSourcePath, output: compiledAppPath)
            logger.notice("Compiled app")

            // Compile helper
            let compiledHelperPath = tempDir.appendingPathComponent("aws-vault-1password")
            try await compileSwift(source: helperSourcePath, output: compiledHelperPath)
            logger.notice("Compiled helper")

            // Install update
            status = .installing
            progressHandler("Installing update...")

            // Get app bundle paths
            guard let appBundle = Bundle.main.bundlePath as String?,
                  let executablePath = Bundle.main.executablePath else {
                throw UpdateError.installationFailed("Could not determine app paths")
            }

            let resourcesPath = (appBundle as NSString).appendingPathComponent("Contents/Resources")

            // Backup current executable
            let backupPath = executablePath + ".backup"
            if FileManager.default.fileExists(atPath: backupPath) {
                try FileManager.default.removeItem(atPath: backupPath)
            }
            try FileManager.default.copyItem(atPath: executablePath, toPath: backupPath)
            logger.notice("Backed up current executable")

            // Replace executable
            try FileManager.default.removeItem(atPath: executablePath)
            try FileManager.default.copyItem(at: compiledAppPath, to: URL(fileURLWithPath: executablePath))
            logger.notice("Replaced app executable")

            // Replace helper
            let helperInstallPath = Config.configDir.appendingPathComponent(Config.helperName)
            if FileManager.default.fileExists(atPath: helperInstallPath.path) {
                try FileManager.default.removeItem(at: helperInstallPath)
            }
            try FileManager.default.copyItem(at: compiledHelperPath, to: helperInstallPath)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperInstallPath.path)
            logger.notice("Replaced helper")

            // Replace icons
            let appIconInstallPath = URL(fileURLWithPath: resourcesPath).appendingPathComponent("AppIcon.icns")
            let menuBarIconInstallPath = URL(fileURLWithPath: resourcesPath).appendingPathComponent("MenuBarIcon.png")

            if FileManager.default.fileExists(atPath: appIconInstallPath.path) {
                try FileManager.default.removeItem(at: appIconInstallPath)
            }
            try FileManager.default.copyItem(at: iconPath, to: appIconInstallPath)

            if FileManager.default.fileExists(atPath: menuBarIconInstallPath.path) {
                try FileManager.default.removeItem(at: menuBarIconInstallPath)
            }
            try FileManager.default.copyItem(at: menuBarIconPath, to: menuBarIconInstallPath)
            logger.notice("Replaced icons")

            // Clean up temp directory
            try? FileManager.default.removeItem(at: tempDir)

            // Clean up backup (update successful)
            try? FileManager.default.removeItem(atPath: backupPath)

            // Clear skipped version
            Preferences.shared.skippedVersion = nil

            logger.notice("Update to v\(versionInfo.version) completed successfully")

            // Send notification
            NotificationManager.shared.sendNotification(
                title: "Acme Config Sync Updated",
                body: "Updated to v\(versionInfo.version). Restarting..."
            )

            // Relaunch after a short delay
            progressHandler("Restarting...")
            try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

            relaunchApp()

        } catch {
            // Clean up on failure
            try? FileManager.default.removeItem(at: tempDir)

            status = .failed(error)
            logger.error("Update failed: \(error.localizedDescription)")
            throw error
        }
    }

    private func downloadFile(from url: URL, to destination: URL) async throws {
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw UpdateError.downloadFailed(url.lastPathComponent)
        }

        try data.write(to: destination)
    }

    private func compileSwift(source: URL, output: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
        process.arguments = ["-O", "-o", output.path, source.path]

        let stderr = Pipe()
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw UpdateError.compilationFailed("swiftc not found")
        }

        if process.terminationStatus != 0 {
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw UpdateError.compilationFailed(errorMsg)
        }
    }

    private func relaunchApp() {
        guard let appPath = Bundle.main.bundlePath as String? else { return }

        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", appPath, "--args", "--relaunched"]

        do {
            try task.run()
        } catch {
            logger.error("Failed to relaunch: \(error.localizedDescription)")
        }

        // Exit current instance
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }

    func skipVersion(_ version: String) {
        Preferences.shared.skippedVersion = version
        status = .upToDate
        logger.notice("Skipped update v\(version)")
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
            try FileManager.default.createDirectory(at: Config.configDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".aws"),
                withIntermediateDirectories: true
            )

            try await opCLI.checkAuthenticated()
            logger.notice("1Password authenticated")

            let helperPath = Config.configDir.appendingPathComponent(Config.helperName)

            let configTemplate = try await downloadString(from: "\(Config.baseURL)/aws-config")
            logger.notice("Downloaded aws-config template")

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

            var config = configTemplate.replacingOccurrences(of: "__HELPER_PATH__", with: helperPath.path)

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

            var mfaSuccess = 0
            await withTaskGroup(of: (String, String?).self) { group in
                for placeholder in placeholders {
                    group.addTask {
                        do {
                            let serial = try await self.opCLI.getMFASerial(item: placeholder.item, vault: placeholder.vault)
                            return (placeholder.full, serial)
                        } catch {
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
    private var updateCheckTimer: Timer?
    private var lastSyncTime: Date?
    private var lastSyncSuccess: Bool = true
    private var isSyncing: Bool = false
    private let syncEngine = SyncEngine()
    private var isFirstSync = true

    private var statusMenu: NSMenu!
    private var statusMenuItem: NSMenuItem!
    private var lastSyncMenuItem: NSMenuItem!
    private var nextSyncMenuItem: NSMenuItem!
    private var updateMenuItem: NSMenuItem!
    private var launchAtLoginMenuItem: NSMenuItem!
    private var notificationsMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check if relaunched after update
        if CommandLine.arguments.contains("--relaunched") {
            logger.notice("App relaunched after update")
        }

        NetworkMonitor.shared.start()
        NotificationManager.shared.requestPermission()
        lastSyncTime = Preferences.shared.lastSyncDate

        setupStatusItem()
        setupMenu()

        // Initial sync
        Task {
            await performSync()
        }

        // Check for updates on launch
        Task {
            await checkForUpdates()
        }

        scheduleSyncTimer()
        scheduleUpdateCheckTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NetworkMonitor.shared.stop()
    }

    private func scheduleSyncTimer() {
        syncTimer?.invalidate()
        let interval = Config.secondsUntilNextSync()
        // Use non-repeating timer, reschedule after each sync
        syncTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task {
                await self?.performSync()
                // Reschedule for next day after sync completes
                await MainActor.run {
                    self?.scheduleSyncTimer()
                }
            }
        }
    }

    private func scheduleUpdateCheckTimer() {
        updateCheckTimer?.invalidate()
        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: Config.updateCheckInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.checkForUpdates()
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

        // Status
        statusMenuItem = NSMenuItem(title: "Status: Ready", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        statusMenu.addItem(statusMenuItem)

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

        // Sync Now
        let syncNowItem = NSMenuItem(title: "Sync Now", action: #selector(syncNowClicked), keyEquivalent: "s")
        syncNowItem.keyEquivalentModifierMask = .command
        syncNowItem.target = self
        statusMenu.addItem(syncNowItem)

        // Check for Updates
        let checkUpdatesItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdatesClicked), keyEquivalent: "")
        checkUpdatesItem.target = self
        statusMenu.addItem(checkUpdatesItem)

        statusMenu.addItem(NSMenuItem.separator())

        // View Logs
        let viewLogsItem = NSMenuItem(title: "View Logs...", action: #selector(viewLogsClicked), keyEquivalent: "l")
        viewLogsItem.keyEquivalentModifierMask = .command
        viewLogsItem.target = self
        statusMenu.addItem(viewLogsItem)

        // View AWS Config
        let openConfigItem = NSMenuItem(title: "View AWS config...", action: #selector(openConfigClicked), keyEquivalent: "o")
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
        let aboutItem = NSMenuItem(title: "About Acme Config Sync", action: #selector(aboutClicked), keyEquivalent: "")
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

            // Send notification about update
            NotificationManager.shared.sendNotification(
                title: "Acme Config Sync Update Available",
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
        statusMenuItem.title = "Status: Syncing..."

        let result = await syncEngine.sync()

        isSyncing = false

        if !result.skipped {
            lastSyncTime = Date()
            Preferences.shared.lastSyncDate = lastSyncTime
            lastSyncSuccess = result.success

            if result.success {
                Preferences.shared.consecutiveFailures = 0
                if isFirstSync {
                    NotificationManager.shared.sendNotification(
                        title: "Acme Config Sync",
                        body: "AWS configuration synced successfully"
                    )
                }
            } else {
                Preferences.shared.consecutiveFailures += 1
                NotificationManager.shared.sendNotification(
                    title: "Acme Config Sync Failed",
                    body: result.message,
                    isError: true
                )
            }

            isFirstSync = false
        }

        updateLastSyncTime()
        updateNextSyncTime()

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

    @objc private func syncNowClicked() {
        Task {
            await performSync()
        }
    }

    @objc private func checkForUpdatesClicked() {
        Task {
            statusMenuItem.title = "Status: Checking for updates..."
            let versionInfo = await UpdateManager.shared.checkForUpdates()

            await MainActor.run {
                updateUpdateMenuItem(versionInfo: versionInfo)

                if versionInfo == nil {
                    let alert = NSAlert()
                    alert.messageText = "No Updates Available"
                    alert.informativeText = "You're running the latest version (v\(AppVersion.current))."
                    alert.alertStyle = .informational
                    alert.runModal()
                }

                statusMenuItem.title = lastSyncSuccess ? "Status: Synced" : "Status: Ready"
            }
        }
    }

    @objc private func updateClicked() {
        guard let versionInfo = UpdateManager.shared.latestVersion else { return }

        let alert = NSAlert()
        alert.messageText = "Update to v\(versionInfo.version)?"
        alert.informativeText = """
        \(versionInfo.releaseNotes)

        The app will download the update, compile it, and restart automatically.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Update Now")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")

        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            performUpdate()
        case .alertThirdButtonReturn:
            UpdateManager.shared.skipVersion(versionInfo.version)
            updateMenuItem.isHidden = true
        default:
            break
        }
    }

    private func performUpdate() {
        guard !UpdateManager.shared.isUpdateInProgress else { return }

        Task {
            await MainActor.run {
                statusMenuItem.title = "Status: Updating..."
                updateMenuItem.title = "Updating..."
                updateMenuItem.isEnabled = false
            }

            do {
                try await UpdateManager.shared.performUpdate { progress in
                    Task { @MainActor in
                        self.statusMenuItem.title = "Status: \(progress)"
                    }
                }
            } catch {
                await MainActor.run {
                    statusMenuItem.title = "Status: Update failed"
                    updateMenuItem.isEnabled = true

                    let alert = NSAlert()
                    alert.messageText = "Update Failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }

    @objc private func viewLogsClicked() {
        let script = """
        tell application "Terminal"
            activate
            do script "log show --last 1h --predicate 'subsystem == \"com.acme.config-sync\"' --style compact"
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
        alert.messageText = "Acme Config Sync"
        alert.informativeText = """
        Version \(AppVersion.current) (build \(AppVersion.build))

        Syncs AWS configuration from 1Password.

        Features:
        - Daily sync at 8:00 AM Central
        - Network-aware (skips when offline)
        - Automatic updates from source
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

private var appDelegate: AppDelegate!

autoreleasepool {
    let app = NSApplication.shared
    appDelegate = AppDelegate()
    app.delegate = appDelegate
    app.setActivationPolicy(.accessory)
    app.run()
}
