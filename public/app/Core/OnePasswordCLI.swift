import Foundation

// MARK: - 1Password CLI

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

    func itemExists(title: String, vault: String) async -> Bool {
        do {
            _ = try await run(["item", "get", title, "--vault", vault, "--account", Config.opAccount])
            return true
        } catch {
            return false
        }
    }

    func createSSHKey(title: String, vault: String, keyType: String, alias: String, description: String) async throws {
        _ = try await run([
            "item", "create",
            "--category", "SSH Key",
            "--title", title,
            "--vault", vault,
            "--account", Config.opAccount,
            "--ssh-generate-key", keyType,
            "url[url]=ssh://\(alias)",
            "notesPlain=\(description)"
        ])
    }

    func getPublicKey(title: String, vault: String) async throws -> String? {
        let result = try await run([
            "item", "get", title,
            "--vault", vault,
            "--account", Config.opAccount,
            "--fields", "public key"
        ])
        return result.isEmpty ? nil : result
    }
}
