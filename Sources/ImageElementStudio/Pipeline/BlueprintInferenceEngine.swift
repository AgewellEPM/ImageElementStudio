import Foundation

struct BlueprintInferenceEngine {
    func infer(document: AnalysisDocument) -> (document: AnalysisDocument, narrative: String) {
        var updated = document
        let elements = updated.artboard.elements.filter { $0.kind != .imageRoot }
        let controls = inferControls(from: elements)
        let states = inferStates(controls: controls, elements: elements, scope: updated.scope)
        let suggestedArtboards = inferSuggestedArtboards(from: states)
        let score = mirrorScore(elements: elements, controls: controls, states: states)
        let summary = "Mirror score \(Int((score * 100).rounded()))%. Inferred \(controls.count) controls and \(states.count) state candidates."

        updated.blueprint = BuildBlueprint(
            mirrorScore: score,
            detectionSummary: summary,
            controls: controls,
            states: states,
            suggestedArtboards: suggestedArtboards,
            buildNotes: buildNotes(
                controls: controls,
                states: states,
                appType: updated.scope?.appType
            )
        )
        updated.metadata.notes.append(summary)

        let narrative = """
        Mirror pass mapped \(controls.count) interactive controls and \(states.count) build states from this screenshot.
        """

        return (updated, narrative)
    }

    private func inferControls(from elements: [CanvasElement]) -> [InferredControl] {
        var controls: [InferredControl] = []
        var seen = Set<String>()

        for element in elements {
            guard let control = inferControl(for: element) else { continue }
            let key = "\(control.kind.rawValue)|\(normalize(control.label))"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            controls.append(control)
        }

        return controls.sorted { lhs, rhs in
            if lhs.frame?.y != rhs.frame?.y {
                return (lhs.frame?.y ?? .infinity) < (rhs.frame?.y ?? .infinity)
            }
            return lhs.label < rhs.label
        }
    }

