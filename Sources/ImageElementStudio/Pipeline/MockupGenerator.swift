import Foundation

struct MockupGenerator {
    func generate(
        from plannerResult: IdeaPlannerResult,
        strategySpec: StrategySpec?,
        preset: MockupStylePreset
    ) -> MockupGenerationResult {
        let tokenSet = tokenSet(for: plannerResult.scope, strategySpec: strategySpec, preset: preset)
        let components = inferComponents(from: plannerResult.artboards)
        let componentLookup = Dictionary(uniqueKeysWithValues: components.flatMap { component in
            component.elementIDs.map { ($0, component.kind) }
        })

        let tokenizedArtboards = plannerResult.artboards.map { board in
            var updatedBoard = board
            updatedBoard.elements = board.elements.map { decorate(element: $0, componentLookup: componentLookup) }
            return updatedBoard
        }

        let notes = [
            "Applied curated design tokens for a higher-fidelity emulator pass.",
            "Mapped semantic elements into reusable component categories.",
            "Token tags are preserved on elements for downstream codegen.",
        ]

        return MockupGenerationResult(
            artboards: tokenizedArtboards,
            tokens: tokenSet,
            components: components,
            notes: notes
        )
    }

    func restyle(
        artboards: [Artboard],
        scope: ProductScopeSnapshot,
        strategySpec: StrategySpec?,
        preset: MockupStylePreset
    ) -> MockupGenerationResult {
        let tokenSet = tokenSet(for: scope, strategySpec: strategySpec, preset: preset)
        let components = inferComponents(from: artboards)
        let componentLookup = Dictionary(uniqueKeysWithValues: components.flatMap { component in
            component.elementIDs.map { ($0, component.kind) }
        })

        let styled = artboards.map { board in
            var updated = board
            updated.elements = board.elements.map { decorate(element: $0, componentLookup: componentLookup) }
            return updated
        }

        return MockupGenerationResult(
            artboards: styled,
            tokens: tokenSet,
            components: components,
            notes: ["Restyled existing mockups with \(preset.title) preset."]
        )
    }

    func defaultTokenSet(
        scope: ProductScopeSnapshot,
        strategySpec: StrategySpec?,
        preset: MockupStylePreset
    ) -> DesignTokenSet {
        tokenSet(for: scope, strategySpec: strategySpec, preset: preset)
    }

    private func decorate(element: CanvasElement, componentLookup: [UUID: ComponentKind]) -> CanvasElement {
        var updated = element
        var tags = Set(updated.tags)

        if let component = componentLookup[updated.id] {
            tags.insert("component:\(component.rawValue)")
        }

        for token in tokenTags(for: updated.semanticRole ?? .unknown, kind: updated.kind) {
            tags.insert("token:\(token)")
        }

        updated.tags = tags.sorted()
        return updated
    }

    private func tokenTags(for role: SemanticElementRole, kind: ElementKind) -> [String] {
        switch role {
        case .buttonPrimary:
            return ["color.accent.primary", "text.inverse", "radius.control", "shadow.focus"]
        case .buttonSecondary:
            return ["color.surface.elevated", "text.primary", "radius.control", "stroke.default"]
        case .navigationItem:
            return ["color.surface.nav", "text.secondary", "radius.control"]
        case .heading:
            return ["typography.title", "text.primary"]
        case .sectionTitle:
            return ["typography.section", "text.primary"]
        case .metricValue:
            return ["typography.metric", "text.primary"]
        case .metricLabel:
            return ["typography.caption", "text.secondary"]
        case .panel:
            return ["color.surface.panel", "stroke.soft", "radius.panel"]
        case .chart:
            return ["color.chart.gradient", "radius.panel"]
        case .tableHeader:
            return ["color.surface.elevated", "typography.caption", "text.secondary"]
        case .tableCell:
            return ["color.surface.base", "text.primary", "stroke.soft"]
        case .listItem:
            return ["color.surface.base", "stroke.soft", "radius.control"]
        default:
            if kind == .shape {
                return ["color.surface.base", "stroke.soft"]
            }
            return ["text.primary"]
        }
    }

    private func inferComponents(from artboards: [Artboard]) -> [ComponentSpec] {
        var grouped: [ComponentKind: [CanvasElement]] = [:]

        for board in artboards {
            for element in board.elements where element.kind != .imageRoot {
                let kind = componentKind(for: element)
                grouped[kind, default: []].append(element)
            }
        }

        let orderedKinds: [ComponentKind] = [.nav, .cta, .card, .panel, .chart, .table, .list, .form]
        return orderedKinds.compactMap { kind in
            guard let elements = grouped[kind], !elements.isEmpty else { return nil }
            return ComponentSpec(
                id: UUID(),
                name: displayName(for: kind),
                kind: kind,
                role: elements.first?.semanticRole,
                elementIDs: elements.map(\.id),
                notes: "Inferred from \(elements.count) semantic elements.",
                variantAxes: ["state": inferredStateOptions(for: kind)],
                stateMappings: ["default": "Base"],
                tokenBindings: tokenBindings(for: kind),
                instanceElementIDs: elements.map(\.id),
                version: 1
            )
        }
    }

