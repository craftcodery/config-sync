import Foundation

// aws-vault-1password: Fetches AWS credentials or TOTP from 1Password
//
// Usage:
//   aws-vault-1password "Item Name" "Vault Name"              # Get credentials
//   aws-vault-1password "Item Name" "Vault Name" --otp        # Get TOTP code
//   aws-vault-1password "Item Name" "Vault Name" --validate   # Validate entry format
//
// Environment Variables:
//   OP_ACCOUNT - 1Password account to use (e.g., "your-team.1password.com")

// MARK: - Configuration

let opAccount = ProcessInfo.processInfo.environment["OP_ACCOUNT"] ?? "your-team.1password.com"

// MARK: - Errors

enum HelperError: Error, LocalizedError {
    case notInstalled
    case notAuthenticated
    case itemNotFound(String, String)
    case commandFailed(String)
    case fieldNotFound(String)
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .notInstalled: return "1Password CLI (op) not found"
        case .notAuthenticated: return "Not signed in to 1Password"
        case .itemNotFound(let item, let vault): return "Item '\(item)' not found in vault '\(vault)'"
        case .commandFailed(let msg): return msg
        case .fieldNotFound(let field): return "Could not find \(field)"
        case .invalidJSON: return "Invalid JSON response from 1Password"
        }
    }
}

// MARK: - Process Helpers

func findOPPath() -> String {
    let paths = ["/opt/homebrew/bin/op", "/usr/local/bin/op", "/usr/bin/op"]
    for path in paths {
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
    }
    return "/opt/homebrew/bin/op"
}

func runOP(_ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: findOPPath())
    process.arguments = arguments
    process.environment = [
        "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
        "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
        "OP_ACCOUNT": opAccount
    ]

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        throw HelperError.notInstalled
    }

    let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
    let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

    if process.terminationStatus != 0 {
        let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
        throw HelperError.commandFailed(errorMsg.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    return String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

// MARK: - Field Extraction

func extractField(from json: [String: Any], labels: [String]) -> String? {
    guard let fields = json["fields"] as? [[String: Any]] else { return nil }

    for field in fields {
        if let label = field["label"] as? String,
           labels.contains(label),
           let value = field["value"] as? String,
           !value.isEmpty, value != "null" {
            return value
        }
        // Also check by ID
        if let id = field["id"] as? String,
           labels.contains(id),
           let value = field["value"] as? String,
           !value.isEmpty, value != "null" {
            return value
        }
    }
    return nil
}

// MARK: - Credential Fetcher

func fetchCredentials(item: String, vault: String) throws {
    // Get item JSON
    let jsonString = try runOP(["item", "get", item, "--vault", vault, "--account", opAccount, "--format", "json"])

    guard let data = jsonString.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw HelperError.invalidJSON
    }

    // Extract Access Key ID
    let accessKeyLabels = ["Access Key ID", "access_key_id", "AccessKeyId", "AWS_ACCESS_KEY_ID"]
    guard let accessKey = extractField(from: json, labels: accessKeyLabels) else {
        fputs("""
        Error: Could not find Access Key ID in '\(item)'

        Expected field label: 'Access Key ID'

        Note: 'username' fields are reserved for console login credentials.
        Add a separate 'Access Key ID' field with your AWS access key (starts with AKIA).

        Run with --validate to diagnose:
          aws-vault-1password "\(item)" "\(vault)" --validate

        """, stderr)
        throw HelperError.fieldNotFound("Access Key ID")
    }

    // Warn if Access Key ID doesn't look right
    if !accessKey.hasPrefix("AKIA") && !accessKey.hasPrefix("ASIA") {
        fputs("Warning: Access Key ID doesn't look like an AWS key: \(String(accessKey.prefix(20)))...\n", stderr)
        fputs("AWS access keys start with AKIA (user) or ASIA (temporary)\n\n", stderr)
    }

    // Extract Secret Access Key
    let secretKeyLabels = ["Secret Access Key", "secret_access_key", "SecretAccessKey", "AWS_SECRET_ACCESS_KEY"]
    guard let secretKey = extractField(from: json, labels: secretKeyLabels) else {
        fputs("""
        Error: Could not find Secret Access Key in '\(item)'

        Expected field label: 'Secret Access Key'

        Note: 'password' fields are reserved for console login credentials.
        Add a separate 'Secret Access Key' field with your AWS secret key (40 chars).

        Run with --validate to diagnose:
          aws-vault-1password "\(item)" "\(vault)" --validate

        """, stderr)
        throw HelperError.fieldNotFound("Secret Access Key")
    }

    // Output AWS credential_process format
    let output: [String: Any] = [
        "Version": 1,
        "AccessKeyId": accessKey,
        "SecretAccessKey": secretKey
    ]

    if let outputData = try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]),
       let outputString = String(data: outputData, encoding: .utf8) {
        print(outputString)
    }
}

// MARK: - OTP Fetcher

func fetchOTP(item: String, vault: String) throws {
    let otp = try runOP(["item", "get", item, "--vault", vault, "--account", opAccount, "--otp"])

    if otp.isEmpty {
        fputs("""
        Error: TOTP field is empty for '\(item)'

        Ensure the item has a one-time password (TOTP) field configured.
        In 1Password: Edit item -> Add More -> One-Time Password

        """, stderr)
        exit(1)
    }

    // mfa_process expects just the code on stdout
    print(otp)
}

