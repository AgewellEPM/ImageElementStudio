import XCTest
@testable import ImageElementStudio

final class InputValidatorTests: XCTestCase {

    // MARK: - Path Traversal Detection

    func testIsPathSafeRejectsDotDotSlash() {
        XCTAssertFalse(InputValidator.isPathSafe("../../etc/passwd"))
        XCTAssertFalse(InputValidator.isPathSafe("/home/user/../../../etc/shadow"))
    }

    func testIsPathSafeRejectsBackslashTraversal() {
        XCTAssertFalse(InputValidator.isPathSafe("..\\Windows\\System32"))
    }

    func testIsPathSafeRejectsTrailingDotDot() {
        XCTAssertFalse(InputValidator.isPathSafe("/some/path/.."))
        XCTAssertFalse(InputValidator.isPathSafe(".."))
    }

    func testIsPathSafeRejectsNullBytes() {
        XCTAssertFalse(InputValidator.isPathSafe("/safe/path\0/evil"))
        XCTAssertFalse(InputValidator.isPathSafe("file\0.txt"))
    }

    func testIsPathSafeRejectsControlCharacters() {
        XCTAssertFalse(InputValidator.isPathSafe("/path/with\u{01}control"))
        XCTAssertFalse(InputValidator.isPathSafe("dir/\u{07}bell"))
    }

    func testIsPathSafeRejectsSensitiveSystemPaths() {
        XCTAssertFalse(InputValidator.isPathSafe("/etc/passwd"))
        XCTAssertFalse(InputValidator.isPathSafe("/var/log/system.log"))
        XCTAssertFalse(InputValidator.isPathSafe("/usr/bin/bash"))
        XCTAssertFalse(InputValidator.isPathSafe("/System/Library/something"))
        XCTAssertFalse(InputValidator.isPathSafe("/private/var/data"))
    }

    func testIsPathSafeAcceptsNormalPaths() {
        XCTAssertTrue(InputValidator.isPathSafe("/Users/luke/Documents/project.json"))
        XCTAssertTrue(InputValidator.isPathSafe("/tmp/export-file.json"))
        XCTAssertTrue(InputValidator.isPathSafe("relative/path/to/file.txt"))
        XCTAssertTrue(InputValidator.isPathSafe("simple-file.json"))
    }

    func testIsPathSafeAcceptsTabCharacter() {
        // Tab is allowed per spec
        XCTAssertTrue(InputValidator.isPathSafe("/safe/path\t/file.txt"))
    }

    // MARK: - Path Sanitization

    func testSanitizePathRemovesTraversalPatterns() {
        let result = InputValidator.sanitizePath("../../etc/passwd")
        XCTAssertFalse(result.contains("../"))
        XCTAssertFalse(result.contains(".."))
    }

    func testSanitizePathRemovesNullBytes() {
        let result = InputValidator.sanitizePath("safe\0path")
        XCTAssertFalse(result.contains("\0"))
        XCTAssertEqual(result, "safepath")
    }

    func testSanitizePathCollapsesDoubleSlashes() {
        let result = InputValidator.sanitizePath("/path//to///file")
        XCTAssertFalse(result.contains("//"))
    }

    func testSanitizePathStripsLeadingTilde() {
        let result = InputValidator.sanitizePath("~/Desktop/file.txt")
        XCTAssertFalse(result.hasPrefix("~"))
    }

    func testSanitizePathReturnsUntitledForEmpty() {
        XCTAssertEqual(InputValidator.sanitizePath(""), "untitled")
        XCTAssertEqual(InputValidator.sanitizePath("   "), "untitled")
    }

    // MARK: - Project Name Validation

    func testIsProjectNameValidAcceptsNormalNames() {
        XCTAssertTrue(InputValidator.isProjectNameValid("My Cool Project"))
        XCTAssertTrue(InputValidator.isProjectNameValid("project-v2"))
        XCTAssertTrue(InputValidator.isProjectNameValid("Design_System_2024"))
        XCTAssertTrue(InputValidator.isProjectNameValid("App (iOS)"))
    }

    func testIsProjectNameValidRejectsEmptyName() {
        XCTAssertFalse(InputValidator.isProjectNameValid(""))
        XCTAssertFalse(InputValidator.isProjectNameValid("   "))
    }

    func testIsProjectNameValidRejectsTooLongName() {
        let longName = String(repeating: "a", count: 200)
        XCTAssertFalse(InputValidator.isProjectNameValid(longName))
    }

    func testIsProjectNameValidRejectsSpecialCharacters() {
        XCTAssertFalse(InputValidator.isProjectNameValid("project/name"))
        XCTAssertFalse(InputValidator.isProjectNameValid("name<script>"))
        XCTAssertFalse(InputValidator.isProjectNameValid("name; rm -rf"))
        XCTAssertFalse(InputValidator.isProjectNameValid("name\0evil"))
    }

    func testIsProjectNameValidRejectsOnlyDotsAndDashes() {
        XCTAssertFalse(InputValidator.isProjectNameValid("..."))
        XCTAssertFalse(InputValidator.isProjectNameValid("---"))
        XCTAssertFalse(InputValidator.isProjectNameValid(". . ."))
    }

    // MARK: - Project Name Sanitization

    func testSanitizeProjectNameStripsDisallowedCharacters() {
        let result = InputValidator.sanitizeProjectName("My <Project> v2!")
        XCTAssertFalse(result.contains("<"))
        XCTAssertFalse(result.contains(">"))
        XCTAssertFalse(result.contains("!"))
        XCTAssertTrue(result.contains("My"))
        XCTAssertTrue(result.contains("Project"))
    }

