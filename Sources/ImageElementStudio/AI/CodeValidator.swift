import Foundation

// MARK: - Code Validator

/// Validates AI-generated code before writing to disk.
/// Pure string analysis — no process launching, no external dependencies.
struct CodeValidator: Sendable {

    // MARK: - Types

    struct ValidationResult: Sendable {
        let isValid: Bool
        let errors: [ValidationError]
        let cleanedContent: String
    }

    struct ValidationError: Sendable {
        let message: String
        let severity: Severity

        enum Severity: Sendable {
            case error
            case warning
        }
    }

    // MARK: - Primary Validation

    static func validate(entry: GeneratedFileEntry) -> ValidationResult {
        let stripped = stripCodeFences(entry.content)

        var allErrors: [ValidationError] = []

        allErrors.append(contentsOf: checkNotEmpty(stripped))
        allErrors.append(contentsOf: checkBalancedBraces(stripped))
        allErrors.append(contentsOf: checkRequiredImports(stripped, fileRole: entry.role))
        allErrors.append(contentsOf: checkForArtifacts(stripped))

        let hasRealError = allErrors.contains { $0.severity == .error }

        return ValidationResult(
            isValid: !hasRealError,
            errors: allErrors,
            cleanedContent: stripped
        )
    }

    // MARK: - Strip Code Fences

