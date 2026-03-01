import XCTest
@testable import ImageElementStudio

@MainActor
final class ComponentServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeService() -> ComponentService {
        ComponentService()
    }

    private let artboardID = UUID(uuidString: "00000000-0000-0000-0000-000000000601")!
    private let elementID1 = UUID(uuidString: "00000000-0000-0000-0000-000000000602")!
    private let elementID2 = UUID(uuidString: "00000000-0000-0000-0000-000000000603")!

    private func makeArtboard(elements: [CanvasElement]? = nil) -> Artboard {
        let defaultElements = [
            CanvasElement(
                id: elementID1, name: "Button", kind: .shape,
                frame: ElementFrame(x: 10, y: 10, width: 100, height: 40),
                confidence: 0.9, content: nil, tags: [],
                semanticRole: .buttonPrimary, semanticReason: "primary button"
            ),
            CanvasElement(
                id: elementID2, name: "Label", kind: .text,
                frame: ElementFrame(x: 120, y: 10, width: 80, height: 20),
                confidence: 0.8, content: "Hello", tags: [],
                semanticRole: .heading, semanticReason: "heading text"
            ),
        ]
        return Artboard(
            id: artboardID, name: "Main",
            width: 1280, height: 720,
            elements: elements ?? defaultElements
        )
    }

    private func makeCanvasElements() -> [CanvasElement] {
        [
            CanvasElement(
                id: elementID1, name: "Button", kind: .shape,
                frame: ElementFrame(x: 10, y: 10, width: 100, height: 40),
                confidence: 0.9, content: nil, tags: [],
                semanticRole: .buttonPrimary, semanticReason: "primary button"
            ),
            CanvasElement(
                id: elementID2, name: "Label", kind: .text,
                frame: ElementFrame(x: 120, y: 10, width: 80, height: 20),
                confidence: 0.8, content: "Hello", tags: [],
                semanticRole: .heading, semanticReason: "heading text"
            ),
        ]
    }

    // MARK: - createComponentFromSelection

    func testCreateComponentFromSelectionCreatesSpec() {
        let service = makeService()
        let artboard = makeArtboard()
        let selectedIDs: Set<UUID> = [elementID1, elementID2]

        service.createComponentFromSelection(
            named: "MyComponent",
            selectedElementIDs: selectedIDs,
            selectedElements: makeCanvasElements(),
            activeArtboard: artboard,
            latestDesignTokens: nil,
            updateArtboard: { _, _ in }
        )

        XCTAssertEqual(service.latestComponentSpecs.count, 1)
        XCTAssertEqual(service.latestComponentSpecs.first?.name, "MyComponent")
        XCTAssertEqual(service.latestComponentSpecs.first?.elementIDs.count, 2)
    }

    func testCreateComponentFromSelectionAutoNames() {
        let service = makeService()
        let artboard = makeArtboard()

        service.createComponentFromSelection(
            named: nil,
            selectedElementIDs: [elementID1],
            selectedElements: [makeCanvasElements()[0]],
            activeArtboard: artboard,
            latestDesignTokens: nil,
            updateArtboard: { _, _ in }
        )

        XCTAssertEqual(service.latestComponentSpecs.first?.name, "Component 1")
    }

    func testCreateComponentFromSelectionIgnoresEmptySelection() {
        let service = makeService()

        service.createComponentFromSelection(
            named: "Empty",
            selectedElementIDs: [],
            selectedElements: [],
            activeArtboard: makeArtboard(),
            latestDesignTokens: nil,
            updateArtboard: { _, _ in }
        )

        XCTAssertTrue(service.latestComponentSpecs.isEmpty)
    }

    func testCreateComponentFromSelectionCreatesFirstInstance() {
        let service = makeService()
        let artboard = makeArtboard()

        service.createComponentFromSelection(
            named: "Card",
            selectedElementIDs: [elementID1],
            selectedElements: [makeCanvasElements()[0]],
            activeArtboard: artboard,
            latestDesignTokens: nil,
            updateArtboard: { _, _ in }
        )

        XCTAssertEqual(service.componentInstances.count, 1)
        XCTAssertEqual(service.componentInstances.first?.artboardID, artboardID)
        XCTAssertEqual(service.componentInstances.first?.state, "default")
    }

    func testCreateComponentFromSelectionInfersKindFromRole() {
        let service = makeService()
        let artboard = makeArtboard()
        let elements = [makeCanvasElements()[0]] // buttonPrimary role

        service.createComponentFromSelection(
            named: "CTA",
            selectedElementIDs: [elementID1],
            selectedElements: elements,
            activeArtboard: artboard,
            latestDesignTokens: nil,
            updateArtboard: { _, _ in }
        )

        XCTAssertEqual(service.latestComponentSpecs.first?.kind, .cta)
    }

    // MARK: - updateSelectedComponentVariants

    func testUpdateSelectedComponentVariantsAddsAxis() {
        let service = makeService()
        let spec = ComponentSpec(
            id: UUID(), name: "Card", kind: .card, role: nil,
            elementIDs: [elementID1], notes: "test",
            variantAxes: ["state": ["default"]], version: 1
        )
        service.latestComponentSpecs = [spec]
        service.selectedComponentID = spec.id

        service.updateSelectedComponentVariants(axis: "size", options: "small, medium, large")

        let updatedSpec = service.latestComponentSpecs.first
        XCTAssertEqual(updatedSpec?.variantAxes?["size"], ["small", "medium", "large"])
        XCTAssertEqual(updatedSpec?.version, 2)
    }

    func testUpdateSelectedComponentVariantsUpdatesStateMappings() {
        let service = makeService()
        let spec = ComponentSpec(
            id: UUID(), name: "Button", kind: .cta, role: nil,
            elementIDs: [elementID1], notes: "test",
            variantAxes: ["state": ["default"]], version: 1
        )
        service.latestComponentSpecs = [spec]
        service.selectedComponentID = spec.id

        service.updateSelectedComponentVariants(axis: "state", options: "default, hover, pressed")

        let updatedSpec = service.latestComponentSpecs.first
        XCTAssertEqual(updatedSpec?.stateMappings?["default"], "Default")
        XCTAssertEqual(updatedSpec?.stateMappings?["hover"], "Hover")
        XCTAssertEqual(updatedSpec?.stateMappings?["pressed"], "Pressed")
    }

    func testUpdateSelectedComponentVariantsIgnoresEmptyAxis() {
        let service = makeService()
        let spec = ComponentSpec(
            id: UUID(), name: "Card", kind: .card, role: nil,
            elementIDs: [elementID1], notes: "test",
            variantAxes: ["state": ["default"]], version: 1
        )
        service.latestComponentSpecs = [spec]
        service.selectedComponentID = spec.id

        service.updateSelectedComponentVariants(axis: "  ", options: "a, b")

        // Version should not change
        XCTAssertEqual(service.latestComponentSpecs.first?.version, 1)
    }

    // MARK: - variantMatrixPreview

    func testVariantMatrixPreviewReturnsEmptyForNilSpec() {
        let service = makeService()
        XCTAssertEqual(service.variantMatrixPreview(for: nil), [])
    }

    func testVariantMatrixPreviewReturnsCombinations() {
        let service = makeService()
        let spec = ComponentSpec(
            id: UUID(), name: "Card", kind: .card, role: nil,
            elementIDs: [], notes: "",
            variantAxes: ["size": ["small", "large"], "state": ["default", "hover"]],
            version: 1
        )
        let preview = service.variantMatrixPreview(for: spec)

        // 2 sizes x 2 states = 4 combinations
        XCTAssertEqual(preview.count, 4)
        // Each line should contain both axes
        for line in preview {
            XCTAssertTrue(line.contains("size="))
            XCTAssertTrue(line.contains("state="))
        }
    }

    func testVariantMatrixPreviewLimitsTo12Rows() {
        let service = makeService()
        let spec = ComponentSpec(
            id: UUID(), name: "Card", kind: .card, role: nil,
            elementIDs: [], notes: "",
            variantAxes: [
                "a": ["1", "2", "3", "4"],
                "b": ["x", "y", "z", "w"],
            ],
            version: 1
        )
        let preview = service.variantMatrixPreview(for: spec)

        // 4 x 4 = 16 but capped at 12
        XCTAssertEqual(preview.count, 12)
    }

    // MARK: - selectComponentInstance

    func testSelectComponentInstanceUpdatesSelection() {
        let service = makeService()
        let componentID = UUID()
        let instanceID = UUID()
        let instance = ComponentInstance(
            id: instanceID, componentID: componentID,
            name: "Instance 1", artboardID: artboardID,
            elementIDs: [elementID1, elementID2],
            variantSelection: ["state": "hover"],
            state: "hover",
            overrides: ["content": "Updated"]
        )
        service.componentInstances = [instance]

        var receivedIDs: Set<UUID>?
        service.selectComponentInstance(instanceID) { ids, _ in
            receivedIDs = ids
        }

        XCTAssertEqual(service.selectedComponentInstanceID, instanceID)
        XCTAssertEqual(service.selectedComponentID, componentID)
        XCTAssertEqual(service.selectedComponentStateDraft, "hover")
        XCTAssertEqual(receivedIDs, Set([elementID1, elementID2]))
    }

    func testSelectComponentInstanceClearsWhenNil() {
        let service = makeService()
        service.selectedComponentInstanceID = UUID()

        service.selectComponentInstance(nil) { _, _ in }

        XCTAssertNil(service.selectedComponentInstanceID)
    }

    // MARK: - mapSelectedInstanceToState

    func testMapSelectedInstanceToStateUpdatesInstanceState() {
        let service = makeService()
        let instanceID = UUID()
        let instance = ComponentInstance(
            id: instanceID, componentID: UUID(),
            name: "Instance 1", artboardID: artboardID,
            elementIDs: [elementID1],
            variantSelection: ["state": "default"],
            state: "default",
            overrides: [:]
        )
        service.componentInstances = [instance]
        service.selectedComponentInstanceID = instanceID

        service.mapSelectedInstanceToState("active") { _ in }

        XCTAssertEqual(service.componentInstances.first?.state, "active")
        XCTAssertEqual(service.componentInstances.first?.variantSelection["state"], "active")
        XCTAssertEqual(service.selectedComponentStateDraft, "active")
    }

    // MARK: - applyOverridesToAllInstances (public version)

    func testApplyOverridesToAllInstancesSetsOverridesOnAllMatchingInstances() {
        let service = makeService()
        let componentID = UUID()
        var instances = [
            ComponentInstance(
                id: UUID(), componentID: componentID,
                name: "Instance 1", artboardID: artboardID,
                elementIDs: [elementID1],
                variantSelection: [:], state: "default",
                overrides: [:]
            ),
            ComponentInstance(
                id: UUID(), componentID: componentID,
                name: "Instance 2", artboardID: artboardID,
                elementIDs: [elementID2],
                variantSelection: [:], state: "default",
                overrides: [:]
            ),
            ComponentInstance(
                id: UUID(), componentID: UUID(), // different component
                name: "Other Instance", artboardID: artboardID,
                elementIDs: [],
                variantSelection: [:], state: "default",
                overrides: [:]
            ),
        ]

        let overrides = ["content": "Updated text", "fill": "#FF0000"]
        service.applyOverridesToAllInstances(of: componentID, overrides: overrides, componentInstances: &instances)

        XCTAssertEqual(instances[0].overrides, overrides)
        XCTAssertEqual(instances[1].overrides, overrides)
        XCTAssertEqual(instances[2].overrides, [:]) // different component, untouched
    }

    func testApplyOverridesToAllInstancesDoesNothingWhenOverridesEmpty() {
        let service = makeService()
        let componentID = UUID()
        var instances = [
            ComponentInstance(
                id: UUID(), componentID: componentID,
                name: "Instance 1", artboardID: artboardID,
                elementIDs: [elementID1],
                variantSelection: [:], state: "default",
                overrides: ["existing": "value"]
            ),
        ]

        service.applyOverridesToAllInstances(of: componentID, overrides: [:], componentInstances: &instances)

        XCTAssertEqual(instances[0].overrides, ["existing": "value"])
    }
}
