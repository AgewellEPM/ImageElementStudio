import XCTest
@testable import ImageElementStudio

final class CodeValidatorTests: XCTestCase {

    // MARK: - stripCodeFences

    func testStripCodeFencesRemovesSwiftFence() {
        let input = """
        ```swift
        import SwiftUI
        struct ContentView: View {
            var body: some View { Text("Hello") }
        }
        ```
        """
        let result = CodeValidator.stripCodeFences(input)
        XCTAssertFalse(result.contains("```"))
        XCTAssertTrue(result.contains("import SwiftUI"))
        XCTAssertTrue(result.contains("ContentView"))
    }

    func testStripCodeFencesRemovesBareFence() {
        let input = """
        ```
        let x = 42
        ```
        """
        let result = CodeValidator.stripCodeFences(input)
        XCTAssertFalse(result.contains("```"))
        XCTAssertTrue(result.contains("let x = 42"))
    }

    func testStripCodeFencesLeavesCleanCodeUnchanged() {
        let input = "import Foundation\nlet x = 1"
        let result = CodeValidator.stripCodeFences(input)
        XCTAssertEqual(result, input)
    }

    // MARK: - checkBalancedBraces (valid code)

    func testBalancedBracesValidCode() {
        let code = """
        struct Foo {
            func bar() -> [Int] {
                return [1, 2, 3]
            }
        }
        """
        let errors = CodeValidator.checkBalancedBraces(code)
        XCTAssertTrue(errors.isEmpty, "Expected no brace errors for valid code, got: \(errors.map(\.message))")
    }

    // MARK: - checkBalancedBraces (invalid code)

    func testUnbalancedCurlyBracesDetected() {
        let code = """
        struct Foo {
            func bar() {
                // missing closing brace
        }
        """
        let errors = CodeValidator.checkBalancedBraces(code)
        XCTAssertFalse(errors.isEmpty, "Expected brace errors for unbalanced curlies")
        XCTAssertTrue(errors.contains { $0.message.contains("curly braces") })
        XCTAssertTrue(errors.allSatisfy { $0.severity == .error })
    }

    func testExtraClosingParenDetected() {
        let code = "func foo() { return (1 + 2)) }"
        let errors = CodeValidator.checkBalancedBraces(code)
        XCTAssertTrue(errors.contains { $0.message.contains("parentheses") })
    }

    func testBracesInsideStringLiteralsAreIgnored() {
        let code = """
        let x = "{ unbalanced"
        let y = "( also unbalanced ]"
        """
        let errors = CodeValidator.checkBalancedBraces(code)
        XCTAssertTrue(errors.isEmpty, "Braces inside strings should be ignored, got: \(errors.map(\.message))")
    }

    func testBracesInsideCommentsAreIgnored() {
        let code = """
        // This has an unmatched { in a comment
        /* And this has unmatched ( in a block comment */
        let x = 1
        """
        let errors = CodeValidator.checkBalancedBraces(code)
        XCTAssertTrue(errors.isEmpty, "Braces inside comments should be ignored, got: \(errors.map(\.message))")
    }

    // MARK: - checkForArtifacts

    func testCheckForArtifactsDetectsPlaceholderComments() {
        let code = """
        import SwiftUI
        struct MyView: View {
            var body: some View {
                // ... rest of the view
                Text("Hello")
            }
        }
        """
        let errors = CodeValidator.checkForArtifacts(code)
        XCTAssertFalse(errors.isEmpty, "Expected artifact warnings for placeholder comment")
        XCTAssertTrue(errors.contains { $0.message.contains("rest of") })
        XCTAssertTrue(errors.allSatisfy { $0.severity == .warning })
    }

    func testCheckForArtifactsDetectsTODOImplement() {
        let code = """
        import Foundation
        class Service {
            func fetchData() {
                // TODO: implement
            }
        }
        """
        let errors = CodeValidator.checkForArtifacts(code)
        XCTAssertTrue(errors.contains { $0.message.contains("TODO: implement") })
    }

    func testCheckForArtifactsDetectsTripleBacktickInBody() {
        let code = """
        import Foundation
        ```swift
        let x = 1
        ```
        """
        let errors = CodeValidator.checkForArtifacts(code)
        XCTAssertTrue(errors.contains { $0.message.contains("backtick") })
    }

