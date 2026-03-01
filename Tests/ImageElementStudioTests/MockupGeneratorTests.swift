import Foundation
import Testing

@testable import ImageElementStudio

@Suite("MockupGenerator Tests")
struct MockupGeneratorTests {
    private let generator = MockupGenerator()

    // MARK: - Helpers

    private func makeScope(appType: String = "Business Analytics Dashboard") -> ProductScopeSnapshot {
        ProductScopeSnapshot(
            appType: appType,
            confidence: 0.85,
            productIntent: "Track analytics and metrics",
            targetUsers: ["Analysts", "Executives"],
            keyCapabilities: ["KPI cards", "Charts"],
            openQuestions: [],
            implementationRoadmap: ["Plan", "Build", "Ship"],
            summary: "Analytics dashboard"
        )
    }

    private func makePlannerResult(
        scope: ProductScopeSnapshot? = nil,
        artboards: [Artboard]? = nil
    ) -> IdeaPlannerResult {
        let resolvedScope = scope ?? makeScope()
        let resolvedArtboards = artboards ?? [
            Artboard.empty(named: "Dashboard", width: 1366, height: 900),
        ]

        return IdeaPlannerResult(
            scope: resolvedScope,
            blueprint: BuildBlueprint(
                mirrorScore: 0.78,
                detectionSummary: "Test",
                controls: [],
                states: [],
                suggestedArtboards: [],
                buildNotes: []
            ),
            artboards: resolvedArtboards,
            narrative: "Test narrative"
        )
    }

    private func elementWithRole(_ role: SemanticElementRole, kind: ElementKind = .text) -> CanvasElement {
        CanvasElement(
            id: UUID(),
            name: "Test Element",
            kind: kind,
            frame: ElementFrame(x: 100, y: 100, width: 200, height: 40),
            confidence: 0.9,
            content: role == .buttonPrimary ? "Create" : "Label",
            tags: ["test"],
            semanticRole: role,
            semanticReason: "Test"
        )
    }

    // MARK: - Tests

    @Test("Generate produces artboards matching input count")
    func generateProducesCorrectArtboardCount() {
        let plannerResult = makePlannerResult()
        let result = generator.generate(from: plannerResult, strategySpec: nil, preset: .apple_hig)

        #expect(result.artboards.count == plannerResult.artboards.count)
    }

    @Test("Generate produces non-empty token set")
    func generateProducesTokenSet() {
        let plannerResult = makePlannerResult()
        let result = generator.generate(from: plannerResult, strategySpec: nil, preset: .apple_hig)

        #expect(!result.tokens.colors.isEmpty)
        #expect(!result.tokens.typography.isEmpty)
        #expect(!result.tokens.spacing.isEmpty)
        #expect(!result.tokens.radius.isEmpty)
    }

    @Test("Apple HIG preset produces correct typography font family")
    func appleHIGPreset() {
        let result = generator.defaultTokenSet(
            scope: makeScope(),
            strategySpec: nil,
            preset: .apple_hig
        )

        #expect(result.typography["title"]?.contains("SF Pro") == true)
        #expect(result.radius["control"] == 10)
    }

    @Test("Adobe Expressive preset produces correct typography")
    func adobeExpressivePreset() {
        let result = generator.defaultTokenSet(
            scope: makeScope(),
            strategySpec: nil,
            preset: .adobe_expressive
        )

        #expect(result.typography["title"]?.contains("Neue Haas") == true)
        #expect(result.radius["control"] == 14)
    }

    @Test("Analytics hint produces teal accent color")
    func analyticsAccentColor() {
        let scope = makeScope(appType: "Analytics Dashboard")
        let result = generator.defaultTokenSet(scope: scope, strategySpec: nil, preset: .apple_hig)

        #expect(result.colors["accent.primary"] == "#0A7B7C")
    }

    @Test("E-commerce hint produces blue accent color")
    func ecommerceAccentColor() {
        let scope = makeScope(appType: "E-commerce Platform")
        let result = generator.defaultTokenSet(scope: scope, strategySpec: nil, preset: .apple_hig)

        #expect(result.colors["accent.primary"] == "#2B6EF2")
    }

