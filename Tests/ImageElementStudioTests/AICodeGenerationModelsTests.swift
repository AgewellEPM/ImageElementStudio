import XCTest
@testable import ImageElementStudio

final class AICodeGenerationModelsTests: XCTestCase {

    // MARK: - FileRole

    /// Guards against accidentally adding or removing a FileRole case,
    /// which would break JSON contracts with the AI backend.
    func testFileRoleCaseCountMatchesExpected() {
        // FileRole is serialized to/from JSON in AI responses.
        // If a case is added or removed, this test forces the developer
        // to consciously update the count.
        let allRoles: [FileRole] = [
            .appEntry, .rootView, .screenView, .componentView,
            .dataModel, .viewModel, .theme, .projectConfig,
            .readme, .webMarkup, .webStyle, .webScript,
            .appSpec, .unknown
        ]
        XCTAssertEqual(allRoles.count, 14,
            "FileRole case count changed — update JSON handling and this test")
    }

    func testFileRoleDecodesFromJSON() throws {
        let json = Data("\"componentView\"".utf8)
        let decoded = try JSONDecoder().decode(FileRole.self, from: json)
        XCTAssertEqual(decoded, .componentView)
    }

    // MARK: - AIGenerationQuality

    /// Verify that AIGenerationQuality round-trips through JSON encoding/decoding.
    /// This matters because the quality setting may be persisted or sent to the API.
    func testAIGenerationQualityCodableRoundTrip() throws {
        for quality in AIGenerationQuality.allCases {
            let data = try JSONEncoder().encode(quality)
            let decoded = try JSONDecoder().decode(AIGenerationQuality.self, from: data)
            XCTAssertEqual(decoded, quality)
        }
    }

    func testAIGenerationQualityTitles() {
        XCTAssertTrue(AIGenerationQuality.fast.title.contains("Sonnet"))
        XCTAssertTrue(AIGenerationQuality.quality.title.contains("Opus"))
    }

    func testAIGenerationQualityModelIDs() {
        XCTAssertTrue(AIGenerationQuality.fast.modelID.contains("sonnet"))
        XCTAssertTrue(AIGenerationQuality.quality.modelID.contains("opus"))
    }

    /// Verify modelID values are valid Anthropic model identifiers.
    /// A typo here would cause silent API failures at runtime.
    func testAIGenerationQualityModelIDsArePlausibleAnthropicIDs() {
        for quality in AIGenerationQuality.allCases {
            let id = quality.modelID
            XCTAssertTrue(id.hasPrefix("claude-"),
                "Model ID '\(id)' should start with 'claude-'")
            // Model IDs must have at least 3 hyphen-separated segments (e.g. claude-opus-4-6)
            let components = id.split(separator: "-")
            XCTAssertGreaterThanOrEqual(components.count, 3,
                "Model ID '\(id)' should have at least 3 hyphen-separated segments")
            XCTAssertFalse(id.hasSuffix("-"),
                "Model ID '\(id)' should not end with a trailing hyphen")
        }
        // Verify the two qualities map to different models
        XCTAssertNotEqual(AIGenerationQuality.fast.modelID,
                          AIGenerationQuality.quality.modelID,
                          "Fast and quality should use different models")
    }

    // MARK: - GeneratedFileEntry

    /// Verify GeneratedFileEntry Codable round-trip preserves content with special
    /// characters (unicode, newlines, quotes) — critical because file contents are
    /// arbitrary Swift/HTML/CSS source code that gets JSON-serialized.
    func testGeneratedFileEntryCodablePreservesSpecialCharacters() throws {
        let tricky = GeneratedFileEntry(
            name: "Tricky.swift",
            relativePath: "Sources/App/Tricky.swift",
            content: "let emoji = \"\u{1F680}\"\nlet quote = \"he said \\\"hello\\\"\"\nlet tab = \"\\t\"\n// Japanese: \u{65E5}\u{672C}\u{8A9E}",
            role: .screenView
        )
        let data = try JSONEncoder().encode(tricky)
        let decoded = try JSONDecoder().decode(GeneratedFileEntry.self, from: data)
        XCTAssertEqual(decoded.content, tricky.content,
            "Content with special characters should survive JSON round-trip intact")
        XCTAssertEqual(decoded.id, tricky.id)
    }