    func testSanitizeProjectNameCollapsesSpaces() {
        let result = InputValidator.sanitizeProjectName("Too    Many   Spaces")
        XCTAssertFalse(result.contains("  "))
    }

    func testSanitizeProjectNameTruncatesLongName() {
        let longName = String(repeating: "x", count: 200)
        let result = InputValidator.sanitizeProjectName(longName)
        XCTAssertLessThanOrEqual(result.count, InputValidator.maxProjectNameLength)
    }

    func testSanitizeProjectNameReturnsDefaultForEmpty() {
        XCTAssertEqual(InputValidator.sanitizeProjectName(""), "Untitled Project")
        XCTAssertEqual(InputValidator.sanitizeProjectName("!!!"), "Untitled Project")
    }

    // MARK: - API Key Format Validation

    func testIsAPIKeyFormatValidAcceptsAnthropicKey() {
        XCTAssertTrue(InputValidator.isAPIKeyFormatValid("sk-ant-api03-abcdefghijklmnop"))
    }

    func testIsAPIKeyFormatValidAcceptsOpenAIKey() {
        XCTAssertTrue(InputValidator.isAPIKeyFormatValid("sk-proj-abcdefghijklmnopqrstuvwx"))
    }

    func testIsAPIKeyFormatValidAcceptsGenericAlphanumericKey() {
        let key = String(repeating: "a1b2c3d4", count: 4) // 32 chars
        XCTAssertTrue(InputValidator.isAPIKeyFormatValid(key))
    }

    func testIsAPIKeyFormatValidRejectsEmptyKey() {
        XCTAssertFalse(InputValidator.isAPIKeyFormatValid(""))
        XCTAssertFalse(InputValidator.isAPIKeyFormatValid("   "))
    }

    func testIsAPIKeyFormatValidRejectsTooShortKey() {
        XCTAssertFalse(InputValidator.isAPIKeyFormatValid("sk-short"))
    }

    func testIsAPIKeyFormatValidRejectsTooLongKey() {
        let longKey = "sk-" + String(repeating: "a", count: 260)
        XCTAssertFalse(InputValidator.isAPIKeyFormatValid(longKey))
    }

    func testIsAPIKeyFormatValidRejectsControlCharacters() {
        let key = "sk-ant-api03-abcdefg\0hijklmnop"
        XCTAssertFalse(InputValidator.isAPIKeyFormatValid(key))
    }

    func testIsAPIKeyFormatValidRejectsKeyWithSpacesAndNoPrefix() {
        XCTAssertFalse(InputValidator.isAPIKeyFormatValid("this has spaces in it and stuff"))
    }

    // MARK: - JSON Validation

    func testIsJSONSafeAcceptsValidObject() {
        XCTAssertTrue(InputValidator.isJSONSafe("{\"key\": \"value\"}"))
    }

    func testIsJSONSafeAcceptsValidArray() {
        XCTAssertTrue(InputValidator.isJSONSafe("[1, 2, 3]"))
    }

    func testIsJSONSafeRejectsEmptyString() {
        XCTAssertFalse(InputValidator.isJSONSafe(""))
    }

    func testIsJSONSafeRejectsNullBytes() {
        XCTAssertFalse(InputValidator.isJSONSafe("{\"key\": \"\0value\"}"))
    }

    func testIsJSONSafeRejectsPlainText() {
        XCTAssertFalse(InputValidator.isJSONSafe("just some text"))
        XCTAssertFalse(InputValidator.isJSONSafe("Hello, World!"))
    }

    func testIsJSONSafeRejectsMismatchedBrackets() {
        XCTAssertFalse(InputValidator.isJSONSafe("{\"key\": \"value\"]"))
        XCTAssertFalse(InputValidator.isJSONSafe("[1, 2, 3}"))
    }

    func testIsJSONSafeRejectsOversizedInput() {
        let largeJSON = "{" + String(repeating: "\"x\"", count: 100) + "}"
        // Use a very small limit to test the check
        XCTAssertFalse(InputValidator.isJSONSafe(largeJSON, maxSize: 10))
    }

    func testIsJSONSafeAcceptsInputUnderLimit() {
        let smallJSON = "{\"a\":1}"
        XCTAssertTrue(InputValidator.isJSONSafe(smallJSON, maxSize: 1000))
    }

    func testIsJSONSafeRejectsWhitespaceOnlyInput() {
        XCTAssertFalse(InputValidator.isJSONSafe("   \n\t  "))
    }

    func testIsJSONSafeHandlesLeadingWhitespace() {
        XCTAssertTrue(InputValidator.isJSONSafe("  \n  {\"key\": 1}  "))
    }

    // MARK: - Edge Cases

    func testSanitizePathWithBackslashTraversal() {
        let result = InputValidator.sanitizePath("..\\..\\Windows\\System32")
        XCTAssertFalse(result.contains("..\\"))
    }

    func testIsProjectNameValidAcceptsSingleCharacter() {
        XCTAssertTrue(InputValidator.isProjectNameValid("A"))
    }

    func testIsProjectNameValidAcceptsMaxLength() {
        let maxName = String(repeating: "a", count: InputValidator.maxProjectNameLength)
        XCTAssertTrue(InputValidator.isProjectNameValid(maxName))
    }

    func testIsAPIKeyFormatValidAcceptsXAIPrefix() {
        XCTAssertTrue(InputValidator.isAPIKeyFormatValid("xai-abcdefghijklmnopqrstuvwx"))
    }

    func testSanitizeProjectNamePreservesValidCharacters() {
        let result = InputValidator.sanitizeProjectName("My-Project_v2.0 (beta)")
        XCTAssertEqual(result, "My-Project_v2.0 (beta)")
    }
}
