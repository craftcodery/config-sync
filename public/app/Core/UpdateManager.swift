import Foundation

// MARK: - Update Manager

class UpdateManager {
    static let shared = UpdateManager()

    struct VersionInfo {
        let version: String
        let releaseDate: String
        let releaseNotes: String
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

    private(set) var latestVersion: VersionInfo?

    func checkForUpdates() async -> VersionInfo? {
        guard NetworkMonitor.shared.isConnected else {
            logger.notice("Update check skipped: no network")
            return nil
        }

        logger.notice("Checking for updates...")

        do {
            let versionInfo = try await fetchVersionInfo()
            latestVersion = versionInfo
            Preferences.shared.lastUpdateCheck = Date()

            if isNewerVersion(versionInfo.version) {
                if Preferences.shared.skippedVersion == versionInfo.version {
                    logger.notice("Update v\(versionInfo.version) available but skipped by user")
                    return nil
                }

                logger.notice("Update available: v\(versionInfo.version)")
                return versionInfo
            } else {
                logger.notice("App is up to date (v\(AppVersion.current))")
                return nil
            }
        } catch {
            logger.error("Update check failed: \(error.localizedDescription)")
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

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tagName = json["tag_name"] as? String,
              let body = json["body"] as? String,
              let publishedAt = json["published_at"] as? String else {
            throw UpdateError.parseError
        }

        let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
        let releaseDate = String(publishedAt.prefix(10))

        return VersionInfo(version: version, releaseDate: releaseDate, releaseNotes: body)
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

    func skipVersion(_ version: String) {
        Preferences.shared.skippedVersion = version
        logger.notice("Skipped update v\(version)")
    }
}
