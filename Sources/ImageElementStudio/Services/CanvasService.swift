import Foundation
import SwiftUI

@MainActor
final class CanvasService: ObservableObject {

    // MARK: - Resize Handle (mirrors StudioViewModel.ResizeHandle)

    enum ResizeHandle: String, CaseIterable, Identifiable {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
        case left
        case right
        case top
        case bottom

        var id: String { rawValue }
    }

    // MARK: - BuildStep

    struct BuildStep: Identifiable {
        enum State {
            case pending
            case active
            case done
        }

        var id: String { title }
        var title: String
        var detail: String
        var state: State
    }

    // MARK: - BuildStepContext

    /// All inputs needed to compute the buildSteps array without ViewModel access.
    struct BuildStepContext {
        var selectedImage: Bool          // true if a design image is currently loaded
        var renderableElementCount: Int
        var latestScope: ProductScopeSnapshot?
        var latestBlueprint: BuildBlueprint?
        var latestDesignTokens: DesignTokenSet?
        var latestComponentSpecs: [ComponentSpec]
        var componentInstances: [ComponentInstance]
        var importLossReport: ImportLossReport?
        var latestBuildQualityReport: BuildQualityReport?
        var latestFullStackBuildSummary: FullStackBuildSummary?
        var latestEnterpriseReadinessReport: EnterpriseReadinessReport?
        var canExportBuildArtifacts: Bool
        var reviewGateStatusLine: String
        var latestBenchmarkReport: BenchmarkRunReport?
        var strategySession: StrategySession?
        var acceptedStrategySpec: StrategySpec?
        var isAnalyzing: Bool
        var strategyStageLine: String
        var designSystemStatusLine: String
        var interopStatusLine: String
        var componentSystemStatusLine: String
        var benchmarkStatusLine: String
        var fullStackStatusLine: String
        var enterpriseReadinessStatusLine: String
        var realTimeBuildTarget: String   // BuildTarget.title
        var lastRealtimeBuildPath: String?
        var overdueReviewCommentCount: Int
        var reviewGateBlockReason: String?
        var benchmarkTrendScore: BenchmarkTrendScore?
    }

    // MARK: - Supporting Types

    enum ElementAlignmentCommand {
        case left
        case centerHorizontal
        case right
        case top
        case centerVertical
        case bottom
    }

    // MARK: - buildSteps(from:)

