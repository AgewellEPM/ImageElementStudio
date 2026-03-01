import Foundation
import os

// MARK: - InputValidator

/// Centralized input validation for enterprise hardening.
///
/// All methods are static and side-effect-free (except logging). Validation
/// failures are logged via `os.Logger` for audit trail purposes.
enum InputValidator {

    // MARK: - Private Logger

    private static let logger = Logger(
        subsystem: "com.imageelementstudio",
        category: "InputValidator"
    )

    // MARK: - Path Safety

    /// Removes dangerous path components such as `../`, null bytes, and leading
    /// tildes that could be used for directory traversal or path injection.
    ///
    /// The result is a path that can be safely appended to a known root
    /// directory. If the entire path is stripped away, returns `"untitled"`.
    static func sanitizePath(_ path: String) -> String {
        var sanitized = path

        // Strip null bytes
        sanitized = sanitized.replacingOccurrences(of: "\0", with: "")

        // Collapse repeated slashes
        while sanitized.contains("//") {
            sanitized = sanitized.replacingOccurrences(of: "//", with: "/")
        }

        // Remove path traversal components
        sanitized = sanitized.replacingOccurrences(of: "../", with: "")
        sanitized = sanitized.replacingOccurrences(of: "..\\", with: "")

        // Remove remaining standalone ".." at end of path
        if sanitized.hasSuffix("/..") || sanitized == ".." {
            sanitized = sanitized.replacingOccurrences(of: "..", with: "")
        }

        // Strip leading ~ (home directory expansion)
        if sanitized.hasPrefix("~") {
            sanitized = String(sanitized.dropFirst())
        }

        // Remove control characters
        sanitized = sanitized.unicodeScalars
            .filter { !$0.properties.isNoncharacterCodePoint && ($0.value >= 0x20 || $0 == "\t") }
            .map { String($0) }
            .joined()

        // Trim whitespace
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)

        if sanitized.isEmpty {
            return "untitled"
        }

