import AppKit
import Foundation

struct SemanticPipelineResult {
    var document: AnalysisDocument
    var narrative: String
    var source: String
}

struct SemanticPipeline {
    private let heuristicEngine = HeuristicSemanticEngine()
    private let blueprintEngine = BlueprintInferenceEngine()
    private let remoteEngine: OpenAISemanticEngine?

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let keyFromEnv = environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyFromDefaults = UserDefaults.standard.string(forKey: "OPENAI_API_KEY")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = [keyFromEnv, keyFromDefaults]
            .compactMap { $0 }
            .first { !$0.isEmpty }

        if let apiKey {
            remoteEngine = OpenAISemanticEngine(apiKey: apiKey)
        } else {
            remoteEngine = nil
        }
    }

    func enrich(document: AnalysisDocument, imageData: Data?) async -> SemanticPipelineResult {
        let heuristicResult = heuristicEngine.interpret(document: document)
        var selectedResult = heuristicResult

        if let remoteEngine, let imageData {
            do {
                selectedResult = try await remoteEngine.interpret(document: heuristicResult.document, imageData: imageData)
            } catch {
                selectedResult.document.metadata.notes.append(
                    "Remote AI enrichment failed: \(error.localizedDescription). Using local semantic inference."
                )
            }
        }

        let blueprintResult = blueprintEngine.infer(document: selectedResult.document)
        let narrativeParts = [selectedResult.narrative, blueprintResult.narrative]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let narrative = narrativeParts.joined(separator: " ")

        return SemanticPipelineResult(
            document: blueprintResult.document,
            narrative: narrative,
            source: selectedResult.source
        )
    }
}

private struct HeuristicSemanticEngine {
    func interpret(document: AnalysisDocument) -> SemanticPipelineResult {
        var updated = document
        var elements = updated.artboard.elements
        let board = updated.artboard

        let corpus = elements
            .compactMap(\.content)
            .joined(separator: " ")
            .lowercased()

        let appType = classifyAppType(from: corpus)

        for index in elements.indices {
            var element = elements[index]
            let inference = inferSemanticElement(
                element: element,
                index: index,
                board: board
            )

            element.semanticRole = inference.role
            element.semanticReason = inference.reason
            element.name = inference.name
            element.tags = withSemanticTag(existing: element.tags, role: inference.role)

            elements[index] = element
        }

        let capabilities = inferCapabilities(from: elements)
        let scope = ProductScopeSnapshot(
            appType: appType.type,
            confidence: appType.confidence,
            productIntent: appType.intent,
            targetUsers: appType.targetUsers,
            keyCapabilities: capabilities,
            openQuestions: inferOpenQuestions(elements: elements, appType: appType.type),
            implementationRoadmap: defaultRoadmap(for: appType.type),
            summary: "Detected a \(appType.type) with \(capabilities.count) likely product capabilities."
        )

        updated.artboard.elements = elements
        updated.scope = scope
        updated.metadata.engine = "\(updated.metadata.engine) + Local Semantic AI"
        updated.metadata.notes.append("Semantic pass inferred app type: \(scope.appType)")

        let narrative = """
        AI interpretation: this looks like a \(scope.appType). \
        Intent: \(scope.productIntent) \
        Key scope: \(capabilities.prefix(3).joined(separator: ", ")).
        """

        return SemanticPipelineResult(
            document: updated,
            narrative: narrative,
            source: "Local Semantic AI"
        )
    }

