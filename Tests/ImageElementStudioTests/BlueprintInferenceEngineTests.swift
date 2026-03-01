import Foundation
import Testing

@testable import ImageElementStudio

@Suite("BlueprintInferenceEngine Tests")
struct BlueprintInferenceEngineTests {
    private let engine = BlueprintInferenceEngine()

    // MARK: - Helpers

    private func makeDocument(
        elements: [CanvasElement],
        scope: ProductScopeSnapshot? = nil,
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
            scope: scope,
            blueprint: nil
        )
    }

    private func textElement(
        content: String,
        frame: ElementFrame = ElementFrame(x: 100, y: 100, width: 120, height: 24),
        role: SemanticElementRole = .unknown
    ) -> CanvasElement {
        CanvasElement(
            id: UUID(),
            name: content,
            kind: .text,
            frame: frame,
            confidence: 0.9,
            content: content,
            tags: ["ocr"],
            semanticRole: role,
            semanticReason: "Test"
        )
    }

    private func shapeElement(
        name: String = "Shape",
        frame: ElementFrame = ElementFrame(x: 100, y: 100, width: 200, height: 100),
        role: SemanticElementRole = .unknown
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
            semanticReason: "Test"
        )
    }

    // MARK: - Tests

    @Test("Empty elements produces default view state only")
    func emptyElements() {
        let doc = makeDocument(elements: [])
        let (updated, narrative) = engine.infer(document: doc)

        #expect(updated.blueprint != nil)
        #expect(updated.blueprint?.controls.isEmpty == true)
        // Should have at least the Default View state
        #expect(updated.blueprint?.states.count == 1)
        #expect(updated.blueprint?.states.first?.name == "Default View")
        #expect(!narrative.isEmpty)
    }

    @Test("Button role generates button control")
    func buttonRoleGeneratesControl() {
        let element = textElement(content: "Export Data", role: .buttonPrimary)
        let doc = makeDocument(elements: [element])
        let (updated, _) = engine.infer(document: doc)

        let controls = updated.blueprint?.controls ?? []
        #expect(controls.count == 1)
        #expect(controls[0].kind == .button)
        #expect(controls[0].name == "Action Control")
    }

    @Test("Navigation role generates navigation control")
    func navigationRoleGeneratesControl() {
        let element = textElement(content: "Dashboard", role: .navigationItem)
        let doc = makeDocument(elements: [element])
        let (updated, _) = engine.infer(document: doc)

        let controls = updated.blueprint?.controls ?? []
        #expect(controls.count == 1)
        #expect(controls[0].kind == .navigation)
    }

    @Test("Date filter role generates filter control")
    func dateFilterRoleGeneratesControl() {
        let element = textElement(content: "Jan - Feb", role: .dateFilter)
        let doc = makeDocument(elements: [element])
        let (updated, _) = engine.infer(document: doc)

        let controls = updated.blueprint?.controls ?? []
        #expect(controls.count == 1)
        #expect(controls[0].kind == .filter)
    }

    @Test("Chart role generates chart control with loading/empty states")
    func chartRoleGeneratesStates() {
        let element = shapeElement(name: "Chart Area", role: .chart)
        let doc = makeDocument(elements: [element])
        let (updated, _) = engine.infer(document: doc)

        let states = updated.blueprint?.states ?? []
        let stateNames = states.map(\.name)

        // Should have Default View, Chart Drilldown, Loading State, and Empty State
        #expect(stateNames.contains("Default View"))
        #expect(stateNames.contains("Chart Drilldown"))
        #expect(stateNames.contains("Loading State"))
        #expect(stateNames.contains("Empty State"))
    }

    @Test("Navigation control generates screen state")
    func navigationGeneratesScreenState() {
        let element = textElement(content: "Reports", role: .navigationItem)
        let doc = makeDocument(elements: [element])
        let (updated, _) = engine.infer(document: doc)

        let states = updated.blueprint?.states ?? []
        let stateNames = states.map(\.name)
        #expect(stateNames.contains("Screen: Reports"))
    }

    @Test("Export button generates export flow state")
    func exportButtonGeneratesExportFlow() {
        let element = textElement(content: "Export PDF", role: .buttonPrimary)
        let doc = makeDocument(elements: [element])
        let (updated, _) = engine.infer(document: doc)

        let states = updated.blueprint?.states ?? []
        let stateNames = states.map(\.name)
        #expect(stateNames.contains("Export Flow"))
    }

    @Test("Create button generates create form and create success states")
    func createButtonGeneratesFormAndSuccessStates() {
        let element = textElement(content: "Create New", role: .buttonPrimary)
        let doc = makeDocument(elements: [element])
        let (updated, _) = engine.infer(document: doc)

        let states = updated.blueprint?.states ?? []
        let stateNames = states.map(\.name)
        #expect(stateNames.contains("Create Form"))
        #expect(stateNames.contains("Create Success"))
    }

    @Test("Suggested artboards generated from states")
    func suggestedArtboardsGenerated() {
        let elements = [
            textElement(content: "Dashboard", role: .navigationItem),
            textElement(content: "Reports", role: .navigationItem),
        ]
        let doc = makeDocument(elements: elements)
        let (updated, _) = engine.infer(document: doc)

        let artboards = updated.blueprint?.suggestedArtboards ?? []
        #expect(!artboards.isEmpty)
        // Each suggested artboard name should start with "State "
        for artboard in artboards {
            #expect(artboard.name.hasPrefix("State"))
        }
    }

    @Test("Mirror score within valid range")
    func mirrorScoreRange() {
        let elements = [
            textElement(content: "Dashboard", role: .navigationItem),
            textElement(content: "1,234", role: .metricValue),
            shapeElement(name: "Chart", role: .chart),
        ]
        let doc = makeDocument(elements: elements)
        let (updated, _) = engine.infer(document: doc)

        let score = updated.blueprint?.mirrorScore ?? 0
        #expect(score >= 0.35)
        #expect(score <= 0.99)
    }

    @Test("Build notes include control and state counts")
    func buildNotesContent() {
        let element = textElement(content: "Dashboard", role: .navigationItem)
        let doc = makeDocument(elements: [element])
        let (updated, _) = engine.infer(document: doc)

        let notes = updated.blueprint?.buildNotes ?? []
        #expect(!notes.isEmpty)
        #expect(notes.contains(where: { $0.contains("controls") }))
        #expect(notes.contains(where: { $0.contains("state candidates") }))
    }

    @Test("Duplicate controls are deduplicated")
    func duplicateControlsDeduplication() {
        let element1 = textElement(
            content: "Dashboard",
            frame: ElementFrame(x: 20, y: 100, width: 120, height: 24),
            role: .navigationItem
        )
        let element2 = textElement(
            content: "Dashboard",
            frame: ElementFrame(x: 20, y: 200, width: 120, height: 24),
            role: .navigationItem
        )
        let doc = makeDocument(elements: [element1, element2])
        let (updated, _) = engine.infer(document: doc)

        let controls = updated.blueprint?.controls ?? []
        let navControls = controls.filter { $0.kind == .navigation }
        #expect(navControls.count == 1)
    }

    @Test("Search text generates input control")
    func searchTextGeneratesInputControl() {
        let element = textElement(content: "Search employees...", role: .unknown)
        let doc = makeDocument(elements: [element])
        let (updated, _) = engine.infer(document: doc)

        let controls = updated.blueprint?.controls ?? []
        #expect(controls.count == 1)
        #expect(controls[0].kind == .input)
    }

    @Test("Table header generates table control with sorted state")
    func tableHeaderGeneratesTableControl() {
        let element = textElement(content: "Name", role: .tableHeader)
        let doc = makeDocument(elements: [element])
        let (updated, _) = engine.infer(document: doc)

        let controls = updated.blueprint?.controls ?? []
        #expect(controls.contains(where: { $0.kind == .table }))

        let states = updated.blueprint?.states ?? []
        #expect(states.contains(where: { $0.name == "Table Sorted" }))
    }
}