    func buildSteps(from ctx: BuildStepContext) -> [BuildStep] {
        let hasInput = ctx.selectedImage || ctx.renderableElementCount > 1 || ctx.latestScope != nil
        let hasSemanticScope = ctx.latestScope != nil
        let hasBlueprint = ctx.latestBlueprint != nil
        let hasElements = ctx.renderableElementCount > 1
        let hasTokenizedMockups = ctx.latestDesignTokens != nil && hasElements
        let hasComponents = !ctx.latestComponentSpecs.isEmpty
        let hasComponentInstances = !ctx.componentInstances.isEmpty
        let hasInteropReport = ctx.importLossReport != nil
        let qualityReady = ctx.latestBuildQualityReport != nil
        let hasFullStackRun = ctx.latestFullStackBuildSummary != nil
        let fullStackReady = ctx.latestFullStackBuildSummary?.allTargetsPassed == true
        let enterpriseReady = ctx.latestEnterpriseReadinessReport?.status == .pass
        let hasEnterpriseReport = ctx.latestEnterpriseReadinessReport != nil
        let reviewReady = ctx.canExportBuildArtifacts
        let benchmarkReady = ctx.latestBenchmarkReport?.passed == true
        let inferredStates = ctx.latestBlueprint?.states.count ?? 0
        let ready = hasSemanticScope && hasElements && inferredStates > 0
        let buildReady = ready && ctx.canExportBuildArtifacts
        let strategyStarted = ctx.strategySession != nil || !(ctx.acceptedStrategySpec == nil && ctx.strategySession == nil)
        let strategyLocked = ctx.acceptedStrategySpec != nil

        let strategyDetail: String
        if strategyLocked {
            strategyDetail = "Spec accepted (\(Int(((ctx.acceptedStrategySpec?.confidence ?? 0) * 100).rounded()))% confidence)"
        } else if let session = ctx.strategySession {
            strategyDetail = session.isComplete
                ? "Interview complete. Finalize spec."
                : ctx.strategyStageLine
        } else {
            strategyDetail = "Start strategy interview from idea."
        }

        let realtimeDetail = ctx.lastRealtimeBuildPath == nil
            ? "Watching imports (\(ctx.realTimeBuildTarget))"
            : "Realtime scaffold synced (\(ctx.realTimeBuildTarget))"

        return [
            BuildStep(
                title: "Input Ready",
                detail: ctx.selectedImage ? "Design loaded" : (hasElements ? "Idea wireframes generated" : "Upload a design or describe your app idea"),
                state: hasInput ? .done : .pending
            ),
            BuildStep(
                title: "Strategist Interview",
                detail: strategyDetail,
                state: strategyLocked ? .done : (strategyStarted ? .active : .pending)
            ),
            BuildStep(
                title: "Token Mockups",
                detail: hasTokenizedMockups ? ctx.designSystemStatusLine : "Generate mockups from approved scope",
                state: hasTokenizedMockups ? .done : .pending
            ),
            BuildStep(
                title: "Analyze Layout",
                detail: ctx.isAnalyzing ? "Running analysis" : (hasSemanticScope ? "Analysis complete" : "Run Analyze or type your idea and send"),
                state: ctx.isAnalyzing ? .active : (hasSemanticScope ? .done : .pending)
            ),
            BuildStep(
                title: "Map Components",
                detail: hasComponents ? ctx.componentSystemStatusLine : (hasElements ? "\(ctx.renderableElementCount) elements mapped" : "Waiting for mapped elements"),
                state: hasComponents ? .done : (hasElements ? .active : .pending)
            ),
            BuildStep(
                title: "Component Instances",
                detail: hasComponentInstances ? "\(ctx.componentInstances.count) instances tracked" : "Create component instances for reusable UI",
                state: hasComponentInstances ? .done : (hasComponents ? .active : .pending)
            ),
            BuildStep(
                title: "Infer States",
                detail: hasBlueprint ? "\(inferredStates) state candidates inferred" : "Infer controls and states from detected UI",
                state: ctx.isAnalyzing ? .active : (hasBlueprint ? .done : .pending)
            ),
            BuildStep(
                title: "Interop Fidelity",
                detail: hasInteropReport ? ctx.interopStatusLine : "Import structured design assets to score fidelity",
                state: hasInteropReport ? .done : .pending
            ),
            BuildStep(
                title: "Scope Locked",
                detail: hasSemanticScope ? (ctx.latestScope?.appType ?? "Scoped") : "Semantic scope not locked yet",
                state: hasSemanticScope ? .done : .pending
            ),
            BuildStep(
                title: "Ready To Build",
                detail: buildReady ? "Use builder commands to iterate and export" : (ready ? ctx.reviewGateStatusLine : "Complete prior steps"),
                state: buildReady ? .done : .pending
            ),
            BuildStep(
                title: "Realtime Build",
                detail: realtimeDetail,
                state: ctx.lastRealtimeBuildPath != nil ? .done : .active
            ),
            BuildStep(
                title: "Quality Checks",
                detail: qualityReady ? "Smoke checks + design/code diff generated" : "Run build to produce quality report",
                state: qualityReady ? .done : .pending
            ),
            BuildStep(
                title: "Full App Run",
                detail: hasFullStackRun ? ctx.fullStackStatusLine : "Run Generate Full Stack to build all targets with quality summary",
                state: fullStackReady ? .done : (hasFullStackRun ? .active : .pending)
            ),
            BuildStep(
                title: "Enterprise Gate",
                detail: hasEnterpriseReport ? ctx.enterpriseReadinessStatusLine : "Generate full stack run to compute enterprise readiness",
                state: enterpriseReady ? .done : (hasEnterpriseReport ? .active : .pending)
            ),
            BuildStep(
                title: "Editing Benchmark",
                detail: ctx.benchmarkStatusLine,
                state: benchmarkReady ? .done : .pending
            ),
            BuildStep(
                title: "Review Approval",
                detail: ctx.reviewGateStatusLine,
                state: reviewReady ? .done : .active
            ),
        ]
    }

    // MARK: - Utility: withActiveArtboard

    /// Applies `update` to the artboard at `activeArtboardIndex`, then runs `reconcileComponentModelIntegrity`
    /// and calls `regenerateJSON`. This is a pure-inout version that does not call any ViewModel closures.
    func withActiveArtboard(
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        _ update: (inout Artboard) -> Void
    ) {
        guard let index = activeArtboardIndex else { return }
        update(&artboards[index])
    }

