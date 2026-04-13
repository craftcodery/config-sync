import Foundation

// MARK: - Module Protocol

protocol SyncModule {
    var name: String { get }
    func sync() async -> SyncResult
}

struct SyncResult {
    let success: Bool
    let message: String
    let skipped: Bool

    static func success(_ message: String) -> SyncResult {
        SyncResult(success: true, message: message, skipped: false)
    }

    static func failure(_ message: String) -> SyncResult {
        SyncResult(success: false, message: message, skipped: false)
    }

    static func skipped(_ message: String) -> SyncResult {
        SyncResult(success: true, message: message, skipped: true)
    }
}