    func testCheckForArtifactsCleanCodeReturnsNoWarnings() {
        let code = """
        import SwiftUI
        struct ContentView: View {
            var body: some View {
                Text("Hello, World!")
            }
        }
        """
        let errors = CodeValidator.checkForArtifacts(code)
        XCTAssertTrue(errors.isEmpty, "Clean code should have no artifact warnings, got: \(errors.map(\.message))")
    }

    // MARK: - checkNotEmpty

    func testCheckNotEmptyDetectsTrivialContent() {
        let errors = CodeValidator.checkNotEmpty("abc")
        XCTAssertFalse(errors.isEmpty)
        XCTAssertTrue(errors.first?.severity == .error)
    }

    func testCheckNotEmptyAcceptsSubstantialContent() {
        let content = "import Foundation\nlet value = 42"
        let errors = CodeValidator.checkNotEmpty(content)
        XCTAssertTrue(errors.isEmpty)
    }

    // MARK: - checkRequiredImports

    func testCheckRequiredImportsSwiftFileMissingImport() {
        let errors = CodeValidator.checkRequiredImports("struct Foo {}", fileRole: .rootView)
        XCTAssertFalse(errors.isEmpty, "Swift files without import should produce an error")
        XCTAssertTrue(errors.first?.severity == .error)
    }

    func testCheckRequiredImportsSwiftFileWithImport() {
        let code = "import SwiftUI\nstruct ContentView: View { var body: some View { EmptyView() } }"
        let errors = CodeValidator.checkRequiredImports(code, fileRole: .rootView)
        XCTAssertTrue(errors.isEmpty)
    }

    func testCheckRequiredImportsHTMLWithDoctype() {
        let code = "<!DOCTYPE html>\n<html><head></head><body></body></html>"
        let errors = CodeValidator.checkRequiredImports(code, fileRole: .webMarkup)
        XCTAssertTrue(errors.isEmpty)
    }

    func testCheckRequiredImportsHTMLMissingDoctype() {
        let code = "<div>Hello</div>"
        let errors = CodeValidator.checkRequiredImports(code, fileRole: .webMarkup)
        XCTAssertFalse(errors.isEmpty)
        XCTAssertTrue(errors.first?.severity == .warning)
    }

    func testCheckRequiredImportsCSSFileNoImportNeeded() {
        let code = "body { margin: 0; }"
        let errors = CodeValidator.checkRequiredImports(code, fileRole: .webStyle)
        XCTAssertTrue(errors.isEmpty)
    }

    func testCheckRequiredImportsJSFileNoImportNeeded() {
        let code = "console.log('hello');"
        let errors = CodeValidator.checkRequiredImports(code, fileRole: .webScript)
        XCTAssertTrue(errors.isEmpty)
    }

    // MARK: - Full validate (integration)

    func testValidateValidSwiftEntry() {
        let entry = GeneratedFileEntry(
            name: "ContentView.swift",
            relativePath: "Sources/App/ContentView.swift",
            content: """
            ```swift
            import SwiftUI

            struct ContentView: View {
                var body: some View {
                    Text("Hello, World!")
                        .font(.largeTitle)
                        .padding()
                }
            }
            ```
            """,
            role: .rootView
        )
        let result = CodeValidator.validate(entry: entry)
        XCTAssertTrue(result.isValid, "Expected valid result, got errors: \(result.errors.map(\.message))")
        XCTAssertFalse(result.cleanedContent.contains("```"), "Code fences should be stripped")
        XCTAssertTrue(result.cleanedContent.contains("import SwiftUI"))
    }

    func testValidateInvalidSwiftEntryUnbalancedBraces() {
        let entry = GeneratedFileEntry(
            name: "Broken.swift",
            relativePath: "Sources/App/Broken.swift",
            content: """
            import SwiftUI

            struct BrokenView: View {
                var body: some View {
                    Text("Missing close")
            }
            """,
            role: .screenView
        )
        let result = CodeValidator.validate(entry: entry)
        XCTAssertFalse(result.isValid, "Unbalanced braces should make the entry invalid")
        let errorMessages = result.errors.filter { $0.severity == .error }.map(\.message)
        XCTAssertTrue(errorMessages.contains { $0.contains("curly braces") })
    }
}