    // MARK: - Utility: reconcileComponentModelIntegrity

    /// Removes component instances and specs whose element IDs no longer exist in any artboard.
    func reconcileComponentModelIntegrity(
        artboards: inout [Artboard],
        latestComponentSpecs: inout [ComponentSpec],
        componentInstances: inout [ComponentInstance]
    ) {
        let validElementIDs = Set(artboards.flatMap { $0.elements.map(\.id) })
        componentInstances = componentInstances.compactMap { instance in
            var copy = instance
            copy.elementIDs = copy.elementIDs.filter { validElementIDs.contains($0) }
            return copy.elementIDs.isEmpty ? nil : copy
        }
        latestComponentSpecs = latestComponentSpecs.compactMap { spec in
            var copy = spec
            copy.elementIDs = copy.elementIDs.filter { validElementIDs.contains($0) }
            copy.instanceElementIDs = copy.instanceElementIDs?.filter { validElementIDs.contains($0) }
            return copy.elementIDs.isEmpty ? nil : copy
        }
    }

    // MARK: - Utility: recordActiveArtboardSnapshot

    /// Records a snapshot of the active artboard into the memory store and returns the updated ProjectMemory.
    func recordActiveArtboardSnapshot(
        reason: String,
        artboard: Artboard?,
        memoryStore: ProjectMemoryStore,
        imageName: String?,
        scope: ProductScopeSnapshot?
    ) -> ProjectMemory {
        guard let artboard else { return memoryStore.memory }
        return memoryStore.recordArtboardSnapshot(
            artboard: artboard,
            reason: reason,
            imageName: imageName,
            scope: scope
        )
    }

    // MARK: - Utility: snap

    /// Snaps a value to the nearest grid unit.
    func snap(value: Double, gridSize: Double) -> Double {
        let unit = max(Constants.Canvas.minimumGridUnit, gridSize)
        return (value / unit).rounded() * unit
    }

    // MARK: - Element Manipulation

    func distributeSelectedElementsHorizontally(
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        selectedElementIDs: Set<UUID>,
        canDistribute: Bool
    ) {
        guard canDistribute else { return }
        guard let index = activeArtboardIndex else { return }
        let ids = selectedElementIDs
        let indices = artboards[index].elements.indices.filter { ids.contains(artboards[index].elements[$0].id) }
        guard indices.count >= 3 else { return }

        let sortedIndices = indices.sorted { artboards[index].elements[$0].frame.minX < artboards[index].elements[$1].frame.minX }
        let totalWidth = sortedIndices.reduce(0.0) { $0 + artboards[index].elements[$1].frame.width }
        guard let first = sortedIndices.first, let last = sortedIndices.last else { return }
        let start = artboards[index].elements[first].frame.minX
        let end = artboards[index].elements[last].frame.maxX
        let available = max(0, end - start - totalWidth)
        let gap = available / Double(max(1, sortedIndices.count - 1))

        var cursor = start
        for i in sortedIndices {
            artboards[index].elements[i].frame.x = max(0, min(cursor, Double(artboards[index].width) - artboards[index].elements[i].frame.width))
            cursor += artboards[index].elements[i].frame.width + gap
        }
    }

    func distributeSelectedElementsVertically(
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        selectedElementIDs: Set<UUID>,
        canDistribute: Bool
    ) {
        guard canDistribute else { return }
        guard let index = activeArtboardIndex else { return }
        let ids = selectedElementIDs
        let indices = artboards[index].elements.indices.filter { ids.contains(artboards[index].elements[$0].id) }
        guard indices.count >= 3 else { return }

        let sortedIndices = indices.sorted { artboards[index].elements[$0].frame.minY < artboards[index].elements[$1].frame.minY }
        let totalHeight = sortedIndices.reduce(0.0) { $0 + artboards[index].elements[$1].frame.height }
        guard let first = sortedIndices.first, let last = sortedIndices.last else { return }
        let start = artboards[index].elements[first].frame.minY
        let end = artboards[index].elements[last].frame.maxY
        let available = max(0, end - start - totalHeight)
        let gap = available / Double(max(1, sortedIndices.count - 1))

        var cursor = start
        for i in sortedIndices {
            artboards[index].elements[i].frame.y = max(0, min(cursor, Double(artboards[index].height) - artboards[index].elements[i].frame.height))
            cursor += artboards[index].elements[i].frame.height + gap
        }
    }