    private func inferControl(for element: CanvasElement) -> InferredControl? {
        let content = (element.content ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalize(content)
        let role = element.semanticRole ?? .unknown

        let classification = classifyControl(role: role, normalizedText: normalized)
        guard let classification else { return nil }

        let fallbackLabel = content.isEmpty ? element.name : content
        let label = compactLabel(fallbackLabel)
        let confidenceBoost = classification.kind == .button || classification.kind == .navigation ? 0.08 : 0.04

        return InferredControl(
            id: UUID(),
            name: classification.name,
            label: label,
            kind: classification.kind,
            role: role,
            sourceElementID: element.id,
            frame: element.frame,
            confidence: min(1.0, max(0.0, element.confidence + confidenceBoost)),
            rationale: classification.rationale
        )
    }

    private func classifyControl(
        role: SemanticElementRole,
        normalizedText: String
    ) -> (kind: InferredControlKind, name: String, rationale: String)? {
        if role == .buttonPrimary || role == .buttonSecondary {
            return (.button, "Action Control", "Semantic role mapped as button.")
        }
        if role == .navigationItem || role == .navigationSection {
            return (.navigation, "Navigation Control", "Semantic role mapped as navigation.")
        }
        if role == .dateFilter {
            return (.filter, "Date Filter", "Text matched date/filter patterns.")
        }
        if role == .chart || role == .chartAxis {
            return (.chart, "Chart Control", "Chart region can drive state transitions.")
        }
        if role == .tableHeader || role == .tableCell {
            return (.table, "Table Control", "Table layout implies sorting/filtering states.")
        }
        if normalizedText.contains("search") {
            return (.input, "Search Input", "Detected search prompt in text.")
        }
        if normalizedText.contains("filter") || normalizedText.contains("date") {
            return (.filter, "Filter Control", "Detected filter/date keywords.")
        }
        if normalizedText.contains("tab") {
            return (.tab, "Tab Control", "Detected tab keyword.")
        }
        if looksLikeActionLabel(normalizedText) {
            return (.button, "Action Control", "Detected action verb in text.")
        }
        return nil
    }

    private func inferStates(
        controls: [InferredControl],
        elements: [CanvasElement],
        scope: ProductScopeSnapshot?
    ) -> [InferredState] {
        var states: [InferredState] = []

        states.append(
            InferredState(
                id: UUID(),
                name: "Default View",
                triggerControlID: nil,
                triggerLabel: "Initial Screen",
                description: scope?.summary ?? "Base layout as captured from the uploaded screenshot.",
                confidence: 0.95
            )
        )

        for control in controls.prefix(Constants.Blueprint.maxControlsForStateInference) {
            switch control.kind {
            case .navigation:
                states.append(
                    InferredState(
                        id: UUID(),
                        name: "Screen: \(titleCase(control.label))",
                        triggerControlID: control.id,
                        triggerLabel: control.label,
                        description: "Navigation route activated from '\(control.label)'.",
                        confidence: min(0.99, control.confidence)
                    )
                )
            case .filter:
                states.append(
                    InferredState(
                        id: UUID(),
                        name: "Filtered: \(titleCase(control.label))",
                        triggerControlID: control.id,
                        triggerLabel: control.label,
                        description: "Data and widgets updated under '\(control.label)' filter criteria.",
                        confidence: min(0.98, control.confidence * 0.95)
                    )
                )
            case .button:
                states.append(contentsOf: buttonStates(for: control))
            case .input:
                states.append(
                    InferredState(
                        id: UUID(),
                        name: "Search Active",
                        triggerControlID: control.id,
                        triggerLabel: control.label,
                        description: "Input field focused with query and filtered result list.",
                        confidence: min(0.96, control.confidence)
                    )
                )
            case .tab:
                states.append(
                    InferredState(
                        id: UUID(),
                        name: "Tab: \(titleCase(control.label))",
                        triggerControlID: control.id,
                        triggerLabel: control.label,
                        description: "Alternate tab content visible for '\(control.label)'.",
                        confidence: min(0.95, control.confidence * 0.92)
                    )
                )
            case .chart:
                states.append(
                    InferredState(
                        id: UUID(),
                        name: "Chart Drilldown",
                        triggerControlID: control.id,
                        triggerLabel: control.label,
                        description: "Focused chart interaction with hovered/selected data point.",
                        confidence: min(0.94, control.confidence * 0.9)
                    )
                )
            case .table:
                states.append(
                    InferredState(
                        id: UUID(),
                        name: "Table Sorted",
                        triggerControlID: control.id,
                        triggerLabel: control.label,
                        description: "Table rows sorted or filtered from header interaction.",
                        confidence: min(0.93, control.confidence * 0.88)
                    )
                )
            case .menu, .unknown:
                continue
            }
        }

        if controls.contains(where: { $0.kind == .chart || $0.kind == .table }) {
            states.append(
                InferredState(
                    id: UUID(),
                    name: "Loading State",
                    triggerControlID: nil,
                    triggerLabel: "Data Fetch",
                    description: "Skeleton/loading placeholders while dashboard data is fetched.",
                    confidence: 0.9
                )
            )
            states.append(
                InferredState(
                    id: UUID(),
                    name: "Empty State",
                    triggerControlID: nil,
                    triggerLabel: "No Data",
                    description: "No rows/charts available, with message and recovery actions.",
                    confidence: 0.88
                )
            )
        }

        let deduped = deduplicateStates(states)
        return Array(deduped.prefix(Constants.Blueprint.maxInferredStates))
    }

    private func buttonStates(for control: InferredControl) -> [InferredState] {
        let label = normalize(control.label)

        if label.contains("export") || label.contains("download") {
            return [
                InferredState(
                    id: UUID(),
                    name: "Export Flow",
                    triggerControlID: control.id,
                    triggerLabel: control.label,
                    description: "Export modal/sheet opened with output format options.",
                    confidence: min(0.98, control.confidence)
                ),
            ]
        }

        if label.contains("new") || label.contains("add") || label.contains("create") {
            return [
                InferredState(
                    id: UUID(),
                    name: "Create Form",
                    triggerControlID: control.id,
                    triggerLabel: control.label,
                    description: "Creation form/modal presented from '\(control.label)'.",
                    confidence: min(0.97, control.confidence)
                ),
                InferredState(
                    id: UUID(),
                    name: "Create Success",
                    triggerControlID: control.id,
                    triggerLabel: control.label,
                    description: "Successful create confirmation and refreshed list/cards.",
                    confidence: min(0.93, control.confidence * 0.9)
                ),
            ]
        }

        if label.contains("edit") || label.contains("update") {
            return [
                InferredState(
                    id: UUID(),
                    name: "Edit Mode",
                    triggerControlID: control.id,
                    triggerLabel: control.label,
                    description: "Editable controls enabled for selected record or section.",
                    confidence: min(0.95, control.confidence)
                ),
            ]
        }

        return [
            InferredState(
                id: UUID(),
                name: "Action: \(titleCase(control.label))",
                triggerControlID: control.id,
                triggerLabel: control.label,
                description: "Triggered by '\(control.label)' interaction.",
                confidence: min(0.92, control.confidence * 0.88)
            ),
        ]
    }

    private func inferSuggestedArtboards(from states: [InferredState]) -> [SuggestedArtboard] {
        let candidates = states.filter { $0.name != "Default View" }
        return Array(candidates.prefix(Constants.Blueprint.maxSuggestedArtboards)).map { state in
            SuggestedArtboard(
                id: UUID(),
                name: "State • \(state.name)",
                sourceStateID: state.id,
                reason: state.description,
                confidence: state.confidence
            )
        }
    }

    private func mirrorScore(
        elements: [CanvasElement],
        controls: [InferredControl],
        states: [InferredState]
    ) -> Double {
        guard !elements.isEmpty else { return 0.0 }

        let semanticCoverage = Double(elements.filter { ($0.semanticRole ?? .unknown) != .unknown }.count) / Double(elements.count)
        let controlCoverage = min(1.0, Double(controls.count) / max(1.0, Double(elements.count) * 0.35))
        let stateCoverage = min(1.0, Double(states.count) / max(4.0, Double(controls.count)))

        let weighted = (semanticCoverage * 0.52) + (controlCoverage * 0.28) + (stateCoverage * 0.2)
        return min(0.99, max(0.35, weighted))
    }

    private func buildNotes(
        controls: [InferredControl],
        states: [InferredState],
        appType: String?
    ) -> [String] {
        var notes: [String] = []
        notes.append("Mirror strategy: preserve OCR frame geometry and semantic roles from uploaded design.")
        notes.append("Detected \(controls.count) interactive controls from one screenshot.")
        notes.append("Generated \(states.count) state candidates for build scaffolding.")
        if let appType, !appType.isEmpty {
            notes.append("Current product hypothesis: \(appType).")
        }
        notes.append("Use suggested state artboards to scaffold loading/empty/action flows.")
        return notes
    }

    private func deduplicateStates(_ states: [InferredState]) -> [InferredState] {
        var seen = Set<String>()
        var output: [InferredState] = []

        for state in states {
            let key = normalize(state.name)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(state)
        }

        return output
    }

    private func looksLikeActionLabel(_ normalized: String) -> Bool {
        [
            "new", "add", "create", "save", "submit", "export", "download", "remove", "delete", "edit", "view",
            "open", "switch", "apply", "duplicate", "clear", "build",
        ]
        .contains { normalized.contains($0) }
    }

    private func compactLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > Constants.Blueprint.maxLabelLength else { return trimmed }
        return "\(trimmed.prefix(Constants.Blueprint.truncatedLabelPrefixLength))..."
    }

    private func titleCase(_ raw: String) -> String {
        let clean = raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "State" }
        return clean.prefix(1).uppercased() + clean.dropFirst()
    }

    private func normalize(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
