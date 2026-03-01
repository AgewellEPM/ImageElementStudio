import Foundation
import SwiftUI

// MARK: - CanvasService+Artboards

extension CanvasService {

    // MARK: - Artboard Management (pure inout, no callbacks)

    func addArtboard(
        artboards: inout [Artboard],
        selectedArtboardID: inout UUID?
    ) {
        let newBoard = Artboard.empty(
            named: "Artboard \(artboards.count + 1)"
        )
        artboards.append(newBoard)
        selectedArtboardID = newBoard.id
    }

    func duplicateActiveArtboard(
        artboards: inout [Artboard],
        selectedArtboardID: inout UUID?,
        activeArtboardIndex: Int?
    ) {
        guard let index = activeArtboardIndex else { return }
        let board = artboards[index]

        let duplicatedElements = board.elements.map { element in
            var copy = element
            copy.id = UUID()
            return copy
        }

        let duplicatedBoard = Artboard(
            id: UUID(),
            name: "\(board.name) Copy",
            width: board.width,
            height: board.height,
            elements: duplicatedElements
        )

        artboards.append(duplicatedBoard)
        selectedArtboardID = duplicatedBoard.id
    }

    func removeActiveArtboard(
        artboards: inout [Artboard],
        selectedArtboardID: inout UUID?,
        activeArtboardIndex: Int?
    ) {
        guard let index = activeArtboardIndex else { return }

        if artboards.count == 1 {
            artboards[0] = Artboard.empty(named: artboards[0].name)
            selectedArtboardID = artboards[0].id
            return
        }

        artboards.remove(at: index)
        selectedArtboardID = artboards.first?.id
    }

    // MARK: - Element Operations (pure inout, no callbacks)

    func renameSelectedElement(
        _ value: String,
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        selectedElementIDs: Set<UUID>
    ) {
        guard let index = activeArtboardIndex else { return }
        // Rename all selected elements; fall back to renaming the first match.
        for elementIndex in artboards[index].elements.indices where selectedElementIDs.contains(artboards[index].elements[elementIndex].id) {
            artboards[index].elements[elementIndex].name = value
        }
    }

    func deleteSelectedElement(
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        selectedElementIDs: Set<UUID>,
        selectedElementID: UUID?
    ) {
        let targets = selectedElementIDs.isEmpty ? (selectedElementID.map { Set([$0]) } ?? Set<UUID>()) : selectedElementIDs
        guard !targets.isEmpty else { return }
        guard let index = activeArtboardIndex else { return }
        artboards[index].elements.removeAll { targets.contains($0.id) }
    }

    func nudgeSelectedElement(
        deltaX: Double,
        deltaY: Double,
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        selectedElementID: UUID?
    ) {
        guard let elementID = selectedElementID else { return }
        guard let boardIndex = activeArtboardIndex else { return }
        guard let elementIndex = artboards[boardIndex].elements.firstIndex(where: { $0.id == elementID }) else { return }

        var element = artboards[boardIndex].elements[elementIndex]
        let maxX = Double(artboards[boardIndex].width) - element.frame.width
        let maxY = Double(artboards[boardIndex].height) - element.frame.height
        element.frame.x = min(max(0, element.frame.x + deltaX), max(0, maxX))
        element.frame.y = min(max(0, element.frame.y + deltaY), max(0, maxY))
        artboards[boardIndex].elements[elementIndex] = element
    }

    // MARK: - Public Methods (legacy callback-based, kept for backward compatibility)

    func addArtboard(
        to artboards: inout [Artboard],
        selectedArtboardID: inout UUID?,
        activeCanvasSize: CGSize,
        latestImageDescriptor: ImageDescriptor?,
        recordSnapshot: (Artboard, String) -> Void,
        regenerateJSON: () -> Void
    ) {
        let newBoard = Artboard.empty(
            named: "Artboard \(artboards.count + 1)",
            width: Int(activeCanvasSize.width),
            height: Int(activeCanvasSize.height),
            filename: latestImageDescriptor?.filename
        )

        artboards.append(newBoard)
        selectedArtboardID = newBoard.id
        regenerateJSON()
        recordSnapshot(newBoard, "add-artboard")
    }