    private func componentKind(for element: CanvasElement) -> ComponentKind {
        switch element.semanticRole ?? .unknown {
        case .navigationItem, .navigationSection:
            return .nav
        case .buttonPrimary, .buttonSecondary, .dateFilter:
            return .cta
        case .chart, .chartAxis:
            return .chart
        case .tableHeader, .tableCell:
            return .table
        case .listItem:
            return .list
        case .panel:
            return .panel
        case .metricValue, .metricLabel, .metricDelta:
            return .card
        default:
            return element.kind == .shape ? .panel : .card
        }
    }

    private func displayName(for kind: ComponentKind) -> String {
        switch kind {
        case .nav:
            return "Navigation"
        case .card:
            return "Info Cards"
        case .table:
            return "Tables"
        case .form:
            return "Forms"
        case .cta:
            return "Calls To Action"
        case .chart:
            return "Charts"
        case .list:
            return "List Rows"
        case .panel:
            return "Panels"
        }
    }

    private func inferredStateOptions(for kind: ComponentKind) -> [String] {
        switch kind {
        case .cta:
            return ["default", "hover", "pressed", "disabled"]
        case .form:
            return ["default", "focus", "error", "disabled"]
        case .table, .list:
            return ["default", "selected", "empty"]
        default:
            return ["default", "active"]
        }
    }

    private func tokenBindings(for kind: ComponentKind) -> [String: String] {
        switch kind {
        case .cta:
            return [
                "fill": "accent.primary",
                "text": "text.inverse",
                "radius": "radius.control",
            ]
        case .nav:
            return [
                "fill": "surface.nav",
                "text": "text.secondary",
            ]
        case .panel:
            return [
                "fill": "surface.panel",
                "stroke": "stroke.soft",
                "radius": "radius.panel",
            ]
        default:
            return [
                "fill": "surface.base",
                "text": "text.primary",
            ]
        }
    }

    private func tokenSet(
        for scope: ProductScopeSnapshot,
        strategySpec: StrategySpec?,
        preset: MockupStylePreset
    ) -> DesignTokenSet {
        let hint = "\(scope.appType) \(strategySpec?.vision ?? "")".lowercased()
        let accentPair: (primary: String, secondary: String, soft: String)

        if hint.contains("commerce") || hint.contains("checkout") || hint.contains("shop") {
            accentPair = ("#2B6EF2", "#0C4EC4", "#DCE8FF")
        } else if hint.contains("analytics") || hint.contains("dashboard") || hint.contains("kpi") {
            accentPair = ("#0A7B7C", "#065C5D", "#D9F4F2")
        } else if hint.contains("social") || hint.contains("community") {
            accentPair = ("#C03E65", "#8A2948", "#F8DFE8")
        } else {
            accentPair = ("#3B5CFF", "#2741CF", "#E2E8FF")
        }

        let typography: [String: String]
        let radius: [String: Double]
        let shadow: [String: Double]
        let motion: [String: Double]

        switch preset {
        case .apple_hig:
            typography = [
                "title": "SF Pro Rounded / semibold / 20",
                "section": "SF Pro Text / semibold / 15",
                "body": "SF Pro Text / medium / 13",
                "caption": "SF Pro Text / medium / 11",
                "metric": "SF Pro Display / bold / 24",
            ]
            radius = [
                "control": 10,
                "panel": 14,
                "chip": 8,
            ]
            shadow = [
                "cardBlur": 16,
                "cardY": 6,
                "focusBlur": 12,
            ]
            motion = [
                "fast": 0.12,
                "normal": 0.22,
            ]
        case .adobe_expressive:
            typography = [
                "title": "Neue Haas Grotesk / bold / 24",
                "section": "Acumin Pro / semibold / 16",
                "body": "Acumin Pro / medium / 13",
                "caption": "Acumin Pro / semibold / 11",
                "metric": "Neue Haas Grotesk / bold / 28",
            ]
            radius = [
                "control": 14,
                "panel": 18,
                "chip": 10,
            ]
            shadow = [
                "cardBlur": 24,
                "cardY": 10,
                "focusBlur": 16,
            ]
            motion = [
                "fast": 0.1,
                "normal": 0.2,
            ]
        }

        return DesignTokenSet(
            colors: [
                "canvas.bg": "#F4F6FA",
                "surface.base": "#FFFFFF",
                "surface.elevated": "#F8FAFF",
                "surface.panel": "#EEF2F8",
                "surface.nav": "#E9EEF8",
                "text.primary": "#151A24",
                "text.secondary": "#556176",
                "text.inverse": "#FFFFFF",
                "stroke.default": "#CDD6E4",
                "stroke.soft": "#E4EAF3",
                "accent.primary": accentPair.primary,
                "accent.secondary": accentPair.secondary,
                "accent.soft": accentPair.soft,
            ],
            typography: typography,
            spacing: [
                "xs": 4,
                "sm": 8,
                "md": 12,
                "lg": 18,
                "xl": 24,
                "grid": 8,
            ],
            radius: radius,
            shadow: shadow,
            motion: motion
        )
    }
}