    private func inferSemanticElement(
        element: CanvasElement,
        index: Int,
        board: Artboard
    ) -> (role: SemanticElementRole, name: String, reason: String) {
        guard element.kind != .imageRoot else {
            return (.panel, "Canvas Root", "Root container")
        }

        let text = (element.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = text.lowercased()
        let centerY = element.frame.y + element.frame.height / 2
        let leftZone = element.frame.x < Double(board.width) * 0.24
        let topZone = centerY < Double(board.height) * 0.2

        if element.kind == .text {
            if isDateRange(normalized) {
                return (.dateFilter, label("Date Filter", text, index), "Text matched date-range pattern")
            }

            if isButtonText(normalized) {
                let role: SemanticElementRole = normalized.contains("export") ? .buttonPrimary : .buttonSecondary
                return (role, label("Button", text, index), "Text looked like a CTA")
            }

            if leftZone, !text.isEmpty {
                if isSectionHeading(text) {
                    return (.navigationSection, label("Nav Section", text, index), "Left rail uppercase heading")
                }
                return (.navigationItem, label("Nav Item", text, index), "Left rail menu candidate")
            }

            if topZone, isHeadingLike(text) {
                return (.heading, label("Page Heading", text, index), "Prominent top heading candidate")
            }

            if looksLikeMetricValue(normalized) {
                return (.metricValue, label("Metric Value", text, index), "Numeric KPI-style text")
            }

            if looksLikeMetricDelta(normalized) {
                return (.metricDelta, label("Metric Delta", text, index), "Percentage and trend-style text")
            }

            if isLikelyTableHeader(text, board: board, frame: element.frame) {
                return (.tableHeader, label("Table Header", text, index), "Lower panel header-like text")
            }

            if isLikelySectionTitle(text) {
                return (.sectionTitle, label("Section", text, index), "Medium heading in content panel")
            }

            return (.metricLabel, label("Label", text, index), "General text label")
        }

        if element.kind == .shape {
            if element.frame.width > Double(board.width) * 0.36, element.frame.height > Double(board.height) * 0.18 {
                if element.frame.y < Double(board.height) * 0.72 {
                    return (.chart, "Chart Panel \(index + 1)", "Large mid-content panel")
                }
                return (.panel, "Content Panel \(index + 1)", "Large lower panel container")
            }
            return (.panel, "Panel \(index + 1)", "Generic shape container")
        }

        return (.unknown, "Element \(index + 1)", "Fallback mapping")
    }

    private func classifyAppType(from corpus: String) -> (type: String, confidence: Double, intent: String, targetUsers: [String]) {
        let candidates: [(type: String, keywords: [String], intent: String, users: [String])] = [
            (
                type: "Workforce Analytics Dashboard",
                keywords: ["dashboard", "employees", "attendance", "project", "report", "calendar", "performance"],
                intent: "Track people metrics and operational performance from one control center.",
                users: ["HR teams", "Operations managers", "Executives"]
            ),
            (
                type: "Financial Analytics Dashboard",
                keywords: ["revenue", "profit", "expenses", "balance", "forecast", "invoice"],
                intent: "Monitor financial health and trends with KPI-first reporting.",
                users: ["Finance teams", "Founders", "Analysts"]
            ),
            (
                type: "E-commerce Admin Panel",
                keywords: ["orders", "products", "inventory", "checkout", "customers", "shipping"],
                intent: "Manage store operations and sales workflows.",
                users: ["Store operators", "Merchandisers", "Support teams"]
            ),
            (
                type: "Project Management Workspace",
                keywords: ["tasks", "sprint", "backlog", "kanban", "milestone", "roadmap"],
                intent: "Coordinate team execution and project delivery.",
                users: ["Product managers", "Engineering leads", "Cross-functional teams"]
            ),
        ]

        var best = candidates[0]
        var bestScore = -1

        for candidate in candidates {
            let score = candidate.keywords.reduce(into: 0) { partialResult, keyword in
                if corpus.contains(keyword) {
                    partialResult += 1
                }
            }
            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }

        let normalizedScore = max(0, bestScore)
        let confidence = min(0.97, 0.42 + (Double(normalizedScore) * 0.09))

        return (
            type: best.type,
            confidence: confidence,
            intent: best.intent,
            targetUsers: best.users
        )
    }

    private func inferCapabilities(from elements: [CanvasElement]) -> [String] {
        var capabilities: [String] = []

        let roles = elements.compactMap(\.semanticRole)

        if roles.contains(.navigationItem) {
            capabilities.append("Multi-section sidebar navigation")
        }
        if roles.contains(.metricValue) {
            capabilities.append("KPI cards with numeric performance indicators")
        }
        if roles.contains(.metricDelta) {
            capabilities.append("Trend indicators for month-over-month movement")
        }
        if roles.contains(.chart) {
            capabilities.append("Time-series charting or visualization panel")
        }
        if roles.contains(.tableHeader) || roles.contains(.tableCell) {
            capabilities.append("Tabular reporting section")
        }
        if roles.contains(.dateFilter) {
            capabilities.append("Date range filtering")
        }
        if roles.contains(.buttonPrimary) {
            capabilities.append("Primary call-to-action workflow")
        }

        if capabilities.isEmpty {
            capabilities.append("Visual analytics layout with structured sections")
        }

        return capabilities
    }

    private func inferOpenQuestions(elements: [CanvasElement], appType: String) -> [String] {
        var questions: [String] = []
        let roles = elements.compactMap(\.semanticRole)

        if !roles.contains(.dateFilter) {
            questions.append("Should the product include a global time/date filter?")
        }
        if !roles.contains(.buttonPrimary) {
            questions.append("What is the main primary action users should take?")
        }
        if roles.contains(.chart), !roles.contains(.tableHeader) {
            questions.append("Do we need drill-down tables behind each chart?")
        }

        questions.append("What data sources should power this \(appType.lowercased())?")
        return Array(questions.prefix(4))
    }

    private func defaultRoadmap(for appType: String) -> [String] {
        [
            "Define canonical data model for \(appType.lowercased()) entities.",
            "Build reusable UI components: nav, KPI cards, charts, and tables.",
            "Connect live API data and map it into typed view models.",
            "Generate production-ready code scaffolding from semantic layout JSON.",
        ]
    }

    private func label(_ prefix: String, _ text: String, _ index: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "\(prefix) \(index + 1)"
        }
        return trimmed
    }