    func spaceSelectedElementsHorizontally(
        gap: Double,
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        selectedElementIDs: Set<UUID>
    ) {
        guard selectedElementIDs.count >= 2 else { return }
        guard let index = activeArtboardIndex else { return }
        let safeGap = max(0, gap)
        let ids = selectedElementIDs
        let sortedIndices = artboards[index].elements.indices
            .filter { ids.contains(artboards[index].elements[$0].id) }
            .sorted { artboards[index].elements[$0].frame.minX < artboards[index].elements[$1].frame.minX }

        guard let first = sortedIndices.first else { return }
        var cursor = artboards[index].elements[first].frame.minX
        for i in sortedIndices {
            artboards[index].elements[i].frame.x = max(0, min(cursor, Double(artboards[index].width) - artboards[index].elements[i].frame.width))
            cursor += artboards[index].elements[i].frame.width + safeGap
        }
    }

    func spaceSelectedElementsVertically(
        gap: Double,
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        selectedElementIDs: Set<UUID>
    ) {
        guard selectedElementIDs.count >= 2 else { return }
        guard let index = activeArtboardIndex else { return }
        let safeGap = max(0, gap)
        let ids = selectedElementIDs
        let sortedIndices = artboards[index].elements.indices
            .filter { ids.contains(artboards[index].elements[$0].id) }
            .sorted { artboards[index].elements[$0].frame.minY < artboards[index].elements[$1].frame.minY }

        guard let first = sortedIndices.first else { return }
        var cursor = artboards[index].elements[first].frame.minY
        for i in sortedIndices {
            artboards[index].elements[i].frame.y = max(0, min(cursor, Double(artboards[index].height) - artboards[index].elements[i].frame.height))
            cursor += artboards[index].elements[i].frame.height + safeGap
        }
    }

    func toggleConstraint(
        _ pin: ConstraintPin,
        enabled: Bool,
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        selectedElementIDs: Set<UUID>
    ) {
        guard !selectedElementIDs.isEmpty else { return }
        guard let index = activeArtboardIndex else { return }
        for i in artboards[index].elements.indices where selectedElementIDs.contains(artboards[index].elements[i].id) {
            var constraints = Set(artboards[index].elements[i].constraints)
            if enabled {
                constraints.insert(pin)
            } else {
                constraints.remove(pin)
            }
            artboards[index].elements[i].constraints = constraints.sorted { $0.rawValue < $1.rawValue }
        }
    }

    func hasConstraint(
        _ pin: ConstraintPin,
        selectedElements: [CanvasElement]
    ) -> Bool {
        guard !selectedElements.isEmpty else { return false }
        return selectedElements.allSatisfy { $0.constraints.contains(pin) }
    }

    func resizeSelectedElements(
        handle: ResizeHandle,
        deltaX: Double,
        deltaY: Double,
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        selectedElementIDs: Set<UUID>
    ) {
        guard !selectedElementIDs.isEmpty else { return }
        guard let index = activeArtboardIndex else { return }
        for i in artboards[index].elements.indices where selectedElementIDs.contains(artboards[index].elements[i].id) {
            var element = artboards[index].elements[i]
            let minSize = Constants.Canvas.minimumElementSize

            switch handle {
            case .right:
                element.frame.width = max(minSize, element.frame.width + deltaX)
            case .left:
                let nextWidth = max(minSize, element.frame.width - deltaX)
                let dx = element.frame.width - nextWidth
                element.frame.width = nextWidth
                element.frame.x += dx
            case .bottom:
                element.frame.height = max(minSize, element.frame.height + deltaY)
            case .top:
                let nextHeight = max(minSize, element.frame.height - deltaY)
                let dy = element.frame.height - nextHeight
                element.frame.height = nextHeight
                element.frame.y += dy
            case .topLeft:
                let nextWidth = max(minSize, element.frame.width - deltaX)
                let nextHeight = max(minSize, element.frame.height - deltaY)
                element.frame.x += element.frame.width - nextWidth
                element.frame.y += element.frame.height - nextHeight
                element.frame.width = nextWidth
                element.frame.height = nextHeight
            case .topRight:
                let oldHeight = element.frame.height
                let nextHeight = max(minSize, element.frame.height - deltaY)
                element.frame.height = nextHeight
                element.frame.y += oldHeight - nextHeight
                element.frame.width = max(minSize, element.frame.width + deltaX)
            case .bottomLeft:
                let nextWidth = max(minSize, element.frame.width - deltaX)
                element.frame.x += element.frame.width - nextWidth
                element.frame.width = nextWidth
                element.frame.height = max(minSize, element.frame.height + deltaY)
            case .bottomRight:
                element.frame.width = max(minSize, element.frame.width + deltaX)
                element.frame.height = max(minSize, element.frame.height + deltaY)
            }

            element.frame.x = max(0, min(element.frame.x, Double(artboards[index].width) - element.frame.width))
            element.frame.y = max(0, min(element.frame.y, Double(artboards[index].height) - element.frame.height))
            artboards[index].elements[i] = element
        }
    }