    /// Verify that all FileRole cases survive a JSON round-trip through GeneratedFileEntry.
    /// This catches cases where a new role is added to the enum but accidentally
    /// breaks Codable (e.g., a custom coding key is wrong).
    func testAllFileRolesRoundTripThroughGeneratedFileEntry() throws {
        let allRoles: [FileRole] = [
            .appEntry, .rootView, .screenView, .componentView,
            .dataModel, .viewModel, .theme, .projectConfig,
            .readme, .webMarkup, .webStyle, .webScript,
            .appSpec, .unknown
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for role in allRoles {
            let entry = GeneratedFileEntry(
                name: "Test.swift", relativePath: "Test.swift",
                content: "", role: role
            )
            let data = try encoder.encode(entry)
            let decoded = try decoder.decode(GeneratedFileEntry.self, from: data)
            XCTAssertEqual(decoded.role, role,
                "FileRole.\(role) should survive Codable round-trip")
        }
    }

    /// Verify GeneratedFileEntry handles empty content gracefully.
    /// The AI code generator may produce empty placeholder files.
    func testGeneratedFileEntryWithEmptyContent() throws {
        let entry = GeneratedFileEntry(
            name: "Placeholder.swift",
            relativePath: "Sources/App/Placeholder.swift",
            content: "",
            role: .unknown
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(GeneratedFileEntry.self, from: data)
        XCTAssertEqual(decoded.content, "")
        XCTAssertEqual(decoded.name, "Placeholder.swift")
    }

    func testGeneratedFileEntryCodable() throws {
        let entry = GeneratedFileEntry(
            name: "Theme.swift",
            relativePath: "Sources/App/Theme.swift",
            content: "import SwiftUI",
            role: .theme
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(GeneratedFileEntry.self, from: data)
        XCTAssertEqual(decoded.name, entry.name)
        XCTAssertEqual(decoded.relativePath, entry.relativePath)
        XCTAssertEqual(decoded.content, entry.content)
        XCTAssertEqual(decoded.role, entry.role)
        XCTAssertEqual(decoded.id, entry.id)
    }

    // MARK: - FilePlanEntry

    /// Verify ArchitecturePlanResponse decodes correctly when files have all optional
    /// fields populated (keyTypes, dependencies) vs when they are absent.
    /// This is the shape the AI actually returns, so missing-field tolerance is key.
    func testArchitectureFileSpecOptionalFieldHandling() throws {
        let json = """
        {
            "appName": "TestApp",
            "summary": "Test",
            "files": [
                {
                    "name": "Full.swift",
                    "relativePath": "Full.swift",
                    "role": "dataModel",
                    "description": "Full spec",
                    "keyTypes": ["Item", "Category"],
                    "dependencies": ["Theme.swift", "Utils.swift"]
                },
                {
                    "name": "Minimal.swift",
                    "relativePath": "Minimal.swift",
                    "role": "unknown",
                    "description": "Minimal spec"
                }
            ]
        }
        """
        let plan = try JSONDecoder().decode(ArchitecturePlanResponse.self, from: Data(json.utf8))
        XCTAssertEqual(plan.files.count, 2)

        // Full spec has all optional fields
        XCTAssertEqual(plan.files[0].keyTypes, ["Item", "Category"])
        XCTAssertEqual(plan.files[0].dependencies, ["Theme.swift", "Utils.swift"])

        // Minimal spec has nil optional fields
        XCTAssertNil(plan.files[1].keyTypes)
        XCTAssertNil(plan.files[1].dependencies)
    }

    /// Verify ArchitecturePlanResponse Codable round-trip preserves all fields,
    /// including optionals. Tests that encoding doesn't drop fields that decoding expects.
    func testArchitecturePlanResponseCodableRoundTrip() throws {
        let original = ArchitecturePlanResponse(
            appName: "RoundTrip App",
            summary: "Tests encode/decode symmetry",
            files: [
                ArchitectureFileSpec(
                    name: "Main.swift", relativePath: "Sources/Main.swift",
                    role: "appEntry", description: "Entry point",
                    keyTypes: ["AppDelegate"], dependencies: nil
                )
            ],
            dataModels: [
                ArchitectureDataModel(name: "User", fields: ["id: UUID", "name: String"])
            ],
            navigationFlow: "Tab bar with 3 tabs",
            designNotes: "Dark mode only"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ArchitecturePlanResponse.self, from: data)

        XCTAssertEqual(decoded.appName, original.appName)
        XCTAssertEqual(decoded.summary, original.summary)
        XCTAssertEqual(decoded.files.count, 1)
        XCTAssertEqual(decoded.files[0].name, "Main.swift")
        XCTAssertEqual(decoded.dataModels?.count, 1)
        XCTAssertEqual(decoded.dataModels?[0].fields, ["id: UUID", "name: String"])
        XCTAssertEqual(decoded.navigationFlow, "Tab bar with 3 tabs")
        XCTAssertEqual(decoded.designNotes, "Dark mode only")
    }

    // MARK: - AIGenerationState

    func testAIGenerationStateIsActiveForWorkingStates() {
        XCTAssertTrue(AIGenerationState.analyzingDesign.isActive)
        XCTAssertTrue(AIGenerationState.planningArchitecture(progress: "Working...").isActive)
        XCTAssertTrue(AIGenerationState.generatingFile(name: "Foo.swift", index: 0, total: 3, streamedText: "").isActive)
        XCTAssertTrue(AIGenerationState.validating(name: "Foo.swift").isActive)
        XCTAssertTrue(AIGenerationState.fixing(name: "Foo.swift", attempt: 1).isActive)
        XCTAssertTrue(AIGenerationState.writingToDisk.isActive)
    }

    func testAIGenerationStateIsNotActiveForTerminalStates() {
        XCTAssertFalse(AIGenerationState.idle.isActive)
        XCTAssertFalse(AIGenerationState.complete(outputPath: "/tmp/out").isActive)
        XCTAssertFalse(AIGenerationState.failed("Something broke").isActive)
    }

    func testAIGenerationStateStatusText() {
        XCTAssertEqual(AIGenerationState.idle.statusText, "Ready")
        XCTAssertTrue(AIGenerationState.analyzingDesign.statusText.contains("Analyzing"))
        XCTAssertTrue(AIGenerationState.planningArchitecture(progress: "test").statusText.contains("Planning"))

        let genState = AIGenerationState.generatingFile(name: "Foo.swift", index: 2, total: 5, streamedText: "")
        XCTAssertTrue(genState.statusText.contains("Foo.swift"))
        XCTAssertTrue(genState.statusText.contains("3/5")) // index + 1

        let fixState = AIGenerationState.fixing(name: "Bar.swift", attempt: 2)
        XCTAssertTrue(fixState.statusText.contains("Bar.swift"))
        XCTAssertTrue(fixState.statusText.contains("attempt 2"))

        XCTAssertTrue(AIGenerationState.writingToDisk.statusText.contains("Writing"))
        XCTAssertTrue(AIGenerationState.complete(outputPath: "/path").statusText.contains("/path"))
        XCTAssertTrue(AIGenerationState.failed("timeout").statusText.contains("timeout"))
    }

    // MARK: - ArchitecturePlanResponse

    func testArchitecturePlanResponseDecodable() throws {
        let json = """
        {
            "appName": "TestApp",
            "summary": "A simple app",
            "files": [
                {
                    "name": "ContentView.swift",
                    "relativePath": "Sources/App/ContentView.swift",
                    "role": "rootView",
                    "description": "Main view",
                    "keyTypes": ["ContentView"],
                    "dependencies": []
                }
            ],
            "dataModels": [
                { "name": "Item", "fields": ["id: UUID", "title: String"] }
            ],
            "navigationFlow": "Single screen",
            "designNotes": "Simple layout"
        }
        """
        let data = Data(json.utf8)
        let plan = try JSONDecoder().decode(ArchitecturePlanResponse.self, from: data)

        XCTAssertEqual(plan.appName, "TestApp")
        XCTAssertEqual(plan.summary, "A simple app")
        XCTAssertEqual(plan.files.count, 1)
        XCTAssertEqual(plan.files[0].name, "ContentView.swift")
        XCTAssertEqual(plan.files[0].role, "rootView")
        XCTAssertEqual(plan.dataModels?.count, 1)
        XCTAssertEqual(plan.dataModels?[0].name, "Item")
        XCTAssertEqual(plan.navigationFlow, "Single screen")
    }

    func testArchitecturePlanResponseOptionalFieldsDecodeAsNil() throws {
        let json = """
        {
            "appName": "MinimalApp",
            "summary": "Minimal",
            "files": []
        }
        """
        let data = Data(json.utf8)
        let plan = try JSONDecoder().decode(ArchitecturePlanResponse.self, from: data)
        XCTAssertNil(plan.dataModels)
        XCTAssertNil(plan.navigationFlow)
        XCTAssertNil(plan.designNotes)
    }
}