    private func withSemanticTag(existing: [String], role: SemanticElementRole) -> [String] {
        var set = Set(existing)
        set.insert("semantic:\(role.rawValue)")
        return set.sorted()
    }

    private func isDateRange(_ value: String) -> Bool {
        value.contains(" - ")
            || value.contains(" to ")
            || value.contains("jan")
            || value.contains("feb")
            || value.contains("mar")
            || value.contains("apr")
            || value.contains("may")
            || value.contains("jun")
            || value.contains("jul")
            || value.contains("aug")
            || value.contains("sep")
            || value.contains("oct")
            || value.contains("nov")
            || value.contains("dec")
    }

    private func isButtonText(_ value: String) -> Bool {
        ["export", "save", "create", "add", "apply", "submit", "download", "new"]
            .contains { value.contains($0) }
    }

    private func looksLikeMetricValue(_ value: String) -> Bool {
        let stripped = value.replacingOccurrences(of: ",", with: "")
        let hasNumber = stripped.contains { $0.isNumber }
        let limitedLength = stripped.count <= 8
        return hasNumber && limitedLength
    }

    private func looksLikeMetricDelta(_ value: String) -> Bool {
        value.contains("%")
            && (value.contains("increase") || value.contains("decrease") || value.contains("up") || value.contains("down"))
    }

    private func isHeadingLike(_ value: String) -> Bool {
        let words = value.split(separator: " ")
        return words.count >= 2 && words.count <= 5
    }

    private func isLikelySectionTitle(_ value: String) -> Bool {
        let words = value.split(separator: " ")
        return words.count >= 2 && words.count <= 4 && !value.contains("%")
    }

    private func isSectionHeading(_ value: String) -> Bool {
        let words = value.split(separator: " ")
        return words.count <= 2 && value.uppercased() == value && words.count > 0
    }

    private func isLikelyTableHeader(_ value: String, board: Artboard, frame: ElementFrame) -> Bool {
        let lower = value.lowercased()
        let match = ["name", "department", "days", "start", "status", "email"].contains { lower == $0 }
        return match && frame.y > Double(board.height) * 0.45
    }
}

private struct BlueprintInferenceEngine {
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