        return sanitized
    }

    /// Returns `true` if the path is free of traversal attacks, null bytes, and
    /// other dangerous patterns. Does **not** sanitize; use `sanitizePath(_:)`
    /// if you need a cleaned-up version.
    static func isPathSafe(_ path: String) -> Bool {
        // Null bytes
        if path.contains("\0") {
            logger.warning("Path validation failed: null byte detected")
            return false
        }

        // Traversal patterns
        if path.contains("../") || path.contains("..\\") || path.hasSuffix("/..") || path == ".." {
            logger.warning("Path validation failed: traversal pattern detected")
            return false
        }

        // Absolute paths to sensitive system directories
        let sensitiveRoots = ["/etc/", "/var/", "/usr/", "/bin/", "/sbin/",
                              "/System/", "/Library/", "/private/"]
        for root in sensitiveRoots {
            if path.hasPrefix(root) {
                logger.warning("Path validation failed: sensitive system directory '\(root, privacy: .public)'")
                return false
            }
        }

        // Control characters (except tab)
        for scalar in path.unicodeScalars {
            if scalar.value < 0x20 && scalar != "\t" {
                logger.warning("Path validation failed: control character detected")
                return false
            }
        }

        return true
    }

    // MARK: - Project Name Safety

    /// Maximum allowed project name length.
    static let maxProjectNameLength = 128

    /// Minimum allowed project name length.
    static let minProjectNameLength = 1

    /// Allowed character set for project names: letters, digits, spaces,
    /// hyphens, underscores, and periods.
    private static let projectNameAllowedCharacters: CharacterSet = {
        var cs = CharacterSet.alphanumerics
        cs.insert(charactersIn: " -_.()")
        return cs
    }()

    /// Removes characters that are not allowed in project names and trims
    /// whitespace. If the result is empty, returns `"Untitled Project"`.
    static func sanitizeProjectName(_ name: String) -> String {
        // Strip null bytes and control characters first
        var sanitized = name.unicodeScalars
            .filter { projectNameAllowedCharacters.contains($0) }
            .map { String($0) }
            .joined()

        // Collapse multiple consecutive spaces
        while sanitized.contains("  ") {
            sanitized = sanitized.replacingOccurrences(of: "  ", with: " ")
        }

        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)

        // Enforce max length
        if sanitized.count > maxProjectNameLength {
            sanitized = String(sanitized.prefix(maxProjectNameLength))
        }

        if sanitized.isEmpty {
            return "Untitled Project"
        }

        return sanitized
    }

    /// Returns `true` if the project name is valid: non-empty, within length
    /// bounds, and contains only allowed characters.
    static func isProjectNameValid(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            logger.warning("Project name validation failed: empty name")
            return false
        }

        if trimmed.count < minProjectNameLength {
            logger.warning("Project name validation failed: too short (\(trimmed.count) chars)")
            return false
        }

        if trimmed.count > maxProjectNameLength {
            logger.warning("Project name validation failed: exceeds max length (\(trimmed.count) > \(maxProjectNameLength))")
            return false
        }

        // Check for disallowed characters
        let scalars = trimmed.unicodeScalars
        for scalar in scalars {
            if !projectNameAllowedCharacters.contains(scalar) {
                logger.warning("Project name validation failed: disallowed character")
                return false
            }
        }

        // Reject names that are entirely dots/dashes (filesystem hazards)
        let stripped = trimmed.replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        if stripped.isEmpty {
            logger.warning("Project name validation failed: name is entirely dots/dashes/spaces")
            return false
        }

        return true
    }

    // MARK: - API Key Validation

    /// Returns `true` if the API key has a plausible format.
    ///
    /// Checks:
    /// - Non-empty after trimming
    /// - Reasonable length (minimum 20 characters, maximum 256)
    /// - Starts with a known provider prefix or is alphanumeric-ish
    /// - No null bytes or control characters
    static func isAPIKeyFormatValid(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            logger.warning("API key validation failed: empty key")
            return false
        }

        if trimmed.count < 20 {
            logger.warning("API key validation failed: too short (\(trimmed.count) chars)")
            return false
        }

        if trimmed.count > 256 {
            logger.warning("API key validation failed: exceeds max length")
            return false
        }

        // No null bytes or control characters
        for scalar in trimmed.unicodeScalars {
            if scalar.value < 0x20 {
                logger.warning("API key validation failed: control character detected")
                return false
            }
        }

        // Must start with a recognized prefix or be alphanumeric
        let knownPrefixes = ["sk-", "sk-ant-", "sk-proj-", "xai-", "ollama-"]
        let hasKnownPrefix = knownPrefixes.contains { trimmed.hasPrefix($0) }

        if !hasKnownPrefix {
            // If no known prefix, at least check it's alphanumeric-ish (letters, digits, hyphens, underscores)
            let allowedKeyChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
            let isAlphanumericIsh = trimmed.unicodeScalars.allSatisfy { allowedKeyChars.contains($0) }
            if !isAlphanumericIsh {
                logger.warning("API key validation failed: unrecognized format")
                return false
            }
        }

        return true
    }

    // MARK: - JSON Input Validation

    /// Default maximum JSON input size in bytes (10 MB).
    static let defaultMaxJSONSize = 10 * 1024 * 1024

    /// Returns `true` if the JSON string is within the size limit and appears
    /// to be structurally valid JSON (starts with `{` or `[`).
    static func isJSONSafe(_ json: String, maxSize: Int = InputValidator.defaultMaxJSONSize) -> Bool {
        // Check byte length
        let byteCount = json.utf8.count
        if byteCount > maxSize {
            logger.warning("JSON validation failed: size \(byteCount) exceeds max \(maxSize)")
            return false
        }

        if byteCount == 0 {
            logger.warning("JSON validation failed: empty input")
            return false
        }

        // Check for null bytes
        if json.contains("\0") {
            logger.warning("JSON validation failed: null byte detected")
            return false
        }

        // Basic structural check: must start with { or [
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstChar = trimmed.first else {
            logger.warning("JSON validation failed: empty after trimming")
            return false
        }

        if firstChar != "{" && firstChar != "[" {
            logger.warning("JSON validation failed: does not start with {{ or [")
            return false
        }

        // Verify it ends with the matching bracket
        guard let lastChar = trimmed.last else { return false }
        let validEnding = (firstChar == "{" && lastChar == "}") ||
                          (firstChar == "[" && lastChar == "]")
        if !validEnding {
            logger.warning("JSON validation failed: mismatched brackets")
            return false
        }

        return true
    }
}