    @Test("Social hint produces pink accent color")
    func socialAccentColor() {
        let scope = makeScope(appType: "Social Community App")
        let result = generator.defaultTokenSet(scope: scope, strategySpec: nil, preset: .apple_hig)

        #expect(result.colors["accent.primary"] == "#C03E65")
    }

    @Test("Component specs are inferred from artboard elements")
    func componentSpecInference() {
        let elements = [
            CanvasElement.root(width: 1366, height: 900, filename: "test.png"),
            elementWithRole(.navigationItem),
            elementWithRole(.buttonPrimary),
            elementWithRole(.metricValue),
        ]
        let artboard = Artboard(id: UUID(), name: "Test", width: 1366, height: 900, elements: elements)
        let plannerResult = makePlannerResult(artboards: [artboard])

        let result = generator.generate(from: plannerResult, strategySpec: nil, preset: .apple_hig)

        #expect(!result.components.isEmpty)
        let kinds = result.components.map(\.kind)
        #expect(kinds.contains(.nav))
        #expect(kinds.contains(.cta))
        #expect(kinds.contains(.card))
    }

    @Test("Token tags added to decorated elements")
    func tokenTagsAdded() {
        let elements = [
            CanvasElement.root(width: 1366, height: 900, filename: "test.png"),
            elementWithRole(.buttonPrimary),
        ]
        let artboard = Artboard(id: UUID(), name: "Test", width: 1366, height: 900, elements: elements)
        let plannerResult = makePlannerResult(artboards: [artboard])

        let result = generator.generate(from: plannerResult, strategySpec: nil, preset: .apple_hig)

        let buttonElement = result.artboards[0].elements.first(where: {
            $0.semanticRole == .buttonPrimary
        })
        let tokenTags = buttonElement?.tags.filter { $0.hasPrefix("token:") } ?? []
        #expect(!tokenTags.isEmpty)
        #expect(tokenTags.contains("token:color.accent.primary"))
    }

    @Test("Restyle preserves artboard structure")
    func restylePreservesStructure() {
        let elements = [
            CanvasElement.root(width: 1366, height: 900, filename: "test.png"),
            elementWithRole(.heading),
        ]
        let artboard = Artboard(id: UUID(), name: "Main", width: 1366, height: 900, elements: elements)

        let result = generator.restyle(
            artboards: [artboard],
            scope: makeScope(),
            strategySpec: nil,
            preset: .adobe_expressive
        )

        #expect(result.artboards.count == 1)
        #expect(result.artboards[0].name == "Main")
        #expect(result.artboards[0].elements.count == 2)
        #expect(result.notes.first?.contains("Adobe Expressive") == true)
    }

    @Test("Notes are generated for mockup output")
    func notesGenerated() {
        let plannerResult = makePlannerResult()
        let result = generator.generate(from: plannerResult, strategySpec: nil, preset: .apple_hig)

        #expect(!result.notes.isEmpty)
        #expect(result.notes.contains(where: { $0.contains("design tokens") }))
    }

    @Test("Component variant axes match expected shapes")
    func componentVariantAxes() {
        let elements = [
            CanvasElement.root(width: 1366, height: 900, filename: "test.png"),
            elementWithRole(.buttonPrimary),
        ]
        let artboard = Artboard(id: UUID(), name: "Test", width: 1366, height: 900, elements: elements)
        let plannerResult = makePlannerResult(artboards: [artboard])

        let result = generator.generate(from: plannerResult, strategySpec: nil, preset: .apple_hig)

        let ctaComponent = result.components.first(where: { $0.kind == .cta })
        let stateVariants = ctaComponent?.variantAxes?["state"] ?? []
        #expect(stateVariants.contains("default"))
        #expect(stateVariants.contains("hover"))
        #expect(stateVariants.contains("pressed"))
        #expect(stateVariants.contains("disabled"))
    }
}