        for control in controls.prefix(18) {
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
        return Array(deduped.prefix(20))
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
        return Array(candidates.prefix(10)).map { state in
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
        guard trimmed.count > 50 else { return trimmed }
        return "\(trimmed.prefix(47))..."
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

private struct OpenAISemanticEngine {
    let apiKey: String
    let model: String = "gpt-4.1-mini"

    func interpret(document: AnalysisDocument, imageData: Data) async throws -> SemanticPipelineResult {
        let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
        let serializedElements = serializeElements(document.artboard.elements)
        let base64Image = imageData.base64EncodedString()

        let systemPrompt = """
        You are an AI UI analyst. Infer app type, product scope, and semantic roles for elements.
        Return strict JSON only with keys:
        appType, confidence, productIntent, targetUsers, keyCapabilities, openQuestions, implementationRoadmap, summary, elementMappings.
        elementMappings is an array of objects with: index, name, role, reason, confidence.
        role must be one of:
        unknown, appBrand, navigationItem, navigationSection, heading, sectionTitle, metricValue, metricLabel, metricDelta, chart, chartAxis, tableHeader, tableCell, buttonPrimary, buttonSecondary, dateFilter, avatar, tag, panel, listItem.
        """

        let userPrompt = """
        Infer semantics from this UI screenshot and OCR/layout extraction.
        Elements (index aligned): \(serializedElements)
        """

        let payload: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "response_format": ["type": "json_object"],
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt,
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": userPrompt,
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)",
                            ],
                        ],
                    ],
                ],
            ],
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SemanticPipelineError.invalidResponse("Missing HTTP response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SemanticPipelineError.invalidResponse("Status \(httpResponse.statusCode): \(body)")
        }

        guard let content = try extractMessageContent(from: data) else {
            throw SemanticPipelineError.invalidResponse("No assistant content found")
        }

        let decoded = try JSONDecoder().decode(RemoteSemanticPayload.self, from: Data(content.utf8))
        let result = applyRemotePayload(decoded, onto: document)

        return result
    }

    private func applyRemotePayload(_ payload: RemoteSemanticPayload, onto document: AnalysisDocument) -> SemanticPipelineResult {
        var updated = document
        var elements = updated.artboard.elements

        for mapping in payload.elementMappings {
            guard elements.indices.contains(mapping.index) else { continue }

            var element = elements[mapping.index]
            let role = SemanticElementRole(rawValue: mapping.role) ?? element.semanticRole ?? .unknown

            element.semanticRole = role
            element.semanticReason = mapping.reason
            if !mapping.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                element.name = mapping.name
            }

            if let mappingConfidence = mapping.confidence {
                element.confidence = max(element.confidence, min(1.0, max(0.0, mappingConfidence)))
            }

            var tags = Set(element.tags)
            tags.insert("semantic:\(role.rawValue)")
            element.tags = tags.sorted()

            elements[mapping.index] = element
        }

        updated.artboard.elements = elements
        updated.scope = ProductScopeSnapshot(
            appType: payload.appType,
            confidence: min(1.0, max(0.0, payload.confidence)),
            productIntent: payload.productIntent,
            targetUsers: normalized(payload.targetUsers),
            keyCapabilities: normalized(payload.keyCapabilities),
            openQuestions: normalized(payload.openQuestions),
            implementationRoadmap: normalized(payload.implementationRoadmap),
            summary: payload.summary
        )
        updated.metadata.engine = "\(updated.metadata.engine) + OpenAI Semantic Vision"
        updated.metadata.notes.append("Remote multimodal semantic analysis applied.")

        return SemanticPipelineResult(
            document: updated,
            narrative: payload.summary,
            source: "OpenAI Semantic Vision"
        )
    }

    private func normalized(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func serializeElements(_ elements: [CanvasElement]) -> String {
        let formatted = elements.enumerated().prefix(140).map { index, element in
            let text = (element.content ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .prefix(90)
            return """
            {
              "index": \(index),
              "kind": "\(element.kind.rawValue)",
              "name": "\(escape(element.name))",
              "text": "\(escape(String(text)))",
              "frame": {"x": \(Int(element.frame.x)), "y": \(Int(element.frame.y)), "w": \(Int(element.frame.width)), "h": \(Int(element.frame.height))}
            }
            """
        }
        return "[\(formatted.joined(separator: ","))]"
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func extractMessageContent(from data: Data) throws -> String? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            return nil
        }

        if let content = message["content"] as? String {
            return content
        }

        if let parts = message["content"] as? [[String: Any]] {
            let texts = parts.compactMap { $0["text"] as? String }
            return texts.joined(separator: "\n")
        }

        return nil
    }
}

private struct RemoteSemanticPayload: Codable {
    var appType: String
    var confidence: Double
    var productIntent: String
    var targetUsers: [String]
    var keyCapabilities: [String]
    var openQuestions: [String]
    var implementationRoadmap: [String]
    var summary: String
    var elementMappings: [RemoteElementMapping]
}

private struct RemoteElementMapping: Codable {
    var index: Int
    var name: String
    var role: String
    var reason: String?
    var confidence: Double?
}

enum SemanticPipelineError: LocalizedError {
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case let .invalidResponse(message):
            return message
        }
    }
}

extension NSImage {
    func jpegData(maxDimension: CGFloat = 1400, compression: CGFloat = 0.78) -> Data? {
        guard let cgImage = resolvedCGImage else { return nil }

        let sourceSize = CGSize(width: cgImage.width, height: cgImage.height)
        let maxSourceDimension = max(sourceSize.width, sourceSize.height)
        let ratio = maxSourceDimension > maxDimension ? (maxDimension / maxSourceDimension) : 1.0

        let resizedSize = CGSize(
            width: max(1, floor(sourceSize.width * ratio)),
            height: max(1, floor(sourceSize.height * ratio))
        )

        let scaledImage = NSImage(size: resizedSize)
        scaledImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: cgImage, size: sourceSize)
            .draw(in: CGRect(origin: .zero, size: resizedSize))
        scaledImage.unlockFocus()

        guard let tiffData = scaledImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: compression]
        )
    }
}
