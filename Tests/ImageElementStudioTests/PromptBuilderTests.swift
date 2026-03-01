import XCTest
@testable import ImageElementStudio

final class PromptBuilderTests: XCTestCase {

    // MARK: - systemPrompt

    func testSystemPromptForIOSContainsSwiftUIInstructions() {
        let prompt = PromptBuilder.systemPrompt(target: .ios)
        XCTAssertTrue(prompt.contains("SwiftUI"), "iOS system prompt should mention SwiftUI")
        XCTAssertTrue(prompt.contains("iOS 17"), "iOS system prompt should mention iOS 17")
        XCTAssertTrue(prompt.contains("@Observable"), "iOS system prompt should mention @Observable")
        XCTAssertTrue(prompt.contains("NavigationStack"), "iOS system prompt should mention NavigationStack")
        XCTAssertTrue(prompt.contains("No third-party"), "iOS system prompt should forbid third-party deps")
    }

    func testSystemPromptForMacOSContainsDesktopInstructions() {
        let prompt = PromptBuilder.systemPrompt(target: .macos)
        XCTAssertTrue(prompt.contains("macOS 14"), "macOS system prompt should mention macOS 14")
        XCTAssertTrue(prompt.contains("NavigationSplitView"), "macOS system prompt should mention NavigationSplitView")
        XCTAssertTrue(prompt.contains("keyboard shortcuts"), "macOS system prompt should mention keyboard shortcuts")
    }

    func testSystemPromptForWebContainsVanillaWebInstructions() {
        let prompt = PromptBuilder.systemPrompt(target: .web)
        XCTAssertTrue(prompt.contains("HTML5"), "Web system prompt should mention HTML5")
        XCTAssertTrue(prompt.contains("CSS3"), "Web system prompt should mention CSS3")
        XCTAssertTrue(prompt.contains("No frameworks"), "Web system prompt should forbid frameworks")
        XCTAssertTrue(prompt.contains("Responsive"), "Web system prompt should mention responsive design")
    }

    func testSystemPromptNeverContainsPlaceholders() {
        for target in StudioViewModel.BuildTarget.allCases {
            let prompt = PromptBuilder.systemPrompt(target: target)
            XCTAssertTrue(prompt.contains("No stubs"), "System prompt for \(target) should forbid stubs")
            XCTAssertTrue(prompt.contains("no TODOs"), "System prompt for \(target) should forbid TODOs")
            XCTAssertTrue(prompt.contains("no placeholders"), "System prompt for \(target) should forbid placeholders")
        }
    }

    // MARK: - architecturePlanningPrompt — artboard dimensions

    func testArchitecturePlanningPromptIncludesArtboardDimensions() {
        let artboard = Artboard(
            id: UUID(),
            name: "Dashboard",
            width: 1920,
            height: 1080,
            elements: []
        )
        let prompt = PromptBuilder.architecturePlanningPrompt(
            elements: [],
            artboards: [artboard],
            tokens: nil,
            components: [],
            blueprint: nil,
            target: .ios,
            appName: "TestApp"
        )
        XCTAssertTrue(prompt.contains("1920x1080"), "Prompt should include artboard dimensions")
        XCTAssertTrue(prompt.contains("Dashboard"), "Prompt should include artboard name")
    }

    // MARK: - architecturePlanningPrompt — design tokens

    func testArchitecturePlanningPromptHandlesNilTokens() {
        let prompt = PromptBuilder.architecturePlanningPrompt(
            elements: [],
            artboards: [],
            tokens: nil,
            components: [],
            blueprint: nil,
            target: .web,
            appName: "NoTokensApp"
        )
        // Should not crash and should not contain token section header
        XCTAssertFalse(prompt.contains("DESIGN TOKENS"), "Nil tokens should not produce a token section")
    }

    func testArchitecturePlanningPromptIncludesColorTokens() {
        let tokens = DesignTokenSet(
            colors: ["primary": "#FF0000", "secondary": "#00FF00"],
            typography: [:],
            spacing: [:],
            radius: [:],
            shadow: [:],
            motion: [:]
        )
        let prompt = PromptBuilder.architecturePlanningPrompt(
            elements: [],
            artboards: [],
            tokens: tokens,
            components: [],
            blueprint: nil,
            target: .macos,
            appName: "ColorApp"
        )
        XCTAssertTrue(prompt.contains("DESIGN TOKENS"), "Prompt should include token section")
        XCTAssertTrue(prompt.contains("#FF0000"), "Prompt should include color values")
        XCTAssertTrue(prompt.contains("primary"), "Prompt should include color names")
        XCTAssertTrue(prompt.contains("secondary"), "Prompt should include all color names")
    }