    func duplicateActiveArtboard(
        artboards: inout [Artboard],
        selectedArtboardID: inout UUID?,
        activeArtboard: Artboard?,
        recordSnapshot: (Artboard, String) -> Void
    ) {
        guard let board = activeArtboard else { return }

        let duplicatedElements = board.elements.map { element in
            var copy = element
            copy.id = UUID()
            return copy
        }

        let duplicatedBoard = Artboard(
            id: UUID(),
            name: "\(board.name) Copy",
            width: board.width,
            height: board.height,
            elements: duplicatedElements
        )

        artboards.append(duplicatedBoard)
        selectedArtboardID = duplicatedBoard.id
        recordSnapshot(duplicatedBoard, "duplicate-artboard")
    }

    func removeActiveArtboard(
        artboards: inout [Artboard],
        selectedArtboardID: inout UUID?,
        activeArtboardIndex: Int?,
        latestImageDescriptor: ImageDescriptor?,
        clearSelection: () -> Void,
        reconcileIntegrity: () -> Void,
        regenerateJSON: () -> Void,
        recordSnapshot: (Artboard, String) -> Void
    ) {
        guard let index = activeArtboardIndex else { return }

        if artboards.count == 1 {
            artboards[0] = Artboard.empty(named: artboards[0].name, filename: latestImageDescriptor?.filename)
            selectedArtboardID = artboards[0].id
            clearSelection()
            reconcileIntegrity()
            regenerateJSON()
            recordSnapshot(artboards[0], "reset-artboard")
            return
        }

        artboards.remove(at: index)
        selectedArtboardID = artboards.first?.id
        reconcileIntegrity()
        let snapshotBoard = artboards.first(where: { $0.id == selectedArtboardID }) ?? artboards.first ?? Artboard.empty()
        recordSnapshot(snapshotBoard, "remove-artboard")
    }

    func generateStateArtboardsFromLatestBlueprint(
        blueprint: BuildBlueprint?,
        artboards: inout [Artboard],
        selectedArtboardID: UUID?,
        memoryStore: ProjectMemoryStore,
        latestImageDescriptor: ImageDescriptor?,
        selectedImageURL: URL?,
        latestScope: ProductScopeSnapshot?
    ) -> ProjectMemory {
        guard let blueprint = blueprint else { return memoryStore.memory }
        return generateSuggestedStateArtboards(
            from: blueprint,
            sourceArtboardID: selectedArtboardID,
            artboards: &artboards,
            selectedArtboardID: selectedArtboardID,
            memoryStore: memoryStore,
            latestImageDescriptor: latestImageDescriptor,
            selectedImageURL: selectedImageURL,
            latestScope: latestScope
        )
    }

    func renameSelectedElement(
        _ value: String,
        selectedElementID: UUID?,
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        reconcileIntegrity: () -> Void,
        regenerateJSON: () -> Void
    ) {
        guard let elementID = selectedElementID else { return }
        guard let index = activeArtboardIndex else { return }
        guard let elementIndex = artboards[index].elements.firstIndex(where: { $0.id == elementID }) else { return }
        artboards[index].elements[elementIndex].name = value
        reconcileIntegrity()
        regenerateJSON()
    }

    func deleteSelectedElement(
        selectedElementID: UUID?,
        selectedElementIDs: Set<UUID>,
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        clearSelection: () -> Void,
        reconcileIntegrity: () -> Void,
        regenerateJSON: () -> Void
    ) {
        let targets = selectedElementIDs.isEmpty ? (selectedElementID.map { Set([$0]) } ?? Set<UUID>()) : selectedElementIDs
        guard !targets.isEmpty else { return }
        guard let index = activeArtboardIndex else { return }
        artboards[index].elements.removeAll { targets.contains($0.id) }
        reconcileIntegrity()
        regenerateJSON()
        clearSelection()
    }

