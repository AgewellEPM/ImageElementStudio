import Foundation

@MainActor
final class SelectionService: ObservableObject {
    @Published var selectedElementID: UUID? {
        didSet {
            guard !isSyncingSelectionState else { return }
            isSyncingSelectionState = true
            if let selectedElementID {
                selectedElementIDs = [selectedElementID]
            } else {
                selectedElementIDs = []
            }
            isSyncingSelectionState = false
        }
    }
    @Published var selectedElementIDs: Set<UUID> = [] {
        didSet {
            guard !isSyncingSelectionState else { return }
            isSyncingSelectionState = true
            selectedElementID = selectedElementIDs.sorted { $0.uuidString < $1.uuidString }.first
            isSyncingSelectionState = false
        }
    }
    @Published var isMarqueeSelecting: Bool = false
    @Published var marqueeSelectionCount: Int = 0

    private var isSyncingSelectionState: Bool = false

    // MARK: - Computed Properties

    var hasMultiSelection: Bool {
        selectedElementIDs.count > 1
    }

    var canDistributeSelection: Bool {
        selectedElementIDs.count >= 3
    }

    // MARK: - Public Methods

    func clearElementSelection() {
        isSyncingSelectionState = true
        selectedElementID = nil
        selectedElementIDs = []
        isSyncingSelectionState = false
    }

    func setSelectedElement(_ id: UUID?, additive: Bool = false, validIDs: Set<UUID>) {
        guard let id else {
            clearElementSelection()
            return
        }

        if additive {
            var updated = selectedElementIDs
            if updated.contains(id) {
                updated.remove(id)
            } else {
                updated.insert(id)
            }
            setSelectedElements(updated, preferredPrimary: id, validIDs: validIDs)
            return
        }

        setSelectedElements([id], preferredPrimary: id, validIDs: validIDs)
    }

    func setSelectedElements(_ ids: Set<UUID>, preferredPrimary: UUID? = nil, validIDs: Set<UUID>) {
        let filtered = ids.intersection(validIDs)

        isSyncingSelectionState = true
        selectedElementIDs = filtered
        if let preferredPrimary, filtered.contains(preferredPrimary) {
            selectedElementID = preferredPrimary
        } else {
            selectedElementID = filtered.sorted { $0.uuidString < $1.uuidString }.first
        }
        isSyncingSelectionState = false
        marqueeSelectionCount = filtered.count
    }

    func selectElementsByMarquee(_ elementIDs: [UUID], additive: Bool = false, validIDs: Set<UUID>) {
        let ids = Set(elementIDs)
        if additive {
            setSelectedElements(selectedElementIDs.union(ids), preferredPrimary: selectedElementID ?? ids.first, validIDs: validIDs)
            return
        }
        setSelectedElements(ids, preferredPrimary: ids.first, validIDs: validIDs)
    }
}
