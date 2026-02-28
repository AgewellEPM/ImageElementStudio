import Foundation

struct HeuristicSemanticEngine {
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
