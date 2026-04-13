import Foundation

// MARK: - GitHub Client
//
// Shared utility for downloading files from a private GitHub repository
// using the GitHub CLI (gh). Used by AWSModule and SSHModule to fetch
// configuration files and templates during sync.

actor GitHubClient {

    enum GitHubError: Error, LocalizedError {
        case downloadFailed(String)
        case invalidContent(String)
        case ghNotFound

        var errorDescription: String? {
            switch self {
            case .downloadFailed(let path): return "Failed to download \(path) from GitHub"
            case .invalidContent(let path): return "Invalid content received for \(path)"
            case .ghNotFound: return "GitHub CLI (gh) not found"
            }
        }
    }

    /// Download a file from the configured GitHub repository.
    ///
    /// Uses `gh api` with the raw content accept header to fetch file contents
    /// from the private repository defined in `Config`.
    ///
    /// - Parameter filePath: Path relative to the repo's path prefix (e.g., "config/ssh-hosts.toml")
    /// - Returns: The file content as a string
    /// - Throws: `GitHubError` if the download fails or content is invalid
    func download(filePath: String) async throws -> String {
        let apiPath = "repos/\(Config.githubOwner)/\(Config.githubRepo)/contents/\(Config.githubPathPrefix)/\(filePath)"

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["gh", "api", apiPath, "-H", "Accept: application/vnd.github.raw"]
            process.standardOutput = stdout
            process.standardError = stderr

            process.terminationHandler = { proc in
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

                if proc.terminationStatus != 0 {
                    let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    logger.error("GitHub download failed for \(filePath): \(errorMsg.trimmingCharacters(in: .whitespacesAndNewlines))")
                    continuation.resume(throwing: GitHubError.downloadFailed(filePath))
                    return
                }

                guard let content = String(data: data, encoding: .utf8), !content.isEmpty else {
                    logger.error("Empty or invalid content received for \(filePath)")
                    continuation.resume(throwing: GitHubError.invalidContent(filePath))
                    return
                }

                continuation.resume(returning: content)
            }

            do {
                try process.run()
            } catch {
                logger.error("Failed to launch gh CLI: \(error.localizedDescription)")
                continuation.resume(throwing: GitHubError.ghNotFound)
            }
        }
    }
}
