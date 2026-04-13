import Foundation

// MARK: - Preferences

class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let notificationsEnabled = "notificationsEnabled"
        static let lastAWSSyncDate = "lastAWSSyncDate"
        static let lastSSHSyncDate = "lastSSHSyncDate"
        static let consecutiveFailures = "consecutiveFailures"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let skippedVersion = "skippedVersion"
    }

    var notificationsEnabled: Bool {
        get { defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.notificationsEnabled) }
    }

    var lastAWSSyncDate: Date? {
        get { defaults.object(forKey: Keys.lastAWSSyncDate) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastAWSSyncDate) }
    }

    var lastSSHSyncDate: Date? {
        get { defaults.object(forKey: Keys.lastSSHSyncDate) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastSSHSyncDate) }
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