    func rotateSelectedElements(
        by deltaDegrees: Double,
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        selectedElementIDs: Set<UUID>
    ) {
        guard !selectedElementIDs.isEmpty else { return }
        guard let index = activeArtboardIndex else { return }
        for i in artboards[index].elements.indices where selectedElementIDs.contains(artboards[index].elements[i].id) {
            var element = artboards[index].elements[i]
            let next = element.rotationDegrees + deltaDegrees
            element.rotationDegrees = (next.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
            artboards[index].elements[i] = element
        }
    }

    func nudgeSelection(
        deltaX: Double,
        deltaY: Double,
        snapToGrid: Bool,
        gridSize: Double,
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        selectedElementIDs: Set<UUID>
    ) {
        guard !selectedElementIDs.isEmpty else { return }
        guard let index = activeArtboardIndex else { return }
        for i in artboards[index].elements.indices where selectedElementIDs.contains(artboards[index].elements[i].id) {
            var element = artboards[index].elements[i]

            let maxX = Double(artboards[index].width) - element.frame.width
            let maxY = Double(artboards[index].height) - element.frame.height
            var nextX = min(max(0, element.frame.x + deltaX), max(0, maxX))
            var nextY = min(max(0, element.frame.y + deltaY), max(0, maxY))

            if snapToGrid {
                nextX = snap(value: nextX, gridSize: gridSize)
                nextY = snap(value: nextY, gridSize: gridSize)
            }

            element.frame.x = min(max(0, nextX), max(0, maxX))
            element.frame.y = min(max(0, nextY), max(0, maxY))
            artboards[index].elements[i] = element
        }
    }

    // MARK: - Alignment (6 functions, pure inout)

    func alignSelectedElementLeft(
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        selectedElementIDs: Set<UUID>
    ) {
        alignSelectedElementPure(.left, artboards: &artboards, activeArtboardIndex: activeArtboardIndex, selectedElementIDs: selectedElementIDs)
    }

    func alignSelectedElementHorizontalCenter(
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        selectedElementIDs: Set<UUID>
    ) {
        alignSelectedElementPure(.centerHorizontal, artboards: &artboards, activeArtboardIndex: activeArtboardIndex, selectedElementIDs: selectedElementIDs)
    }

    func alignSelectedElementRight(
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        selectedElementIDs: Set<UUID>
    ) {
        alignSelectedElementPure(.right, artboards: &artboards, activeArtboardIndex: activeArtboardIndex, selectedElementIDs: selectedElementIDs)
    }

    func alignSelectedElementTop(
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        selectedElementIDs: Set<UUID>
    ) {
        alignSelectedElementPure(.top, artboards: &artboards, activeArtboardIndex: activeArtboardIndex, selectedElementIDs: selectedElementIDs)
    }

    func alignSelectedElementVerticalCenter(
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        selectedElementIDs: Set<UUID>
    ) {
        alignSelectedElementPure(.centerVertical, artboards: &artboards, activeArtboardIndex: activeArtboardIndex, selectedElementIDs: selectedElementIDs)
    }

    func alignSelectedElementBottom(
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        selectedElementIDs: Set<UUID>
    ) {
        alignSelectedElementPure(.bottom, artboards: &artboards, activeArtboardIndex: activeArtboardIndex, selectedElementIDs: selectedElementIDs)
    }

    // MARK: - Private Helpers

    /// Pure inout version of alignment that does not call any closures.
    private func alignSelectedElementPure(
        _ alignment: ElementAlignmentCommand,
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        selectedElementIDs: Set<UUID>
    ) {
        guard !selectedElementIDs.isEmpty else { return }
        guard let boardIndex = activeArtboardIndex else { return }

        for index in artboards[boardIndex].elements.indices where selectedElementIDs.contains(artboards[boardIndex].elements[index].id) {
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

            artboards[boardIndex].elements[index] = element
        }
    }
}
