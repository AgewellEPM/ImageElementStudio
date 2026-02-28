import Foundation

struct PromptBuilder: Sendable {

    // MARK: - Type Alias

    private typealias BuildTarget = StudioViewModel.BuildTarget

    // MARK: - System Prompt

    static func systemPrompt(target: StudioViewModel.BuildTarget) -> String {
        switch target {
        case .ios:
            return """
            You are a production iOS app architect and SwiftUI expert. \
            Generate clean, idiomatic SwiftUI code targeting iOS 17+/Swift 5.9+.

            Rules:
            - Use @Observable macro for view models (Observation framework, not ObservableObject).
            - Use NavigationStack (not NavigationView).
            - Use async/await for all asynchronous work. No Combine unless essential.
            - Proper use of @State, @Binding, @Environment. Minimal @StateObject.
            - No third-party dependencies. Use only Apple frameworks.
            - Follow Apple Human Interface Guidelines for spacing, typography, and layout.
            - Every View struct goes in its own file unless trivially small (< 15 lines).
            - Models must be Codable and Sendable where appropriate.
            - Use SF Symbols for icons.
            - Include MARK comments for logical sections.
            - Generate complete, compiling code. No stubs, no TODOs, no placeholders.
            """

        case .macos:
            return """
            You are a production macOS app architect and SwiftUI expert. \
            Generate clean, idiomatic SwiftUI code targeting macOS 14+/Swift 5.9+.

            Rules:
            - Use @Observable macro for view models (Observation framework, not ObservableObject).
            - Use NavigationSplitView for sidebar/detail patterns.
            - Use async/await for all asynchronous work.
            - Proper use of @State, @Binding, @Environment.
            - No third-party dependencies. Use only Apple frameworks.
            - Follow macOS Human Interface Guidelines: toolbars, sidebars, split views.
            - Support keyboard shortcuts and menu bar where relevant.
            - Models must be Codable and Sendable where appropriate.
            - Use SF Symbols for icons.
            - Include MARK comments for logical sections.
            - Generate complete, compiling code. No stubs, no TODOs, no placeholders.
            """

        case .web:
            return """
            You are a senior frontend developer. \
            Generate production-quality vanilla HTML5, CSS3, and JavaScript (ES2022+).

            Rules:
            - No frameworks, no build tools, no npm. Pure HTML/CSS/JS only.
            - Semantic HTML elements (header, nav, main, section, article, footer).
            - Modern CSS: custom properties, flexbox, grid, clamp(), container queries.
            - Responsive design with mobile-first approach.
            - Accessible: ARIA attributes, keyboard navigation, focus management.
            - Clean separation: one HTML file, one CSS file, one or more JS files.
            - Use CSS custom properties for theming (colors, spacing, typography).
            - Use ES modules where beneficial.
            - No inline styles or inline scripts in HTML.
            - Generate complete, working code. No stubs, no TODOs, no placeholders.
            """
        }
    }

    // MARK: - Architecture Planning Prompt

    static func architecturePlanningPrompt(
        elements: [CanvasElement],
        artboards: [Artboard],
        tokens: DesignTokenSet?,
        components: [ComponentSpec],
        blueprint: BuildBlueprint?,
        target: StudioViewModel.BuildTarget,
        appName: String
    ) -> String {
        var sections: [String] = []

        // Header
        sections.append("""
        Plan the file architecture for "\(appName)" (\(target.title) app).
        Below is the complete design data extracted from the user's mockup. \
        Analyze it and produce an architecture plan.
        """)

        // Artboards & elements
        sections.append(serializeArtboards(artboards, elements: elements))

        // Design tokens
        if let tokens {
            sections.append(serializeTokens(tokens))
        }

        // Components
        if !components.isEmpty {
            sections.append(serializeComponents(components))
        }

        // Build blueprint
        if let blueprint {
            sections.append(serializeBlueprint(blueprint))
        }

        // Target-specific instructions
        sections.append(targetArchitectureInstructions(target))

        // Response format instructions
        sections.append("""
        Respond with ONLY a JSON object in this exact format (no markdown, no explanation):
        {
          "appName": "\(appName)",
          "summary": "Brief description of the app architecture",
          "files": [
            {
              "name": "ContentView.swift",
              "relativePath": "\(filePrefixForTarget(target))ContentView.swift",
              "role": "rootView",
              "description": "Main content view with navigation",
              "keyTypes": ["ContentView"],
              "dependencies": []
            }
          ],
          "dataModels": [
            {
              "name": "Item",
              "fields": ["id: UUID", "title: String", "createdAt: Date"]
            }
          ],
          "navigationFlow": "Description of screen-to-screen navigation",
          "designNotes": "Key design decisions"
        }

        Valid role values: appEntry, rootView, screenView, componentView, dataModel, viewModel, theme, projectConfig, readme, webMarkup, webStyle, webScript, appSpec, unknown.
        Order files so foundational types (models, theme) come before views that depend on them.
        """)

        return sections.joined(separator: "\n\n")
    }