    func testArchitecturePlanningPromptIncludesSpacingAndRadius() {
        let tokens = DesignTokenSet(
            colors: [:],
            typography: [:],
            spacing: ["small": 8, "large": 32],
            radius: ["card": 12],
            shadow: [:],
            motion: [:]
        )
        let prompt = PromptBuilder.architecturePlanningPrompt(
            elements: [],
            artboards: [],
            tokens: tokens,
            components: [],
            blueprint: nil,
            target: .ios,
            appName: "SpacingApp"
        )
        XCTAssertTrue(prompt.contains("Spacing:"))
        XCTAssertTrue(prompt.contains("small"))
        XCTAssertTrue(prompt.contains("Corner Radii:"))
        XCTAssertTrue(prompt.contains("card"))
    }

    // MARK: - architecturePlanningPrompt — elements formatted

    func testArchitecturePlanningPromptFormatsElements() {
        let element = CanvasElement(
            id: UUID(),
            name: "Header Title",
            kind: .text,
            frame: ElementFrame(x: 10, y: 20, width: 300, height: 50),
            confidence: 0.95,
            content: "My Dashboard",
            tags: ["heading"],
            semanticRole: .heading,
            semanticReason: "Main title"
        )
        let artboard = Artboard(
            id: UUID(),
            name: "Main",
            width: 1440,
            height: 900,
            elements: [element]
        )
        let prompt = PromptBuilder.architecturePlanningPrompt(
            elements: [element],
            artboards: [artboard],
            tokens: nil,
            components: [],
            blueprint: nil,
            target: .ios,
            appName: "ElementApp"
        )
        XCTAssertTrue(prompt.contains("Header Title"), "Prompt should include element name")
        XCTAssertTrue(prompt.contains("[text]"), "Prompt should include element kind")
        XCTAssertTrue(prompt.contains("My Dashboard"), "Prompt should include element content")
        XCTAssertTrue(prompt.contains("heading"), "Prompt should include semantic role")
    }

    // MARK: - architecturePlanningPrompt — app name and JSON format

    func testArchitecturePlanningPromptIncludesAppNameInJSON() {
        let prompt = PromptBuilder.architecturePlanningPrompt(
            elements: [],
            artboards: [],
            tokens: nil,
            components: [],
            blueprint: nil,
            target: .ios,
            appName: "SuperApp"
        )
        XCTAssertTrue(prompt.contains("\"SuperApp\""), "Prompt should include app name in JSON template")
        XCTAssertTrue(prompt.contains("appName"), "Prompt should request appName field")
        XCTAssertTrue(prompt.contains("files"), "Prompt should request files array")
    }

    // MARK: - buildErrorFixPrompt

    func testBuildErrorFixPromptFormatsErrorsCorrectly() {
        let prompt = PromptBuilder.buildErrorFixPrompt(
            fileContent: "import SwiftUI\nstruct Foo {}",
            fileName: "Foo.swift",
            errors: ["Cannot find type 'Bar'", "Missing return"],
            target: .ios
        )
        XCTAssertTrue(prompt.contains("Foo.swift"), "Fix prompt should include file name")
        XCTAssertTrue(prompt.contains("Cannot find type 'Bar'"), "Fix prompt should include error text")
        XCTAssertTrue(prompt.contains("Missing return"), "Fix prompt should include all errors")
        XCTAssertTrue(prompt.contains("1."), "Fix prompt should number errors")
        XCTAssertTrue(prompt.contains("2."), "Fix prompt should number errors")
        XCTAssertTrue(prompt.contains("import SwiftUI"), "Fix prompt should include file content")
    }

    // MARK: - fileGenerationPrompt

    func testFileGenerationPromptIncludesPlanContext() {
        let plan = FilePlanEntry(
            name: "Theme.swift",
            relativePath: "Sources/App/Theme.swift",
            role: .theme,
            description: "App-wide color and font constants",
            keyTypes: ["AppTheme"],
            dependencies: []
        )
        let prompt = PromptBuilder.fileGenerationPrompt(
            filePlan: plan,
            architecturePlan: "{ some plan json }",
            previousFileSignatures: ["// --- Models.swift ---\nstruct Item {}"],
            target: .ios
        )
        XCTAssertTrue(prompt.contains("Theme.swift"), "Should include file path")
        XCTAssertTrue(prompt.contains("theme"), "Should include role")
        XCTAssertTrue(prompt.contains("AppTheme"), "Should include key types")
        XCTAssertTrue(prompt.contains("Models.swift"), "Should include previous file signatures")
        XCTAssertTrue(prompt.contains("iOS 17"), "Should include target-specific reminder")
    }
}
