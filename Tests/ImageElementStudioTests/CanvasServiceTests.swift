import XCTest
@testable import ImageElementStudio

@MainActor
final class CanvasServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeService() -> CanvasService {
        CanvasService()
    }

    private let artboardID = UUID(uuidString: "00000000-0000-0000-0000-000000000600")!
    private let idA = UUID(uuidString: "00000000-0000-0000-0000-000000000601")!
    private let idB = UUID(uuidString: "00000000-0000-0000-0000-000000000602")!
    private let idC = UUID(uuidString: "00000000-0000-0000-0000-000000000603")!

    private func makeElement(id: UUID, x: Double, y: Double, width: Double = 100, height: Double = 50) -> CanvasElement {
        CanvasElement(
            id: id,
            name: "Element",
            kind: .shape,
            frame: ElementFrame(x: x, y: y, width: width, height: height),
            confidence: 0.9,
            content: nil,
            tags: [],
            semanticRole: .unknown,
            semanticReason: "test"
        )
    }

    private func makeArtboard(elements: [CanvasElement], width: Int = 1000, height: Int = 800) -> Artboard {
        Artboard(id: artboardID, name: "Test", width: width, height: height, elements: elements)
    }

    // MARK: - reconcileComponentModelIntegrity

    func testReconcileComponentModelIntegrityRemovesOrphanedInstances() {
        let service = makeService()
        let orphanID = UUID(uuidString: "00000000-0000-0000-0000-000000000699")!
        var artboards = [makeArtboard(elements: [makeElement(id: idA, x: 0, y: 0)])]
        var specs: [ComponentSpec] = []
        var instances: [ComponentInstance] = [
            ComponentInstance(
                id: UUID(),
                componentID: UUID(),
                name: "Orphan",
                artboardID: artboardID,
                elementIDs: [orphanID],
                variantSelection: [:],
                state: "default",
                overrides: [:]
            ),
        ]

        service.reconcileComponentModelIntegrity(
            artboards: &artboards,
            latestComponentSpecs: &specs,
            componentInstances: &instances
        )

        XCTAssertTrue(instances.isEmpty, "Instance with non-existent element IDs should be removed")
    }

    func testReconcileComponentModelIntegrityKeepsValidInstances() {
        let service = makeService()
        var artboards = [makeArtboard(elements: [makeElement(id: idA, x: 0, y: 0)])]
        var specs: [ComponentSpec] = [
            ComponentSpec(id: UUID(), name: "Valid", kind: .card, elementIDs: [idA], notes: "test"),
        ]
        var instances: [ComponentInstance] = [
            ComponentInstance(
                id: UUID(),
                componentID: specs[0].id,
                name: "ValidInst",
                artboardID: artboardID,
                elementIDs: [idA],
                variantSelection: [:],
                state: "default",
                overrides: [:]
            ),
        ]

        service.reconcileComponentModelIntegrity(
            artboards: &artboards,
            latestComponentSpecs: &specs,
            componentInstances: &instances
        )

        XCTAssertEqual(instances.count, 1)
        XCTAssertEqual(specs.count, 1)
    }

    // MARK: - Alignment: left

    func testAlignSelectedElementLeftSetsXToZero() {
        let service = makeService()
        var artboards = [makeArtboard(elements: [makeElement(id: idA, x: 200, y: 100)])]

        service.alignSelectedElementLeft(
            artboards: &artboards,
            activeArtboardIndex: 0,
            selectedElementIDs: [idA]
        )

        XCTAssertEqual(artboards[0].elements[0].frame.x, 0)
    }

    // MARK: - Alignment: right

    func testAlignSelectedElementRightSetsXToMaxX() {
        let service = makeService()
        let elementWidth = 100.0
        var artboards = [makeArtboard(elements: [makeElement(id: idA, x: 0, y: 0, width: elementWidth)])]

        service.alignSelectedElementRight(
            artboards: &artboards,
            activeArtboardIndex: 0,
            selectedElementIDs: [idA]
        )

        let expected = Double(artboards[0].width) - elementWidth
        XCTAssertEqual(artboards[0].elements[0].frame.x, expected)
    }

    // MARK: - Alignment: center horizontal

    func testAlignSelectedElementHorizontalCenterCentersElement() {
        let service = makeService()
        let elementWidth = 100.0
        var artboards = [makeArtboard(elements: [makeElement(id: idA, x: 0, y: 0, width: elementWidth)])]

        service.alignSelectedElementHorizontalCenter(
            artboards: &artboards,
            activeArtboardIndex: 0,
            selectedElementIDs: [idA]
        )

        let expected = (Double(artboards[0].width) - elementWidth) / 2
        XCTAssertEqual(artboards[0].elements[0].frame.x, expected)
    }

    // MARK: - Alignment: top

    func testAlignSelectedElementTopSetsYToZero() {
        let service = makeService()
        var artboards = [makeArtboard(elements: [makeElement(id: idA, x: 100, y: 300)])]

        service.alignSelectedElementTop(
            artboards: &artboards,
            activeArtboardIndex: 0,
            selectedElementIDs: [idA]
        )

        XCTAssertEqual(artboards[0].elements[0].frame.y, 0)
    }

    // MARK: - Alignment: bottom

    func testAlignSelectedElementBottomSetsYToMaxY() {
        let service = makeService()
        let elementHeight = 50.0
        var artboards = [makeArtboard(elements: [makeElement(id: idA, x: 0, y: 0, height: elementHeight)])]

        service.alignSelectedElementBottom(
            artboards: &artboards,
            activeArtboardIndex: 0,
            selectedElementIDs: [idA]
        )

        let expected = Double(artboards[0].height) - elementHeight
        XCTAssertEqual(artboards[0].elements[0].frame.y, expected)
    }

    // MARK: - Alignment: vertical center

    func testAlignSelectedElementVerticalCenterCentersElement() {
        let service = makeService()
        let elementHeight = 50.0
        var artboards = [makeArtboard(elements: [makeElement(id: idA, x: 0, y: 0, height: elementHeight)])]

        service.alignSelectedElementVerticalCenter(
            artboards: &artboards,
            activeArtboardIndex: 0,
            selectedElementIDs: [idA]
        )

        let expected = (Double(artboards[0].height) - elementHeight) / 2
        XCTAssertEqual(artboards[0].elements[0].frame.y, expected)
    }

    // MARK: - Distribute horizontally

    func testDistributeSelectedElementsHorizontallySpacesEvenly() {
        let service = makeService()
        let elA = makeElement(id: idA, x: 0, y: 0, width: 50)
        let elB = makeElement(id: idB, x: 100, y: 0, width: 50)
        let elC = makeElement(id: idC, x: 500, y: 0, width: 50)
        var artboards = [makeArtboard(elements: [elA, elB, elC])]

        service.distributeSelectedElementsHorizontally(
            artboards: &artboards,
            activeArtboardIndex: 0,
            selectedElementIDs: [idA, idB, idC],
            canDistribute: true
        )

        // After distribution, elements should be evenly spaced between first.minX and last.maxX
        let positions = artboards[0].elements.map(\.frame.x).sorted()
        XCTAssertEqual(positions.count, 3)
        // First element stays at its position
        XCTAssertEqual(positions[0], 0, accuracy: 0.01)
        // Last element ends at original last maxX
        let lastEl = artboards[0].elements.first(where: { $0.frame.x == positions.last! })!
        XCTAssertEqual(lastEl.frame.maxX, 550, accuracy: 0.01)
    }

    func testDistributeSelectedElementsHorizontallyDoesNothingWhenCanDistributeIsFalse() {
        let service = makeService()
        let elA = makeElement(id: idA, x: 0, y: 0)
        let elB = makeElement(id: idB, x: 200, y: 0)
        let elC = makeElement(id: idC, x: 400, y: 0)
        var artboards = [makeArtboard(elements: [elA, elB, elC])]
        let originalPositions = artboards[0].elements.map(\.frame.x)

        service.distributeSelectedElementsHorizontally(
            artboards: &artboards,
            activeArtboardIndex: 0,
            selectedElementIDs: [idA, idB, idC],
            canDistribute: false
        )

        XCTAssertEqual(artboards[0].elements.map(\.frame.x), originalPositions)
    }

    // MARK: - Distribute vertically

    func testDistributeSelectedElementsVerticallySpacesEvenly() {
        let service = makeService()
        let elA = makeElement(id: idA, x: 0, y: 0, height: 40)
        let elB = makeElement(id: idB, x: 0, y: 100, height: 40)
        let elC = makeElement(id: idC, x: 0, y: 400, height: 40)
        var artboards = [makeArtboard(elements: [elA, elB, elC])]

        service.distributeSelectedElementsVertically(
            artboards: &artboards,
            activeArtboardIndex: 0,
            selectedElementIDs: [idA, idB, idC],
            canDistribute: true
        )

        let positions = artboards[0].elements.map(\.frame.y).sorted()
        XCTAssertEqual(positions.count, 3)
        XCTAssertEqual(positions[0], 0, accuracy: 0.01)
    }

    // MARK: - Nudge with snap

    func testNudgeSelectionMovesElementByDelta() {
        let service = makeService()
        var artboards = [makeArtboard(elements: [makeElement(id: idA, x: 100, y: 100)])]

        service.nudgeSelection(
            deltaX: 10,
            deltaY: 20,
            snapToGrid: false,
            gridSize: 8,
            artboards: &artboards,
            activeArtboardIndex: 0,
            selectedElementIDs: [idA]
        )

        XCTAssertEqual(artboards[0].elements[0].frame.x, 110)
        XCTAssertEqual(artboards[0].elements[0].frame.y, 120)
    }

    func testNudgeSelectionWithSnapRoundsToGrid() {
        let service = makeService()
        var artboards = [makeArtboard(elements: [makeElement(id: idA, x: 100, y: 100)])]

        service.nudgeSelection(
            deltaX: 3,
            deltaY: 3,
            snapToGrid: true,
            gridSize: 8,
            artboards: &artboards,
            activeArtboardIndex: 0,
            selectedElementIDs: [idA]
        )

        // 100 + 3 = 103, snapped to nearest multiple of 8 = 104
        let resultX = artboards[0].elements[0].frame.x
        XCTAssertEqual(resultX.truncatingRemainder(dividingBy: 8), 0, accuracy: 0.01,
                       "X should be snapped to grid")
    }

    func testNudgeSelectionClampsToArtboardBounds() {
        let service = makeService()
        var artboards = [makeArtboard(elements: [makeElement(id: idA, x: 0, y: 0, width: 100, height: 50)])]

        service.nudgeSelection(
            deltaX: -50,
            deltaY: -50,
            snapToGrid: false,
            gridSize: 8,
            artboards: &artboards,
            activeArtboardIndex: 0,
            selectedElementIDs: [idA]
        )

        XCTAssertGreaterThanOrEqual(artboards[0].elements[0].frame.x, 0)
        XCTAssertGreaterThanOrEqual(artboards[0].elements[0].frame.y, 0)
    }

    // MARK: - Resize

    func testResizeSelectedElementsBottomRightIncreasesSize() {
        let service = makeService()
        var artboards = [makeArtboard(elements: [makeElement(id: idA, x: 0, y: 0, width: 100, height: 50)])]

        service.resizeSelectedElements(
            handle: .bottomRight,
            deltaX: 20,
            deltaY: 10,
            artboards: &artboards,
            activeArtboardIndex: 0,
            selectedElementIDs: [idA]
        )

        XCTAssertEqual(artboards[0].elements[0].frame.width, 120)
        XCTAssertEqual(artboards[0].elements[0].frame.height, 60)
    }

    func testResizeSelectedElementsEnforcesMinimumSize() {
        let service = makeService()
        var artboards = [makeArtboard(elements: [makeElement(id: idA, x: 0, y: 0, width: 20, height: 20)])]

        service.resizeSelectedElements(
            handle: .bottomRight,
            deltaX: -100,
            deltaY: -100,
            artboards: &artboards,
            activeArtboardIndex: 0,
            selectedElementIDs: [idA]
        )

        XCTAssertGreaterThanOrEqual(artboards[0].elements[0].frame.width, 16)
        XCTAssertGreaterThanOrEqual(artboards[0].elements[0].frame.height, 16)
    }

    func testResizeSelectedElementsTopLeftAdjustsPositionAndSize() {
        let service = makeService()
        var artboards = [makeArtboard(elements: [makeElement(id: idA, x: 100, y: 100, width: 200, height: 200)])]

        service.resizeSelectedElements(
            handle: .topLeft,
            deltaX: 20,
            deltaY: 20,
            artboards: &artboards,
            activeArtboardIndex: 0,
            selectedElementIDs: [idA]
        )

        XCTAssertEqual(artboards[0].elements[0].frame.width, 180)
        XCTAssertEqual(artboards[0].elements[0].frame.height, 180)
        XCTAssertEqual(artboards[0].elements[0].frame.x, 120)
        XCTAssertEqual(artboards[0].elements[0].frame.y, 120)
    }

    // MARK: - Rotate

    func testRotateSelectedElementsUpdatesRotation() {
        let service = makeService()
        var artboards = [makeArtboard(elements: [makeElement(id: idA, x: 0, y: 0)])]

        service.rotateSelectedElements(
            by: 45,
            artboards: &artboards,
            activeArtboardIndex: 0,
            selectedElementIDs: [idA]
        )

        XCTAssertEqual(artboards[0].elements[0].rotationDegrees, 45)
    }

    func testRotateSelectedElementsWrapsAt360() {
        let service = makeService()
        var element = makeElement(id: idA, x: 0, y: 0)
        element.rotationDegrees = 350
        var artboards = [makeArtboard(elements: [element])]

        service.rotateSelectedElements(
            by: 20,
            artboards: &artboards,
            activeArtboardIndex: 0,
            selectedElementIDs: [idA]
        )

        XCTAssertEqual(artboards[0].elements[0].rotationDegrees, 10, accuracy: 0.001)
    }

    // MARK: - snap utility

    func testSnapValueRoundsToNearestGridUnit() {
        let service = makeService()

        XCTAssertEqual(service.snap(value: 13, gridSize: 8), 16)
        XCTAssertEqual(service.snap(value: 12, gridSize: 8), 16)
        XCTAssertEqual(service.snap(value: 8, gridSize: 8), 8)
        XCTAssertEqual(service.snap(value: 0, gridSize: 8), 0)
    }

    func testSnapValueUsesMinimumGridSizeOfTwo() {
        let service = makeService()

        // gridSize < 2 should use 2 as minimum
        let result = service.snap(value: 3, gridSize: 0)
        XCTAssertEqual(result, 4) // 3/2 rounded = 2, 2*2 = 4
    }
}
