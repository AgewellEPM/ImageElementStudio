import Foundation
import Testing

@testable import ImageElementStudio

@Suite("HeuristicSemanticEngine Tests")
struct HeuristicSemanticEngineTests {
    private let engine = HeuristicSemanticEngine()

    // MARK: - Helpers

    private func makeDocument(
        elements: [CanvasElement],
        width: Int = 1366,
        height: Int = 900
    ) -> AnalysisDocument {
        let artboard = Artboard(
            id: UUID(),
            name: "Test Artboard",
            width: width,
            height: height,
            elements: elements
        )
        return AnalysisDocument(
            image: ImageDescriptor(filename: "test.png", width: width, height: height),
            artboard: artboard,
            metadata: AnalysisMetadata(
                generatedAt: Date(),
                engine: "Test Engine",
                notes: []
            ),
            scope: nil,
            blueprint: nil
        )
    }

    private func textElement(
        name: String = "Element",
        content: String,
        frame: ElementFrame,
        role: SemanticElementRole? = .unknown
    ) -> CanvasElement {
        CanvasElement(
            id: UUID(),
            name: name,
            kind: .text,
            frame: frame,
            confidence: 0.9,
            content: content,
            tags: ["ocr", "text-line"],
            semanticRole: role,
            semanticReason: nil
        )
    }

    private func shapeElement(
        name: String = "Shape",
        frame: ElementFrame,
        role: SemanticElementRole? = .unknown
    ) -> CanvasElement {
        CanvasElement(
            id: UUID(),
            name: name,
            kind: .shape,
            frame: frame,
            confidence: 0.85,
            content: nil,
            tags: ["vision-rectangle"],
            semanticRole: role,
            semanticReason: nil
        )
    }

    // MARK: - Tests

    @Test("Empty elements produces minimal result")
    func emptyElements() {
        let doc = makeDocument(elements: [])
        let result = engine.interpret(document: doc)

        #expect(result.source == "Local Semantic AI")
        #expect(result.document.scope != nil)
        #expect(!result.narrative.isEmpty)
    }

    @Test("Single root element classifies correctly")
    func singleRootElement() {
        let root = CanvasElement.root(width: 1366, height: 900, filename: "test.png")
        let doc = makeDocument(elements: [root])
        let result = engine.interpret(document: doc)

        let updated = result.document.artboard.elements
        #expect(updated.count == 1)
        #expect(updated[0].semanticRole == .panel)
        #expect(updated[0].name == "Canvas Root")
    }

    @Test("Button text is classified as button role")
    func buttonTextClassification() {
        let element = textElement(
            content: "Export Data",
            frame: ElementFrame(x: 500, y: 500, width: 120, height: 30)
        )
        let doc = makeDocument(elements: [element])
        let result = engine.interpret(document: doc)

        let updated = result.document.artboard.elements[0]
        #expect(updated.semanticRole == .buttonPrimary)
    }

    @Test("Save button is classified as secondary button")
    func saveButtonClassification() {
        let element = textElement(
            content: "Save",
            frame: ElementFrame(x: 500, y: 500, width: 80, height: 30)
        )
        let doc = makeDocument(elements: [element])
        let result = engine.interpret(document: doc)

        let updated = result.document.artboard.elements[0]
        #expect(updated.semanticRole == .buttonSecondary)
    }

    @Test("Date range text classified as date filter")
    func dateRangeClassification() {
        let element = textElement(
            content: "Jan 1 - Feb 28",
            frame: ElementFrame(x: 500, y: 500, width: 160, height: 24)
        )
        let doc = makeDocument(elements: [element])
        let result = engine.interpret(document: doc)

        let updated = result.document.artboard.elements[0]
        #expect(updated.semanticRole == .dateFilter)
    }

    @Test("Left-rail uppercase text classified as navigation section")
    func navigationSectionClassification() {
        // Left zone is x < 0.24 * 1366 = 327.84, top zone is y < 0.2 * 900 = 180
        // Uppercase text with <= 2 words in left rail -> navigationSection
        let element = textElement(
            content: "ANALYTICS",
            frame: ElementFrame(x: 20, y: 300, width: 180, height: 22)
        )
        let doc = makeDocument(elements: [element])
        let result = engine.interpret(document: doc)

        let updated = result.document.artboard.elements[0]
        #expect(updated.semanticRole == .navigationSection)
    }

    @Test("Left-rail regular text classified as navigation item")
    func navigationItemClassification() {
        let element = textElement(
            content: "Dashboard Overview",
            frame: ElementFrame(x: 20, y: 350, width: 180, height: 22)
        )
        let doc = makeDocument(elements: [element])
        let result = engine.interpret(document: doc)

        let updated = result.document.artboard.elements[0]
        #expect(updated.semanticRole == .navigationItem)
    }