    func nudgeSelectedElement(
        deltaX: Double,
        deltaY: Double,
        selectedElementIDs: Set<UUID>,
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        snapToGrid: Bool,
        gridSize: Double,
        reconcileIntegrity: () -> Void,
        regenerateJSON: () -> Void
    ) {
        guard !selectedElementIDs.isEmpty else { return }
        guard let boardIndex = activeArtboardIndex else { return }
        for index in artboards[boardIndex].elements.indices where selectedElementIDs.contains(artboards[boardIndex].elements[index].id) {
            var element = artboards[boardIndex].elements[index]

            let maxX = Double(artboards[boardIndex].width) - element.frame.width
            let maxY = Double(artboards[boardIndex].height) - element.frame.height
            var nextX = min(max(0, element.frame.x + deltaX), max(0, maxX))
            var nextY = min(max(0, element.frame.y + deltaY), max(0, maxY))

            if snapToGrid {
                nextX = snap(value: nextX, gridSize: gridSize)
                nextY = snap(value: nextY, gridSize: gridSize)
            }

            element.frame.x = min(max(0, nextX), max(0, maxX))
            element.frame.y = min(max(0, nextY), max(0, maxY))
            artboards[boardIndex].elements[index] = element
        }
        reconcileIntegrity()
        regenerateJSON()
    }

    // MARK: - Legacy Callback-Based Alignment (6 functions)

    func alignSelectedElementLeft(
        selectedElementID: UUID?,
        selectedElementIDs: Set<UUID>,
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        snapToGrid: Bool,
        gridSize: Double,
        reconcileIntegrity: () -> Void,
        regenerateJSON: () -> Void
    ) {
        alignSelectedElement(
            .left,
            selectedElementID: selectedElementID,
            selectedElementIDs: selectedElementIDs,
            artboards: &artboards,
            activeArtboardIndex: activeArtboardIndex,
            snapToGrid: snapToGrid,
            gridSize: gridSize,
            reconcileIntegrity: reconcileIntegrity,
            regenerateJSON: regenerateJSON
        )
    }

    func alignSelectedElementHorizontalCenter(
        selectedElementID: UUID?,
        selectedElementIDs: Set<UUID>,
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        snapToGrid: Bool,
        gridSize: Double,
        reconcileIntegrity: () -> Void,
        regenerateJSON: () -> Void
    ) {
        alignSelectedElement(
            .centerHorizontal,
            selectedElementID: selectedElementID,
            selectedElementIDs: selectedElementIDs,
            artboards: &artboards,
            activeArtboardIndex: activeArtboardIndex,
            snapToGrid: snapToGrid,
            gridSize: gridSize,
            reconcileIntegrity: reconcileIntegrity,
            regenerateJSON: regenerateJSON
        )
    }

    func alignSelectedElementRight(
        selectedElementID: UUID?,
        selectedElementIDs: Set<UUID>,
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        snapToGrid: Bool,
        gridSize: Double,
        reconcileIntegrity: () -> Void,
        regenerateJSON: () -> Void
    ) {
        alignSelectedElement(
            .right,
            selectedElementID: selectedElementID,
            selectedElementIDs: selectedElementIDs,
            artboards: &artboards,
            activeArtboardIndex: activeArtboardIndex,
            snapToGrid: snapToGrid,
            gridSize: gridSize,
            reconcileIntegrity: reconcileIntegrity,
            regenerateJSON: regenerateJSON
        )
    }

    func alignSelectedElementTop(
        selectedElementID: UUID?,
        selectedElementIDs: Set<UUID>,
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        snapToGrid: Bool,
        gridSize: Double,
        reconcileIntegrity: () -> Void,
        regenerateJSON: () -> Void
    ) {
        alignSelectedElement(
            .top,
            selectedElementID: selectedElementID,
            selectedElementIDs: selectedElementIDs,
            artboards: &artboards,
            activeArtboardIndex: activeArtboardIndex,
            snapToGrid: snapToGrid,
            gridSize: gridSize,
            reconcileIntegrity: reconcileIntegrity,
            regenerateJSON: regenerateJSON
        )
    }

