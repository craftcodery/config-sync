import Foundation
import Network

// MARK: - Network Monitor

class NetworkMonitor {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.yourteam.config-sync.networkmonitor")
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