    @Test("Top heading text classified as heading")
    func headingClassification() {
        // Top zone: centerY < 0.2 * 900 = 180, so y+height/2 < 180
        // heading-like: 2-5 words
        let element = textElement(
            content: "Welcome Dashboard View",
            frame: ElementFrame(x: 400, y: 40, width: 350, height: 34)
        )
        let doc = makeDocument(elements: [element])
        let result = engine.interpret(document: doc)

        let updated = result.document.artboard.elements[0]
        #expect(updated.semanticRole == .heading)
    }

    @Test("Numeric text classified as metric value")
    func metricValueClassification() {
        let element = textElement(
            content: "1,234",
            frame: ElementFrame(x: 500, y: 500, width: 80, height: 30)
        )
        let doc = makeDocument(elements: [element])
        let result = engine.interpret(document: doc)

        let updated = result.document.artboard.elements[0]
        #expect(updated.semanticRole == .metricValue)
    }

    @Test("Percentage delta text classified as metric delta")
    func metricDeltaClassification() {
        let element = textElement(
            content: "12% increase",
            frame: ElementFrame(x: 500, y: 500, width: 120, height: 24)
        )
        let doc = makeDocument(elements: [element])
        let result = engine.interpret(document: doc)

        let updated = result.document.artboard.elements[0]
        #expect(updated.semanticRole == .metricDelta)
    }

    @Test("Large shape in mid-content classified as chart")
    func largeShapeChartClassification() {
        // Large shape: width > 0.36 * 1366 = 491.76, height > 0.18 * 900 = 162
        // Mid-content boundary: y < 0.72 * 900 = 648
        let element = shapeElement(
            frame: ElementFrame(x: 250, y: 200, width: 600, height: 250)
        )
        let doc = makeDocument(elements: [element])
        let result = engine.interpret(document: doc)

        let updated = result.document.artboard.elements[0]
        #expect(updated.semanticRole == .chart)
    }

    @Test("Large shape in lower area classified as panel")
    func largeShapePanelClassification() {
        // Large shape below mid-content boundary (y >= 0.72 * 900 = 648)
        let element = shapeElement(
            frame: ElementFrame(x: 250, y: 650, width: 600, height: 200)
        )
        let doc = makeDocument(elements: [element])
        let result = engine.interpret(document: doc)

        let updated = result.document.artboard.elements[0]
        #expect(updated.semanticRole == .panel)
    }

    @Test("App type classification uses keyword matching")
    func appTypeClassification() {
        let elements = [
            textElement(content: "Dashboard", frame: ElementFrame(x: 400, y: 40, width: 200, height: 30)),
            textElement(content: "Employees", frame: ElementFrame(x: 400, y: 100, width: 200, height: 24)),
            textElement(content: "Attendance Report", frame: ElementFrame(x: 400, y: 140, width: 200, height: 24)),
        ]
        let doc = makeDocument(elements: elements)
        let result = engine.interpret(document: doc)

        let scope = result.document.scope
        #expect(scope != nil)
        #expect(scope?.appType == "Workforce Analytics Dashboard")
    }

    @Test("Semantic tags are added to elements")
    func semanticTagsAdded() {
        let element = textElement(
            content: "Export",
            frame: ElementFrame(x: 500, y: 500, width: 80, height: 30)
        )
        let doc = makeDocument(elements: [element])
        let result = engine.interpret(document: doc)

        let updated = result.document.artboard.elements[0]
        let hasSemanticTag = updated.tags.contains(where: { $0.hasPrefix("semantic:") })
        #expect(hasSemanticTag)
    }

    @Test("Capabilities inferred from element roles")
    func capabilitiesInference() {
        let elements = [
            textElement(
                name: "Nav Item",
                content: "Dashboard",
                frame: ElementFrame(x: 20, y: 300, width: 180, height: 22)
            ),
            textElement(
                content: "1,234",
                frame: ElementFrame(x: 500, y: 500, width: 80, height: 30)
            ),
        ]
        let doc = makeDocument(elements: elements)
        let result = engine.interpret(document: doc)

        let capabilities = result.document.scope?.keyCapabilities ?? []
        #expect(!capabilities.isEmpty)
    }

    @Test("Open questions generated when roles are missing")
    func openQuestionsGeneration() {
        // Element that will not produce dateFilter or buttonPrimary
        let element = textElement(
            content: "Overview Data Panel",
            frame: ElementFrame(x: 500, y: 500, width: 200, height: 24)
        )
        let doc = makeDocument(elements: [element])
        let result = engine.interpret(document: doc)

        let questions = result.document.scope?.openQuestions ?? []
        #expect(!questions.isEmpty)
    }

    @Test("Metadata engine string is updated after interpretation")
    func metadataEngineUpdated() {
        let doc = makeDocument(elements: [])
        let result = engine.interpret(document: doc)

        #expect(result.document.metadata.engine.contains("Local Semantic AI"))
    }

    @Test("Implementation roadmap is non-empty")
    func implementationRoadmapGenerated() {
        let doc = makeDocument(elements: [])
        let result = engine.interpret(document: doc)

        let roadmap = result.document.scope?.implementationRoadmap ?? []
        #expect(roadmap.count == 4)
    }
}
