import XCTest
@testable import ImageElementStudio

@MainActor
final class SelectionServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeService() -> SelectionService {
        SelectionService()
    }

    private let idA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let idB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let idC = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    private let idD = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!

    private var allIDs: Set<UUID> {
        [idA, idB, idC, idD]
    }

    // MARK: - clearElementSelection

    func testClearElementSelectionResetsAllSelectionState() {
        let service = makeService()
        service.setSelectedElements([idA, idB], preferredPrimary: idA, validIDs: allIDs)

        service.clearElementSelection()

        XCTAssertNil(service.selectedElementID)
        XCTAssertTrue(service.selectedElementIDs.isEmpty)
    }

    // MARK: - setSelectedElement (single)

    func testSetSelectedElementSingleSelectSetsExactlyOneElement() {
        let service = makeService()

        service.setSelectedElement(idA, additive: false, validIDs: allIDs)

        XCTAssertEqual(service.selectedElementID, idA)
        XCTAssertEqual(service.selectedElementIDs, [idA])
    }

    func testSetSelectedElementWithNilClearsSelection() {
        let service = makeService()
        service.setSelectedElement(idA, additive: false, validIDs: allIDs)

        service.setSelectedElement(nil, additive: false, validIDs: allIDs)

        XCTAssertNil(service.selectedElementID)
        XCTAssertTrue(service.selectedElementIDs.isEmpty)
    }

    // MARK: - setSelectedElement (additive)

    func testSetSelectedElementAdditiveAddsToExistingSelection() {
        let service = makeService()
        service.setSelectedElement(idA, additive: false, validIDs: allIDs)

        service.setSelectedElement(idB, additive: true, validIDs: allIDs)

        XCTAssertEqual(service.selectedElementIDs, [idA, idB])
        XCTAssertTrue(service.hasMultiSelection)
    }

    func testSetSelectedElementAdditiveRemovesAlreadySelectedElement() {
        let service = makeService()
        service.setSelectedElements([idA, idB], preferredPrimary: idA, validIDs: allIDs)

        service.setSelectedElement(idA, additive: true, validIDs: allIDs)

        XCTAssertEqual(service.selectedElementIDs, [idB])
        XCTAssertEqual(service.selectedElementID, idB)
    }

    // MARK: - setSelectedElements with preferredPrimary

    func testSetSelectedElementsWithPreferredPrimarySetsPrimaryCorrectly() {
        let service = makeService()

        service.setSelectedElements([idA, idB, idC], preferredPrimary: idB, validIDs: allIDs)

        XCTAssertEqual(service.selectedElementID, idB)
        XCTAssertEqual(service.selectedElementIDs, [idA, idB, idC])
    }

    func testSetSelectedElementsFiltersOutInvalidIDs() {
        let service = makeService()
        let limitedValid: Set<UUID> = [idA, idC]

        service.setSelectedElements([idA, idB, idC], preferredPrimary: idB, validIDs: limitedValid)

        XCTAssertEqual(service.selectedElementIDs, [idA, idC])
        // idB was not valid, so preferred primary falls back
        XCTAssertNotEqual(service.selectedElementID, idB)
        XCTAssertNotNil(service.selectedElementID)
    }

    func testSetSelectedElementsWithoutPreferredPrimaryUsesAlphabeticFirst() {
        let service = makeService()

        service.setSelectedElements([idB, idC], preferredPrimary: nil, validIDs: allIDs)

        // Should pick the first UUID by alphabetical uuidString
        let expected = [idB, idC].sorted { $0.uuidString < $1.uuidString }.first
        XCTAssertEqual(service.selectedElementID, expected)
    }

    // MARK: - selectElementsByMarquee

    func testSelectElementsByMarqueeNonAdditiveReplacesSelection() {
        let service = makeService()
        service.setSelectedElement(idA, additive: false, validIDs: allIDs)

        service.selectElementsByMarquee([idB, idC], additive: false, validIDs: allIDs)

        XCTAssertEqual(service.selectedElementIDs, [idB, idC])
        XCTAssertFalse(service.selectedElementIDs.contains(idA))
    }

    func testSelectElementsByMarqueeAdditiveUnionsWithExisting() {
        let service = makeService()
        service.setSelectedElement(idA, additive: false, validIDs: allIDs)

        service.selectElementsByMarquee([idB, idC], additive: true, validIDs: allIDs)

        XCTAssertEqual(service.selectedElementIDs, [idA, idB, idC])
    }

    func testSelectElementsByMarqueeUpdatesMarqueeSelectionCount() {
        let service = makeService()

        service.selectElementsByMarquee([idA, idB, idC], additive: false, validIDs: allIDs)

        XCTAssertEqual(service.marqueeSelectionCount, 3)
    }

    // MARK: - hasMultiSelection / canDistributeSelection

    func testHasMultiSelectionIsFalseForSingleElement() {
        let service = makeService()
        service.setSelectedElement(idA, additive: false, validIDs: allIDs)

        XCTAssertFalse(service.hasMultiSelection)
    }

    func testHasMultiSelectionIsTrueForTwoElements() {
        let service = makeService()
        service.setSelectedElements([idA, idB], preferredPrimary: idA, validIDs: allIDs)

        XCTAssertTrue(service.hasMultiSelection)
    }

    func testCanDistributeSelectionRequiresAtLeastThreeElements() {
        let service = makeService()

        service.setSelectedElements([idA, idB], preferredPrimary: idA, validIDs: allIDs)
        XCTAssertFalse(service.canDistributeSelection)

        service.setSelectedElements([idA, idB, idC], preferredPrimary: idA, validIDs: allIDs)
        XCTAssertTrue(service.canDistributeSelection)
    }

    func testCanDistributeSelectionIsFalseWhenEmpty() {
        let service = makeService()

        XCTAssertFalse(service.canDistributeSelection)
    }
}