    // MARK: - File Generation Prompt

    static func fileGenerationPrompt(
        filePlan: FilePlanEntry,
        architecturePlan: String,
        previousFileSignatures: [String],
        target: StudioViewModel.BuildTarget
    ) -> String {
        var sections: [String] = []

        sections.append("""
        Generate the file: \(filePlan.relativePath)
        Role: \(filePlan.role.rawValue)
        Description: \(filePlan.description)
        """)

        if !filePlan.keyTypes.isEmpty {
            sections.append("Key types to define: \(filePlan.keyTypes.joined(separator: ", "))")
        }

        if !filePlan.dependencies.isEmpty {
            sections.append("Dependencies (files this imports from): \(filePlan.dependencies.joined(separator: ", "))")
        }

        // Provide context of already-generated files
        if !previousFileSignatures.isEmpty {
            sections.append("""
            Already-generated type/function signatures (use these, do not redefine them):
            \(previousFileSignatures.joined(separator: "\n"))
            """)
        }

        // Full architecture plan for context
        sections.append("""
        Full architecture plan for reference:
        \(architecturePlan)
        """)

        // Target-specific reminders
        switch target {
        case .ios:
            sections.append("Target: iOS 17+ SwiftUI. Use @Observable, NavigationStack, async/await.")
        case .macos:
            sections.append("Target: macOS 14+ SwiftUI. Use @Observable, NavigationSplitView, async/await.")
        case .web:
            sections.append("Target: Vanilla HTML/CSS/JS. No frameworks, semantic HTML, responsive design.")
        }

        sections.append("""
        Output ONLY the file contents. No explanation, no markdown code fences, no commentary. \
        Start directly with the first line of the file (e.g., "import SwiftUI" or "<!DOCTYPE html>").
        """)

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Build Error Fix Prompt

    static func buildErrorFixPrompt(
        fileContent: String,
        fileName: String,
        errors: [String],
        target: StudioViewModel.BuildTarget
    ) -> String {
        let errorList = errors.enumerated()
            .map { "  \($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")

        return """
        The file "\(fileName)" has build errors. Fix all of them.

        Build errors:
        \(errorList)

        Current file contents:
        \(fileContent)

        Rules:
        - Fix every listed error.
        - Do not change functionality or remove features.
        - Do not add new features.
        - Keep the same file structure and naming.
        - Target: \(target.title) (\(platformVersionString(target))).
        - Output ONLY the corrected file contents. No explanation, no markdown code fences.
        """
    }

    // MARK: - Private: Serialization Helpers

    private static func serializeArtboards(_ artboards: [Artboard], elements: [CanvasElement]) -> String {
        var lines: [String] = ["## ARTBOARDS & ELEMENTS"]

        // Combine artboard-embedded elements with any loose elements
        let allArtboardElementIDs = Set(artboards.flatMap { $0.elements.map(\.id) })
        let looseElements = elements.filter { !allArtboardElementIDs.contains($0.id) }

        for artboard in artboards {
            lines.append("### Artboard: \(artboard.name) (\(artboard.width)x\(artboard.height))")

            let relevantElements = artboard.elements.filter { $0.kind != .imageRoot }
            for element in relevantElements {
                lines.append(serializeElement(element))
            }
        }

        if !looseElements.isEmpty {
            lines.append("### Unassigned Elements")
            for element in looseElements.filter({ $0.kind != .imageRoot }) {
                lines.append(serializeElement(element))
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func serializeElement(_ el: CanvasElement) -> String {
        var parts: [String] = []
        parts.append("- \(el.name) [\(el.kind.rawValue)]")
        parts.append("  frame: (\(Int(el.frame.x)),\(Int(el.frame.y)) \(Int(el.frame.width))x\(Int(el.frame.height)))")

        if let role = el.semanticRole, role != .unknown {
            parts.append("  role: \(role.rawValue)")
        }

        if let content = el.content, !content.isEmpty {
            let truncated = content.count > 120 ? String(content.prefix(120)) + "..." : content
            parts.append("  text: \"\(truncated)\"")
        }

        if let style = el.style {
            var styleParts: [String] = []
            if let fill = style.fill?.color { styleParts.append("fill:\(fill)") }
            if let stroke = style.stroke?.color { styleParts.append("stroke:\(stroke)") }
            if let radius = style.cornerRadius { styleParts.append("radius:\(Int(radius))") }
            if let opacity = style.opacity, opacity < 1.0 { styleParts.append("opacity:\(String(format: "%.2f", opacity))") }
            if let typo = style.typography {
                var typoParts: [String] = []
                if let family = typo.family { typoParts.append(family) }
                if let weight = typo.weight { typoParts.append(weight) }
                if let size = typo.size { typoParts.append("\(Int(size))pt") }
                if !typoParts.isEmpty { styleParts.append("font:[\(typoParts.joined(separator: " "))]") }
            }
            if !styleParts.isEmpty {
                parts.append("  style: \(styleParts.joined(separator: ", "))")
            }
        }

        if !el.tags.isEmpty {
            parts.append("  tags: \(el.tags.joined(separator: ", "))")
        }

        if let parentID = el.parentElementID {
            parts.append("  parent: \(parentID.uuidString.prefix(8))")
        }

        return parts.joined(separator: "\n")
    }

    private static func serializeTokens(_ tokens: DesignTokenSet) -> String {
        var lines: [String] = ["## DESIGN TOKENS"]

        if !tokens.colors.isEmpty {
            lines.append("Colors:")
            for (name, value) in tokens.colors.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(name): \(value)")
            }
        }

        if !tokens.typography.isEmpty {
            lines.append("Typography:")
            for (name, value) in tokens.typography.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(name): \(value)")
            }
        }

        if !tokens.spacing.isEmpty {
            lines.append("Spacing:")
            for (name, value) in tokens.spacing.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(name): \(Int(value))")
            }
        }

        if !tokens.radius.isEmpty {
            lines.append("Corner Radii:")
            for (name, value) in tokens.radius.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(name): \(Int(value))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func serializeComponents(_ components: [ComponentSpec]) -> String {
        var lines: [String] = ["## COMPONENTS"]

        for comp in components {
            lines.append("- \(comp.name) [\(comp.kind.rawValue)]")
            if let role = comp.role { lines.append("  role: \(role.rawValue)") }
            if !comp.notes.isEmpty { lines.append("  notes: \(comp.notes)") }

            if let axes = comp.variantAxes, !axes.isEmpty {
                let variants = axes.map { "\($0.key): \($0.value.joined(separator: "|"))" }
                lines.append("  variants: \(variants.joined(separator: "; "))")
            }

            if let states = comp.stateMappings, !states.isEmpty {
                let stateList = states.map { "\($0.key) -> \($0.value)" }
                lines.append("  states: \(stateList.joined(separator: "; "))")
            }

            if let bindings = comp.tokenBindings, !bindings.isEmpty {
                let bindingList = bindings.map { "\($0.key): \($0.value)" }
                lines.append("  tokens: \(bindingList.joined(separator: "; "))")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func serializeBlueprint(_ blueprint: BuildBlueprint) -> String {
        var lines: [String] = ["## BUILD BLUEPRINT"]
        lines.append("Mirror score: \(String(format: "%.1f", blueprint.mirrorScore))")
        lines.append("Summary: \(blueprint.detectionSummary)")

        if !blueprint.controls.isEmpty {
            lines.append("Controls:")
            for ctrl in blueprint.controls {
                lines.append("  - \(ctrl.label) [\(ctrl.kind.rawValue)] confidence:\(String(format: "%.2f", ctrl.confidence))")
            }
        }

        if !blueprint.states.isEmpty {
            lines.append("States:")
            for state in blueprint.states {
                lines.append("  - \(state.name): \(state.description) (trigger: \(state.triggerLabel))")
            }
        }

        if !blueprint.buildNotes.isEmpty {
            lines.append("Notes:")
            for note in blueprint.buildNotes {
                lines.append("  - \(note)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private: Target-Specific Instructions

    private static func targetArchitectureInstructions(_ target: StudioViewModel.BuildTarget) -> String {
        switch target {
        case .ios:
            return """
            ## TARGET: iOS 17+ SwiftUI
            - App entry: @main App struct with WindowGroup.
            - Root view: ContentView with NavigationStack.
            - File prefix: Sources/App/
            - Prefer List, LazyVGrid, TabView for layout.
            - Use @Observable view models (import Observation).
            - Group related views into logical files.
            """

        case .macos:
            return """
            ## TARGET: macOS 14+ SwiftUI
            - App entry: @main App struct with WindowGroup.
            - Root view: ContentView with NavigationSplitView.
            - File prefix: Sources/App/
            - Use .toolbar for actions, Settings scene for preferences.
            - Support keyboard shortcuts with .keyboardShortcut.
            - Use @Observable view models (import Observation).
            """

        case .web:
            return """
            ## TARGET: Web (Vanilla HTML/CSS/JS)
            - Entry: index.html with linked CSS and JS.
            - Use semantic HTML5 elements.
            - CSS: custom properties for theme tokens, flexbox/grid layout.
            - JS: ES2022+, class-based or module pattern.
            - File prefix: src/
            - Mobile-first responsive breakpoints.
            """
        }
    }

    private static func filePrefixForTarget(_ target: StudioViewModel.BuildTarget) -> String {
        switch target {
        case .ios, .macos:
            return "Sources/App/"
        case .web:
            return "src/"
        }
    }

    private static func platformVersionString(_ target: StudioViewModel.BuildTarget) -> String {
        switch target {
        case .ios:
            return "iOS 17+, SwiftUI, Swift 5.9+"
        case .macos:
            return "macOS 14+, SwiftUI, Swift 5.9+"
        case .web:
            return "HTML5/CSS3/ES2022+"
        }
    }
}
