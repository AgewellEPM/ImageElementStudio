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
            // Use mobile dimensions for state artboards
            let mobileWidth = 393
            let mobileHeight = 852

            // Partition elements: keep shared (navigation, headers, root) + screen-relevant
            let screenKeywords = extractScreenKeywords(from: suggestion.name)
            let filteredElements = sourceBoard.elements.filter { element in
                if element.kind == .imageRoot { return true }
                if let role = element.semanticRole, isSharedRole(role) { return true }
                if !screenKeywords.isEmpty && elementMatchesScreen(element, keywords: screenKeywords) {
                    return true
                }
                return screenKeywords.isEmpty
            }

            let nonRootCount = filteredElements.filter { $0.kind != .imageRoot }.count
            let sourceElements = nonRootCount >= 3 ? filteredElements : sourceBoard.elements

            // Auto-layout elements into a mobile-friendly vertical stack
            let laidOutElements = autoLayoutForMobile(
                elements: sourceElements,
                screenWidth: Double(mobileWidth),
                screenHeight: Double(mobileHeight),
                stateName: suggestion.name,
                stateReason: suggestion.reason
            )

            return Artboard(
                id: UUID(),
                name: suggestion.name,
                width: mobileWidth,
                height: mobileHeight,
                elements: laidOutElements
            )
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

    // MARK: - Mobile Auto-Layout Engine

    private func autoLayoutForMobile(
        elements: [CanvasElement],
        screenWidth: Double,
        screenHeight: Double,
        stateName: String,
        stateReason: String
    ) -> [CanvasElement] {
        let padding: Double = 16
        let spacing: Double = 10
        let contentWidth = screenWidth - (padding * 2)

        // Separate elements by role for layout ordering
        var root: CanvasElement?
        var navElements: [CanvasElement] = []
        var headerElements: [CanvasElement] = []
        var contentElements: [CanvasElement] = []

        for element in elements {
            if element.kind == .imageRoot {
                root = element
                continue
            }
            switch element.semanticRole {
            case .navigationItem, .navigationSection, .appBrand:
                navElements.append(element)
            case .heading, .sectionTitle:
                headerElements.append(element)
            default:
                contentElements.append(element)
            }
        }

        var result: [CanvasElement] = []
        var cursorY: Double = 0

        // Root element (full screen)
        if var rootEl = root {
            rootEl.id = UUID()
            rootEl.frame = ElementFrame(x: 0, y: 0, width: screenWidth, height: screenHeight)
            var tags = Set(rootEl.tags)
            tags.insert("auto-state")
            tags.insert("state:\(slugifiedStateName(stateName))")
            rootEl.tags = tags.sorted()
            rootEl.semanticReason = stateReason
            result.append(rootEl)
        }

        // Status bar area
        cursorY = 54

        // Navigation bar (horizontal row at top)
        if !navElements.isEmpty {
            let navHeight: Double = 44
            let navItemWidth = min(contentWidth / Double(navElements.count), 80)
            var navX = padding
            for nav in navElements {
                var copy = nav
                copy.id = UUID()
                copy.frame = ElementFrame(x: navX, y: cursorY, width: navItemWidth - 4, height: navHeight)
                result.append(copy)
                navX += navItemWidth
            }
            cursorY += navHeight + spacing
        }

        // Headers
        for header in headerElements {
            var copy = header
            copy.id = UUID()
            let h: Double = header.semanticRole == .heading ? 36 : 28
            copy.frame = ElementFrame(x: padding, y: cursorY, width: contentWidth, height: h)
            result.append(copy)
            cursorY += h + spacing
        }

        // Content elements — layout in a responsive grid/stack
        let isWideContent = contentElements.contains { element in
            element.semanticRole == .chart || element.semanticRole == .panel
        }

        if isWideContent {
            // Cards/panels: full width, stacked
            for element in contentElements {
                var copy = element
                copy.id = UUID()
                let h = heightForRole(element.semanticRole, defaultHeight: 64)
                copy.frame = ElementFrame(x: padding, y: cursorY, width: contentWidth, height: h)
                result.append(copy)
                cursorY += h + spacing
            }
        } else {
            // Small items: 2-column grid
            let colWidth = (contentWidth - spacing) / 2
            var col = 0
            var rowY = cursorY
            var maxRowH: Double = 0

            for element in contentElements {
                var copy = element
                copy.id = UUID()
                let h = heightForRole(element.semanticRole, defaultHeight: 48)
                let x = padding + Double(col) * (colWidth + spacing)
                copy.frame = ElementFrame(x: x, y: rowY, width: colWidth, height: h)
                result.append(copy)
                maxRowH = max(maxRowH, h)

                col += 1
                if col >= 2 {
                    col = 0
                    rowY += maxRowH + spacing
                    maxRowH = 0
                }
            }
            if col > 0 {
                rowY += maxRowH + spacing
            }
            cursorY = rowY
        }

        // If content overflows, extend artboard height (already handled by Artboard rendering)
        return result
    }

    private func heightForRole(_ role: SemanticElementRole?, defaultHeight: Double) -> Double {
        switch role {
        case .chart, .chartAxis:
            return 180
        case .panel:
            return 120
        case .metricValue, .metricLabel, .metricDelta:
            return 56
        case .tableHeader:
            return 36
        case .tableCell:
            return 44
        case .buttonPrimary, .buttonSecondary:
            return 44
        case .avatar:
            return 48
        case .tag:
            return 32
        case .dateFilter:
            return 40
        case .listItem:
            return 52
        default:
            return defaultHeight
        }
    }

    // MARK: - Screen Partitioning Helpers

    private func extractScreenKeywords(from screenName: String) -> [String] {
        // Strip prefixes like "State - Screen: " or "State • "
        let cleaned = screenName
            .replacingOccurrences(of: "State - Screen:", with: "")
            .replacingOccurrences(of: "State •", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Split into meaningful words (3+ chars, not stopwords)
        let stopwords: Set<String> = ["the", "and", "for", "with", "from", "this", "that", "view", "screen", "page", "state"]
        return cleaned
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.lowercased() }
            .filter { $0.count >= 3 && !stopwords.contains($0) }
    }

    private func isSharedRole(_ role: SemanticElementRole) -> Bool {
        switch role {
        case .navigationItem, .navigationSection, .appBrand:
            return true
        default:
            return false
        }
    }

    private func elementMatchesScreen(_ element: CanvasElement, keywords: [String]) -> Bool {
        let nameLC = element.name.lowercased()
        let contentLC = (element.content ?? "").lowercased()
        let reasonLC = (element.semanticReason ?? "").lowercased()

        for keyword in keywords {
            if nameLC.contains(keyword) || contentLC.contains(keyword) || reasonLC.contains(keyword) {
                return true
            }
        }
        return false
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
