import Foundation

// MARK: - Internal Helpers

extension ScaffoldGenerator {

    static func normalizedStateNames(from manifest: StudioViewModel.BuildManifest) -> [String] {
        let states = manifest.inferredStates
            .map(\.name)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return states.isEmpty ? ["Default"] : Array(Set(states)).sorted()
    }

    static func normalizedControlLabels(from manifest: StudioViewModel.BuildManifest) -> [String] {
        let controls = manifest.inferredControls
            .map(\.label)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return controls.isEmpty ? ["Primary Action"] : Array(Set(controls)).sorted()
    }

    static func normalizedCapabilities(from manifest: StudioViewModel.BuildManifest) -> [String] {
        let capabilities = manifest.capabilities
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return capabilities.isEmpty ? ["Core workflow support"] : capabilities
    }

    static func inferredTransitions(states: [String], controls: [String]) -> [GeneratedFlowTransition] {
        guard !states.isEmpty, !controls.isEmpty else { return [] }
        return controls.enumerated().map { index, control in
            let fromState = states[index % states.count]
            let toState = states[(index + 1) % states.count]
            return GeneratedFlowTransition(
                id: deterministicUUID(seed: "transition|\(control)|\(fromState)|\(toState)"),
                controlLabel: control,
                fromState: fromState,
                toState: toState,
                rationale: "Sequential flow inferred from control order."
            )
        }
    }

    static func inferredScreens(
        manifest: StudioViewModel.BuildManifest,
        states: [String],
        capabilities: [String]
    ) -> [GeneratedAppScreen] {
        let defaultCapabilities = capabilities.isEmpty ? ["Core workflow support"] : capabilities
        let stateLookup = Dictionary(uniqueKeysWithValues: manifest.inferredStates.map { ($0.id, $0.name) })
        var screens: [GeneratedAppScreen] = []
        var seenNames: Set<String> = []

        for (index, suggested) in manifest.suggestedStateArtboards.prefix(16).enumerated() {
            let suggestedName = suggested.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let mappedState = suggested.sourceStateID.flatMap { stateLookup[$0] } ?? states[index % max(1, states.count)]
            let fallbackName = mappedState.isEmpty ? "Screen \(index + 1)" : "\(mappedState) Screen"
            let name = suggestedName.isEmpty ? fallbackName : suggestedName
            guard !name.isEmpty, !seenNames.contains(name) else { continue }
            seenNames.insert(name)

            let reason = suggested.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = reason.isEmpty
                ? "Generated from \(manifest.activeArtboardName) for state \(mappedState)."
                : reason

            screens.append(
                GeneratedAppScreen(
                    id: deterministicUUID(seed: "screen|\(manifest.projectID)|\(name)|\(mappedState)|\(index)"),
                    name: name,
                    state: mappedState.isEmpty ? (states.first ?? "Default") : mappedState,
                    summary: summary,
                    capabilityHints: Array(defaultCapabilities.prefix(3))
                )
            )
        }

        if screens.isEmpty {
            for (index, state) in states.enumerated() {
                let name = "\(state) Screen"
                screens.append(
                    GeneratedAppScreen(
                        id: deterministicUUID(seed: "screen|\(manifest.projectID)|\(state)|\(index)"),
                        name: name,
                        state: state,
                        summary: "Generated from \(manifest.activeArtboardName) for state \(state).",
                        capabilityHints: Array(defaultCapabilities.prefix(3))
                    )
                )
            }
        }

        return screens
    }

    // MARK: - String Formatting Helpers

    static func markdownList(_ values: [String], fallback: String) -> String {
        let cleaned = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "- \(fallback)" }
        return cleaned.map { "- \($0)" }.joined(separator: "\n")
    }

    static func escapedSwiftString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func swiftStringArrayLiteral(_ values: [String]) -> String {
        let escaped = values.map { "\"\(escapedSwiftString($0))\"" }
        return "[\(escaped.joined(separator: ", "))]"
    }

    static func swiftStringDictionaryLiteral(_ entries: [(String, String)]) -> String {
        let pairs = entries.map { key, value in
            "\"\(escapedSwiftString(key))\": \"\(escapedSwiftString(value))\""
        }
        return "[\(pairs.joined(separator: ", "))]"
    }

    static func swiftGeneratedScreenArrayLiteral(_ screens: [GeneratedAppScreen]) -> String {
        let rows = screens.map { screen in
            let id = escapedSwiftString(screen.id.uuidString)
            let name = escapedSwiftString(screen.name)
            let state = escapedSwiftString(screen.state)
            let summary = escapedSwiftString(screen.summary)
            let capabilityHints = swiftStringArrayLiteral(screen.capabilityHints)
            return "GeneratedScreen(id: \"\(id)\", name: \"\(name)\", state: \"\(state)\", summary: \"\(summary)\", capabilityHints: \(capabilityHints))"
        }
        if rows.isEmpty {
            return "[GeneratedScreen.fallback]"
        }
        return "[\(rows.joined(separator: ", "))]"
    }

    static func escapedJSString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
    }

    static func jsStringArrayLiteral(_ values: [String]) -> String {
        let escaped = values.map { "\"\(escapedJSString($0))\"" }
        return "[\(escaped.joined(separator: ", "))]"
    }

    static func jsTransitionObjectLiteral(_ transitions: [GeneratedFlowTransition]) -> String {
        let pairs = transitions.map { transition in
            "\"\(escapedJSString(transition.controlLabel))\": \"\(escapedJSString(transition.toState))\""
        }
        return "{\(pairs.joined(separator: ", "))}"
    }

    static func jsGeneratedScreenArrayLiteral(_ screens: [GeneratedAppScreen]) -> String {
        let rows = screens.map { screen in
            let id = escapedJSString(screen.id.uuidString)
            let name = escapedJSString(screen.name)
            let state = escapedJSString(screen.state)
            let summary = escapedJSString(screen.summary)
            let capabilityHints = jsStringArrayLiteral(screen.capabilityHints)
            return "{ id: \"\(id)\", name: \"\(name)\", state: \"\(state)\", summary: \"\(summary)\", capabilityHints: \(capabilityHints) }"
        }
        if rows.isEmpty {
            return "[]"
        }
        return "[\(rows.joined(separator: ", "))]"
    }

    static func escapedHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