    func alignSelectedElementVerticalCenter(
        selectedElementID: UUID?,
        selectedElementIDs: Set<UUID>,
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        snapToGrid: Bool,
        gridSize: Double,
        reconcileIntegrity: () -> Void,
        regenerateJSON: () -> Void
    ) {
        alignSelectedElement(
            .centerVertical,
            selectedElementID: selectedElementID,
            selectedElementIDs: selectedElementIDs,
            artboards: &artboards,
            activeArtboardIndex: activeArtboardIndex,
            snapToGrid: snapToGrid,
            gridSize: gridSize,
            reconcileIntegrity: reconcileIntegrity,
            regenerateJSON: regenerateJSON
        )
    }

    func alignSelectedElementBottom(
        selectedElementID: UUID?,
        selectedElementIDs: Set<UUID>,
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        snapToGrid: Bool,
        gridSize: Double,
        reconcileIntegrity: () -> Void,
        regenerateJSON: () -> Void
    ) {
        alignSelectedElement(
            .bottom,
            selectedElementID: selectedElementID,
            selectedElementIDs: selectedElementIDs,
            artboards: &artboards,
            activeArtboardIndex: activeArtboardIndex,
            snapToGrid: snapToGrid,
            gridSize: gridSize,
            reconcileIntegrity: reconcileIntegrity,
            regenerateJSON: regenerateJSON
        )
    }

    // MARK: - Private Helpers

    func generateSuggestedStateArtboards(
        from blueprint: BuildBlueprint,
        sourceArtboardID: UUID?,
        artboards: inout [Artboard],
        selectedArtboardID: UUID?,
        memoryStore: ProjectMemoryStore,
        latestImageDescriptor: ImageDescriptor?,
        selectedImageURL: URL?,
        latestScope: ProductScopeSnapshot?
    ) -> ProjectMemory {
        guard let sourceID = sourceArtboardID ?? selectedArtboardID,
              let sourceIndex = artboards.firstIndex(where: { $0.id == sourceID }) else { return memoryStore.memory }

        let sourceBoard = artboards[sourceIndex]
        let suggestions = Array(blueprint.suggestedArtboards.prefix(8))
        guard !suggestions.isEmpty else { return memoryStore.memory }

        let preservedBoards = artboards.filter { board in
            board.id == sourceBoard.id || !isAutoStateArtboard(board)
        }

        let generatedBoards = suggestions.map { suggestion in
            var cloned = sourceBoard
            cloned.id = UUID()
            cloned.name = suggestion.name
            cloned.elements = sourceBoard.elements.map { element in
                var copy = element
                copy.id = UUID()
                if copy.kind == .imageRoot {
                    var tags = Set(copy.tags)
                    tags.insert("auto-state")
                    tags.insert("state:\(slugifiedStateName(suggestion.name))")
                    copy.tags = tags.sorted()
                    copy.semanticReason = suggestion.reason
                }
                return copy
            }
            return cloned
        }

        artboards = preservedBoards + generatedBoards

        return memoryStore.recordArtboardSnapshot(
            artboard: sourceBoard,
            reason: "auto-state-artboards",
            imageName: latestImageDescriptor?.filename ?? selectedImageURL?.lastPathComponent,
            scope: latestScope
        )
    }

    private func isAutoStateArtboard(_ artboard: Artboard) -> Bool {
        artboard.elements.contains(where: { element in
            element.kind == .imageRoot && element.tags.contains("auto-state")
        })
    }

