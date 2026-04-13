import Foundation

// MARK: - TOML Parser
//
// Lightweight parser for the subset of TOML used by config-sync's
// configuration files (ssh-hosts.toml, aws-profiles.toml).
//
// Supports:
//   - Top-level key = "value" pairs (settings)
//   - Array-of-tables sections ([[section]])
//   - Quoted string values
//   - Comments (lines starting with #)
//
// Does NOT support: nested tables, inline tables, arrays, multiline strings,
// or the full TOML spec. This is intentional — our config files use a
// simple, flat structure.

enum TOMLParser {

    /// A parsed TOML entry from an array-of-tables section.
    /// Each entry is a dictionary of key-value pairs.
    typealias Entry = [String: String]

    /// Parse top-level settings (key = "value" pairs before any [[section]]).
    ///
    /// - Parameter toml: Raw TOML string
    /// - Returns: Dictionary of setting names to values
    static func parseSettings(_ toml: String) -> [String: String] {
        var settings: [String: String] = [:]

        for line in toml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Stop at first array-of-tables section
            if trimmed.hasPrefix("[[") { break }

            // Skip comments and empty lines
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if let (key, value) = parseKeyValue(trimmed) {
                settings[key] = value
            }
        }

        return settings
    }

    /// Parse all entries from array-of-tables sections (e.g., [[hosts]], [[profiles]]).
    ///
    /// - Parameters:
    ///   - toml: Raw TOML string
    ///   - section: Section name without brackets (e.g., "hosts", "profiles")
    /// - Returns: Array of dictionaries, one per `[[section]]` block
    static func parseArrayOfTables(_ toml: String, section: String) -> [Entry] {
        var entries: [Entry] = []
        var current: Entry = [:]
        var inSection = false
        let sectionMarker = "[[\(section)]]"

        for line in toml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == sectionMarker {
                // Save previous entry
                if inSection && !current.isEmpty {
                    entries.append(current)
                }
                current = [:]
                inSection = true
                continue
            }

            // A different section marker ends the current section
            if trimmed.hasPrefix("[[") && trimmed != sectionMarker {
                if inSection && !current.isEmpty {
                    entries.append(current)
                }
                inSection = false
                continue
            }

            // Parse key-value pairs within the section
            if inSection && !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                if let (key, value) = parseKeyValue(trimmed) {
                    current[key] = value
                }
            }
        }

        // Handle last entry
        if inSection && !current.isEmpty {
            entries.append(current)
        }

        return entries
    }

    /// Parse a single "key = value" line, stripping quotes from values.
    ///
    /// - Parameter line: A trimmed line like `name = "default"` or `has_mfa = true`
    /// - Returns: Tuple of (key, value) or nil if line doesn't contain `=`
    private static func parseKeyValue(_ line: String) -> (String, String)? {
        guard line.contains("=") else { return nil }

        let parts = line.components(separatedBy: "=")
        guard parts.count >= 2 else { return nil }

        let key = parts[0].trimmingCharacters(in: .whitespaces)
        var value = parts.dropFirst().joined(separator: "=").trimmingCharacters(in: .whitespaces)

        // Strip surrounding quotes
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        return (key, value)
    }
}