// MARK: - Validator

func validate(item: String, vault: String) throws {
    print("Validating: \(item) (vault: \(vault))")
    print("")

    // Get item JSON
    let jsonString: String
    do {
        jsonString = try runOP(["item", "get", item, "--vault", vault, "--account", opAccount, "--format", "json"])
    } catch {
        print("\u{2717} Could not retrieve item")
        throw error
    }
    print("\u{2713} Item found")

    guard let data = jsonString.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        print("\u{2717} Invalid JSON response")
        exit(1)
    }

    var hasErrors = false

    // Check Access Key ID
    let accessKeyLabels = ["Access Key ID", "access_key_id", "AccessKeyId", "AWS_ACCESS_KEY_ID"]
    if let accessKey = extractField(from: json, labels: accessKeyLabels) {
        if accessKey.hasPrefix("AKIA") {
            print("\u{2713} Access Key ID: \(String(accessKey.prefix(8)))... (valid IAM user key)")
        } else if accessKey.hasPrefix("ASIA") {
            print("\u{2713} Access Key ID: \(String(accessKey.prefix(8)))... (valid temporary key)")
        } else if accessKey.hasPrefix("AIDA") {
            print("\u{26A0} Access Key ID: \(String(accessKey.prefix(8)))... (this is an IAM User ID, not an access key)")
            hasErrors = true
        } else {
            print("\u{26A0} Access Key ID: \(String(accessKey.prefix(20)))... (doesn't look like an AWS access key)")
            print("  AWS access keys start with AKIA (user) or ASIA (temporary)")
            hasErrors = true
        }
    } else {
        print("\u{2717} Access Key ID: NOT FOUND")
        print("  Add a field labeled 'Access Key ID' with the AWS access key")
        hasErrors = true
    }

    // Check Secret Access Key
    let secretKeyLabels = ["Secret Access Key", "secret_access_key", "SecretAccessKey", "AWS_SECRET_ACCESS_KEY"]
    if let secretKey = extractField(from: json, labels: secretKeyLabels) {
        if secretKey.count == 40 {
            print("\u{2713} Secret Access Key: ******** (valid length: 40 chars)")
        } else {
            print("\u{26A0} Secret Access Key: ******** (length: \(secretKey.count) chars, expected: 40)")
        }
    } else {
        print("\u{2717} Secret Access Key: NOT FOUND")
        print("  Add a field labeled 'Secret Access Key' with the AWS secret key")
        hasErrors = true
    }

    // Check TOTP
    do {
        _ = try runOP(["item", "get", item, "--vault", vault, "--account", opAccount, "--otp"])
        print("\u{2713} TOTP: Configured")
    } catch {
        print("\u{25CB} TOTP: Not configured (optional, needed for MFA)")
    }

    // Check additional metadata fields
    let accountIdLabels = ["AWS Account ID", "account_id", "AccountId"]
    if let accountId = extractField(from: json, labels: accountIdLabels) {
        print("\u{2713} AWS Account ID: \(accountId)")
    } else {
        print("\u{25CB} AWS Account ID: Not set (optional)")
    }

    let mfaLabels = ["MFA Serial ARN", "mfa_serial", "MfaSerial"]
    if let mfaArn = extractField(from: json, labels: mfaLabels) {
        print("\u{2713} MFA Serial ARN: \(mfaArn)")
    } else {
        print("\u{25CB} MFA Serial ARN: Not set (optional, needed for MFA)")
    }

    print("")

    // Check Access Key for final result
    let accessKey = extractField(from: json, labels: accessKeyLabels)
    let secretKey = extractField(from: json, labels: secretKeyLabels)
    let validAccessKey = accessKey?.hasPrefix("AKIA") == true || accessKey?.hasPrefix("ASIA") == true

    if validAccessKey && secretKey != nil && !hasErrors {
        print("Result: \u{2713} Entry is properly configured for AWS CLI")
    } else {
        print("Result: \u{2717} Entry needs updates (see above)")
        exit(1)
    }
}

// MARK: - Main

func printUsage() {
    fputs("""
    Usage: aws-vault-1password <item-name> <vault-name> [--otp|--validate]

    Modes:
      (default)   Return AWS credentials in JSON format
      --otp       Return TOTP code for MFA
      --validate  Check if entry is properly configured

    Environment:
      OP_ACCOUNT  1Password account (e.g., your-team.1password.com)

    """, stderr)
}

func main() {
    let args = CommandLine.arguments

    if args.count < 3 {
        printUsage()
        exit(1)
    }

    let item = args[1]
    let vault = args[2]
    let mode = args.count > 3 ? args[3] : ""

    // Check 1Password authentication
    do {
        _ = try runOP(["account", "list", "--account", opAccount])
    } catch {
        fputs("Error: Not signed in to 1Password.\n", stderr)
        fputs("Open 1Password app to authenticate, or check OP_ACCOUNT setting.\n", stderr)
        exit(1)
    }

    do {
        switch mode {
        case "--otp":
            try fetchOTP(item: item, vault: vault)
        case "--validate":
            try validate(item: item, vault: vault)
        default:
            try fetchCredentials(item: item, vault: vault)
        }
    } catch {
        fputs("Error: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

main()