    private func slugifiedStateName(_ value: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789")
        var output = ""
        var previousDash = false

        for scalar in value.lowercased().unicodeScalars {
            if allowed.contains(Character(scalar)) {
                output.unicodeScalars.append(scalar)
                previousDash = false
            } else if !previousDash {
                output.append("-")
                previousDash = true
            }
        }

        while output.hasPrefix("-") { output.removeFirst() }
        while output.hasSuffix("-") { output.removeLast() }
        return output.isEmpty ? "state" : output
    }

    private func alignSelectedElement(
        _ alignment: ElementAlignmentCommand,
        selectedElementID: UUID?,
        selectedElementIDs: Set<UUID>,
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        snapToGrid: Bool,
        gridSize: Double,
        reconcileIntegrity: () -> Void,
        regenerateJSON: () -> Void
    ) {
        let targets = selectedElementIDs.isEmpty ? (selectedElementID.map { Set([$0]) } ?? Set<UUID>()) : selectedElementIDs
        guard !targets.isEmpty else { return }
        guard let boardIndex = activeArtboardIndex else { return }

        for index in artboards[boardIndex].elements.indices where targets.contains(artboards[boardIndex].elements[index].id) {
            var element = artboards[boardIndex].elements[index]
            let maxX = Double(artboards[boardIndex].width) - element.frame.width
            let maxY = Double(artboards[boardIndex].height) - element.frame.height

            switch alignment {
            case .left:
                element.frame.x = 0
            case .centerHorizontal:
                element.frame.x = (Double(artboards[boardIndex].width) - element.frame.width) / 2
            case .right:
                element.frame.x = maxX
            case .top:
                element.frame.y = 0
            case .centerVertical:
                element.frame.y = (Double(artboards[boardIndex].height) - element.frame.height) / 2
            case .bottom:
                element.frame.y = maxY
            }

            if snapToGrid {
                element.frame.x = min(max(0, snap(value: element.frame.x, gridSize: gridSize)), max(0, maxX))
                element.frame.y = min(max(0, snap(value: element.frame.y, gridSize: gridSize)), max(0, maxY))
            }

            artboards[boardIndex].elements[index] = element
        }
        reconcileIntegrity()
        regenerateJSON()
    }
}

extension CanvasService.BuildStepContext {
    @MainActor init(from vm: StudioViewModel) {
        self.init(selectedImage: vm.selectedImage != nil, renderableElementCount: vm.renderableElements.count,
            latestScope: vm.latestScope, latestBlueprint: vm.latestBlueprint, latestDesignTokens: vm.latestDesignTokens,
            latestComponentSpecs: vm.latestComponentSpecs, componentInstances: vm.componentInstances,
            importLossReport: vm.importLossReport, latestBuildQualityReport: vm.latestBuildQualityReport,
            latestFullStackBuildSummary: vm.latestFullStackBuildSummary, latestEnterpriseReadinessReport: vm.latestEnterpriseReadinessReport,
            canExportBuildArtifacts: vm.canExportBuildArtifacts, reviewGateStatusLine: vm.reviewGateStatusLine,
            latestBenchmarkReport: vm.latestBenchmarkReport, strategySession: vm.strategySession,
            acceptedStrategySpec: vm.acceptedStrategySpec, isAnalyzing: vm.isAnalyzing,
            strategyStageLine: vm.strategyStageLine, designSystemStatusLine: vm.designSystemStatusLine,
            interopStatusLine: vm.interopStatusLine, componentSystemStatusLine: vm.componentSystemStatusLine,
            benchmarkStatusLine: vm.benchmarkStatusLine, fullStackStatusLine: vm.fullStackStatusLine,
            enterpriseReadinessStatusLine: vm.enterpriseReadinessStatusLine, realTimeBuildTarget: vm.realTimeBuildTarget.title,
            lastRealtimeBuildPath: vm.lastRealtimeBuildPath, overdueReviewCommentCount: vm.overdueReviewCommentCount,
            reviewGateBlockReason: vm.reviewGateBlockReason, benchmarkTrendScore: vm.benchmarkTrendScore)
    }
}