    /// Removes markdown code fences that AI models sometimes wrap output in.
    /// Handles ```swift, ```html, ```css, ```javascript, ```js, and bare ```.
    static func stripCodeFences(_ content: String) -> String {
        var lines = content.components(separatedBy: "\n")

        // Strip leading fence line (e.g. ```swift or ```)
        if let first = lines.first?.trimmingCharacters(in: .whitespaces) {
            if first.hasPrefix("```") {
                lines.removeFirst()
            }
        }

        // Strip trailing fence line
        if let last = lines.last?.trimmingCharacters(in: .whitespaces) {
            if last == "```" {
                lines.removeLast()
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Balanced Braces

    /// Checks that {}, (), and [] are each balanced.
    static func checkBalancedBraces(_ content: String) -> [ValidationError] {
        var errors: [ValidationError] = []

        // We need to skip characters inside string literals and comments to avoid
        // false positives on braces in strings. A simplified approach: track whether
        // we're inside a string or single-line / multi-line comment.

        var curlyCount = 0
        var parenCount = 0
        var bracketCount = 0

        var inSingleLineComment = false
        var inMultiLineComment = false
        var inDoubleQuoteString = false
        var inMultiLineString = false  // triple-quote """
        var escaped = false

        let chars = Array(content.unicodeScalars)
        var i = 0

        while i < chars.count {
            let c = chars[i]
            let next: Unicode.Scalar? = (i + 1 < chars.count) ? chars[i + 1] : nil
            let nextNext: Unicode.Scalar? = (i + 2 < chars.count) ? chars[i + 2] : nil

            // Handle newlines — reset single-line comment state
            if c == "\n" {
                inSingleLineComment = false
                escaped = false
                i += 1
                continue
            }

            // Skip if in single-line comment
            if inSingleLineComment {
                i += 1
                continue
            }

            // Multi-line comment end
            if inMultiLineComment {
                if c == "*" && next == "/" {
                    inMultiLineComment = false
                    i += 2
                    continue
                }
                i += 1
                continue
            }

            // Multi-line string handling (triple quote)
            if inMultiLineString {
                if c == "\\" {
                    escaped = !escaped
                    i += 1
                    continue
                }
                if !escaped && c == "\"" && next == "\"" && nextNext == "\"" {
                    inMultiLineString = false
                    i += 3
                    continue
                }
                escaped = false
                i += 1
                continue
            }

            // Double-quote string handling
            if inDoubleQuoteString {
                if c == "\\" {
                    escaped = !escaped
                    i += 1
                    continue
                }
                if !escaped && c == "\"" {
                    inDoubleQuoteString = false
                }
                escaped = false
                i += 1
                continue
            }

            // Check for comment starts
            if c == "/" && next == "/" {
                inSingleLineComment = true
                i += 2
                continue
            }
            if c == "/" && next == "*" {
                inMultiLineComment = true
                i += 2
                continue
            }

            // Check for string starts
            if c == "\"" {
                if next == "\"" && nextNext == "\"" {
                    inMultiLineString = true
                    i += 3
                    continue
                }
                inDoubleQuoteString = true
                i += 1
                continue
            }

            // Count braces
            switch c {
            case "{": curlyCount += 1
            case "}": curlyCount -= 1
            case "(": parenCount += 1
            case ")": parenCount -= 1
            case "[": bracketCount += 1
            case "]": bracketCount -= 1
            default: break
            }

            i += 1
        }

        if curlyCount != 0 {
            let direction = curlyCount > 0 ? "unclosed" : "extra closing"
            errors.append(ValidationError(
                message: "Unbalanced curly braces: \(abs(curlyCount)) \(direction) '{'/'}'",
                severity: .error
            ))
        }

        if parenCount != 0 {
            let direction = parenCount > 0 ? "unclosed" : "extra closing"
            errors.append(ValidationError(
                message: "Unbalanced parentheses: \(abs(parenCount)) \(direction) '('/')'",
                severity: .error
            ))
        }

        if bracketCount != 0 {
            let direction = bracketCount > 0 ? "unclosed" : "extra closing"
            errors.append(ValidationError(
                message: "Unbalanced brackets: \(abs(bracketCount)) \(direction) '['/ ']'",
                severity: .error
            ))
        }

        return errors
    }

    // MARK: - Required Imports

    /// Checks that files contain expected import/structure markers based on their role.
    static func checkRequiredImports(_ content: String, fileRole: FileRole) -> [ValidationError] {
        switch fileRole {
        case .webMarkup:
            // HTML files should have a doctype or html tag
            let lower = content.lowercased()
            if !lower.contains("<!doctype") && !lower.contains("<html") {
                return [ValidationError(
                    message: "HTML file missing <!DOCTYPE> or <html> tag",
                    severity: .warning
                )]
            }
            return []

        case .webStyle, .webScript:
            // CSS and JS files have no specific import requirement
            return []

        default:
            // Swift files should have at least one import statement
            let hasImport: Bool = {
                for line in content.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.range(of: #"^import\s+\w+"#, options: .regularExpression) != nil {
                        return true
                    }
                }
                return false
            }()

            if !hasImport {
                return [ValidationError(
                    message: "Swift file missing import statement (expected 'import Foundation' or 'import SwiftUI')",
                    severity: .error
                )]
            }
            return []
        }
    }

    // MARK: - Not Empty

    /// Checks that the file content is non-trivial (more than 10 characters after trimming).
    static func checkNotEmpty(_ content: String) -> [ValidationError] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 10 {
            return [ValidationError(
                message: "File content is empty or nearly empty (\(trimmed.count) characters)",
                severity: .error
            )]
        }
        return []
    }

    // MARK: - AI Artifacts

    /// Detects common AI generation artifacts — placeholder comments, leftover fences, etc.
    static func checkForArtifacts(_ content: String) -> [ValidationError] {
        var errors: [ValidationError] = []

        let artifactPatterns: [(pattern: String, description: String)] = [
            (#"//\s*\.\.\.\s*rest\s+of"#, "Contains placeholder comment '// ... rest of'"),
            (#"//\s*\.\.\.\s*remaining"#, "Contains placeholder comment '// ... remaining'"),
            (#"//\s*TODO:\s*implement"#, "Contains 'TODO: implement' placeholder"),
            (#"/\*\s*Add\s+more\s*\*/"#, "Contains '/* Add more */' placeholder"),
            (#"\[Your\s+code\s+here\]"#, "Contains '[Your code here]' placeholder"),
            (#"\[Insert\s+code\]"#, "Contains '[Insert code]' placeholder"),
        ]

        for (pattern, description) in artifactPatterns {
            if content.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil {
                errors.append(ValidationError(
                    message: description,
                    severity: .warning
                ))
            }
        }

        // Check for triple backticks inside code (not at the very start/end, which
        // stripCodeFences already handled). We look for ``` on its own line or as a
        // fence marker mid-file. Skip occurrences inside string literals by checking
        // for lines that are just ``` or ```<language>.
        let lines = content.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                // This is a leftover markdown fence inside the code
                errors.append(ValidationError(
                    message: "Triple backtick fence found at line \(index + 1) — likely a markdown artifact",
                    severity: .warning
                ))
                break  // One warning is sufficient
            }
        }

        return errors
    }
}
