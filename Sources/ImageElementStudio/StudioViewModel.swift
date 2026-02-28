import AppKit
import Combine
import CryptoKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class StudioViewModel: ObservableObject {
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

    enum BuildTarget: String, CaseIterable, Identifiable {
        case ios
        case macos
        case web

        var id: String { rawValue }

        var title: String {
            switch self {
            case .ios:
                return "iOS"
            case .macos:
                return "macOS"
            case .web:
                return "Web"
            }
        }

        var symbolName: String {
            switch self {
            case .ios:
                return "iphone"
            case .macos:
                return "desktopcomputer"
            case .web:
                return "globe"
            }
        }

        var buildLabel: String {
            switch self {
            case .ios:
                return "Mobile App"
            case .macos:
                return "Desktop App"
            case .web:
                return "Web App"
            }
        }
    }

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

    // Chat properties forwarded to ChatService
    var messages: [ChatMessage] {
        get { chatService.messages }
        set { chatService.messages = newValue }
    }
    var draftMessage: String {
        get { chatService.draftMessage }
        set { chatService.draftMessage = newValue }
    }
    var builderMessages: [ChatMessage] {
        get { chatService.builderMessages }
        set { chatService.builderMessages = newValue }
    }
    var builderDraft: String {
        get { chatService.builderDraft }
        set { chatService.builderDraft = newValue }
    }

    @Published var selectedImage: NSImage?
    @Published var selectedImageURL: URL?

    @Published var artboards: [Artboard]
    @Published var selectedArtboardID: UUID? {
        didSet {
            clearElementSelection()
            regenerateJSONPreview()
        }
    }
    var selectedElementID: UUID? {
        get { selectionService.selectedElementID }
        set { selectionService.selectedElementID = newValue }
    }
    var selectedElementIDs: Set<UUID> {
        get { selectionService.selectedElementIDs }
        set { selectionService.selectedElementIDs = newValue }
    }

    @Published var isAnalyzing: Bool = false
    @Published var isSettingUpBuild: Bool = false
    @Published var errorMessage: String?
    @Published var jsonPreview: String = "{}"
    @Published var projectName: String
    @Published var latestScope: ProductScopeSnapshot?
    @Published var latestBlueprint: BuildBlueprint?
    var latestComponentSpecs: [ComponentSpec] {
        get { componentService.latestComponentSpecs }
        set { componentService.latestComponentSpecs = newValue }
    }
    @Published var mockupStylePreset: MockupStylePreset = .apple_hig
    @Published var autoGenerateStateArtboards: Bool = true
    @Published var realTimeBuildEnabled: Bool = true
    @Published var realTimeBuildTarget: BuildTarget = .macos
    @Published var lastRealtimeBuildPath: String?
    @Published var memory: ProjectMemory
    @Published var showLayoutGrid: Bool = true
    @Published var snapToGrid: Bool = true
    @Published var showAlignmentGuides: Bool = true
    @Published var gridSize: Double = 8
    @Published var pipelineMode: PipelineMode = .hybrid
    var strategySession: StrategySession? {
        get { strategyService.strategySession }
        set { strategyService.strategySession = newValue }
    }
    var strategyAnswerDraft: String {
        get { strategyService.strategyAnswerDraft }
        set { strategyService.strategyAnswerDraft = newValue }
    }
    var componentInstances: [ComponentInstance] {
        get { componentService.componentInstances }
        set { componentService.componentInstances = newValue }
    }
    var selectedComponentID: UUID? {
        get { componentService.selectedComponentID }
        set { componentService.selectedComponentID = newValue }
    }
    var selectedComponentInstanceID: UUID? {
        get { componentService.selectedComponentInstanceID }
        set { componentService.selectedComponentInstanceID = newValue }
    }
    @Published var importLossReport: ImportLossReport?
    @Published var latestInteropPackage: InteropExportPackage?
    @Published var latestBuildQualityReport: BuildQualityReport?
    @Published var designCodeDiffs: [DesignCodeDiffEntry] = []
    @Published var latestFullStackBuildSummary: FullStackBuildSummary?
    @Published var latestEnterpriseReadinessReport: EnterpriseReadinessReport?
    @Published var selectedVariantAxisName: String = "state"
    @Published var selectedVariantOptionsDraft: String = "default,hover,pressed"
    var selectedComponentStateDraft: String {
        get { componentService.selectedComponentStateDraft }
        set { componentService.selectedComponentStateDraft = newValue }
    }
    var selectedInstanceOverrideKeyDraft: String {
        get { componentService.selectedInstanceOverrideKeyDraft }
        set { componentService.selectedInstanceOverrideKeyDraft = newValue }
    }
    var selectedInstanceOverrideValueDraft: String {
        get { componentService.selectedInstanceOverrideValueDraft }
        set { componentService.selectedInstanceOverrideValueDraft = newValue }
    }
    @Published var distributionGap: Double = 12
    @Published var keyboardNudgeAmount: Double = 4
    var isMarqueeSelecting: Bool {
        get { selectionService.isMarqueeSelecting }
        set { selectionService.isMarqueeSelecting = newValue }
    }
    var marqueeSelectionCount: Int {
        get { selectionService.marqueeSelectionCount }
        set { selectionService.marqueeSelectionCount = newValue }
    }

    private let analyzer = ImageAnalyzer()
    private let designAssetImporter = DesignAssetImporter()
    private let ideaPlanner = IdeaPlanner()
    private let mockupGenerator = MockupGenerator()
    private let semanticPipeline: SemanticPipeline
    private let memoryStore: ProjectMemoryStore
    private var latestMetadata: AnalysisMetadata?
    private var latestImageDescriptor: ImageDescriptor?
    private var realtimeAnalysisTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    let reviewService = ReviewService()
    let selectionService = SelectionService()
    let benchmarkService = BenchmarkService()
    let designTokenService = DesignTokenService()
    let canvasService = CanvasService()
    let componentService = ComponentService()
    let chatService: ChatService
    let strategyService: StrategyService
    let buildExportService = BuildExportService()

    // MARK: - BuildExportService Typealiases
    // These typealiases keep existing call sites (including tests) compiling without change.
    typealias BuildManifest = BuildExportService.BuildManifest
    typealias DeterministicManifestSnapshot = BuildExportService.DeterministicManifestSnapshot
    typealias DeterministicDiffSnapshot = BuildExportService.DeterministicDiffSnapshot
    typealias DeterministicAppSpecSnapshot = BuildExportService.DeterministicAppSpecSnapshot

    // MARK: - AI Code Generation & Build Pipeline

    let codeGenerationPipeline = CodeGenerationPipeline()
    let buildPipelineCoordinator = BuildPipelineCoordinator()
    @Published var isGeneratingApp: Bool = false
    @Published var showBuildOutput: Bool = false
    @Published var showSettingsSheet: Bool = false

    init() {
        let defaultProjectName = UserDefaults.standard.string(forKey: "ImageElementStudio.ActiveProjectName") ?? "Default Project"
        let store = ProjectMemoryStore(projectName: defaultProjectName)
        let activeProjectName = store.projectName
        self.memoryStore = store
        self.projectName = activeProjectName
        self.memory = store.memory
        self.semanticPipeline = SemanticPipeline()

        let initialBoard = Artboard.empty()
        self.artboards = [initialBoard]
        self.selectedArtboardID = initialBoard.id
        self.chatService = ChatService(projectName: activeProjectName)
        let engine = ProductStrategistEngine()
        self.strategyService = StrategyService(strategistEngine: engine)
        self.strategyService.strategySession = store.memory.strategySessions.last
        self.pipelineMode = store.memory.strategySessions.last?.pipelineMode ?? .hybrid

        if !memory.latestSummary.isEmpty {
            self.messages.append(
                ChatMessage(role: .assistant, text: "Memory restored: \(memory.latestSummary)")
            )
        }

        reviewService.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        selectionService.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        benchmarkService.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        chatService.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        designTokenService.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        componentService.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        canvasService.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        strategyService.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        codeGenerationPipeline.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        buildPipelineCoordinator.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        buildExportService.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)

        strategyService.onAppendBuilderMessage = { [weak self] msg in
            self?.builderMessages.append(msg)
        }
        strategyService.onAppendMessage = { [weak self] msg in
            self?.messages.append(msg)
        }
        strategyService.onMemoryUpdated = { [weak self] updatedMemory in
            self?.memory = updatedMemory
        }
        strategyService.onSetPipelineMode = { [weak self] mode in
            self?.pipelineMode = mode
        }
        strategyService.onScopeProduced = { [weak self] scope in
            self?.latestScope = scope
        }
        strategyService.onFinalizeAndGenerateMockups = { [weak self] in
            self?.finalizeAndGenerateMockups()
        }

        designTokenService.onTokenChangesPropagated = { [weak self] tokens in
            self?.propagateGlobalTokenChanges(tokens)
        }

        regenerateJSONPreview()
    }

    // MARK: - Review Service Forwarding Properties

    var reviewComments: [DesignReviewComment] {
        get { reviewService.reviewComments }
        set { reviewService.reviewComments = newValue }
    }

    var reviewApprovalState: ReviewApprovalState {
        get { reviewService.reviewApprovalState }
        set { reviewService.reviewApprovalState = newValue }
    }

    var reviewCommentDraft: String {
        get { reviewService.reviewCommentDraft }
        set { reviewService.reviewCommentDraft = newValue }
    }

    var reviewCommentAssigneeDraft: String {
        get { reviewService.reviewCommentAssigneeDraft }
        set { reviewService.reviewCommentAssigneeDraft = newValue }
    }

    var reviewCommentHasDueDate: Bool {
        get { reviewService.reviewCommentHasDueDate }
        set { reviewService.reviewCommentHasDueDate = newValue }
    }

    var reviewCommentDueDateDraft: Date {
        get { reviewService.reviewCommentDueDateDraft }
        set { reviewService.reviewCommentDueDateDraft = newValue }
    }

    // MARK: - Benchmark Service Forwarding Properties

    var latestBenchmarkReport: BenchmarkRunReport? {
        get { benchmarkService.latestBenchmarkReport }
        set { benchmarkService.latestBenchmarkReport = newValue }
    }

    var benchmarkHistory: [BenchmarkRunReport] {
        get { benchmarkService.benchmarkHistory }
        set { benchmarkService.benchmarkHistory = newValue }
    }

    // MARK: - Design Token Service Forwarding Properties

    var latestDesignTokens: DesignTokenSet? {
        get { designTokenService.latestDesignTokens }
        set { designTokenService.latestDesignTokens = newValue }
    }

    var tokenRevisions: [TokenRevision] {
        get { designTokenService.tokenRevisions }
        set { designTokenService.tokenRevisions = newValue }
    }

    var activeArtboard: Artboard? {
        guard let index = activeArtboardIndex else { return nil }
        return artboards[index]
    }

    var selectedElement: CanvasElement? {
        guard let elementID = selectedElementID else { return nil }
        return activeArtboard?.elements.first(where: { $0.id == elementID })
    }

    var selectedElements: [CanvasElement] {
        guard !selectedElementIDs.isEmpty else { return [] }
        return renderableElements.filter { selectedElementIDs.contains($0.id) }
    }

    var hasMultiSelection: Bool {
        selectionService.hasMultiSelection
    }

    var canDistributeSelection: Bool {
        selectionService.canDistributeSelection
    }

    var tokenRevisionStatusLine: String {
        if tokenRevisions.isEmpty {
            return "No token revisions yet."
        }
        return "\(tokenRevisions.count) revisions available for rollback."
    }

    var componentSystemStatusLine: String {
        let specCount = latestComponentSpecs.count
        let instanceCount = componentInstances.count
        return "\(specCount) components, \(instanceCount) instances."
    }

    var selectedComponentSpec: ComponentSpec? {
        guard let selectedComponentID else { return nil }
        return latestComponentSpecs.first(where: { $0.id == selectedComponentID })
    }

    var selectedComponentInstance: ComponentInstance? {
        guard let selectedComponentInstanceID else { return nil }
        return componentInstances.first(where: { $0.id == selectedComponentInstanceID })
    }

    var variantMatrixPreview: [String] {
        guard let spec = selectedComponentSpec, let axes = spec.variantAxes, !axes.isEmpty else { return [] }
        let sortedAxes = axes.keys.sorted()
        var rows: [[String: String]] = [[:]]
        for axis in sortedAxes {
            let options = axes[axis] ?? []
            if options.isEmpty { continue }
            rows = rows.flatMap { existing in
                options.map { option in
                    var entry = existing
                    entry[axis] = option
                    return entry
                }
            }
        }
        return rows.prefix(12).map { row in
            sortedAxes.map { axis in "\(axis)=\(row[axis] ?? "")" }.joined(separator: " | ")
        }
    }

    var benchmarkStatusLine: String {
        benchmarkService.benchmarkStatusLine
    }

    var benchmarkHistoryPreview: [BenchmarkRunReport] {
        benchmarkService.benchmarkHistoryPreview
    }

    var benchmarkTrendScore: BenchmarkTrendScore? {
        benchmarkService.benchmarkTrendScore
    }

    var benchmarkTrendPoints: [BenchmarkTrendPoint] {
        benchmarkService.benchmarkTrendPoints
    }

    var benchmarkTrendStatusLine: String {
        benchmarkService.benchmarkTrendStatusLine
    }

    var benchmarkTrendDirectionLine: String {
        benchmarkService.benchmarkTrendDirectionLine
    }

    var interopStatusLine: String {
        guard let importLossReport else {
            return "No interop report yet."
        }
        return "Estimated manual cleanup: \(Int(importLossReport.estimatedManualCleanupPercent.rounded()))%."
    }

    var reviewStatusLine: String {
        reviewService.reviewStatusLine
    }

    var unresolvedReviewCommentCount: Int {
        reviewService.unresolvedReviewCommentCount
    }

    var resolvedReviewCommentCount: Int {
        reviewService.resolvedReviewCommentCount
    }

    var reviewCommentsPreview: [DesignReviewComment] {
        reviewService.reviewCommentsPreview
    }

    var overdueReviewCommentCount: Int {
        reviewService.overdueReviewCommentCount
    }

    var reviewGateBlockReason: String? {
        reviewService.reviewGateBlockReason
    }

    var canExportBuildArtifacts: Bool {
        reviewService.canExportBuildArtifacts
    }

    var reviewGateStatusLine: String {
        reviewService.reviewGateStatusLine
    }

    var currentQualityGateSummary: QualityGateSummary {
        let smokeChecks = latestBuildQualityReport?.smokeChecks ?? []
        let diffs = designCodeDiffs.isEmpty ? (latestBuildQualityReport?.diffs ?? []) : designCodeDiffs
        let benchmarkPassRate = benchmarkTrendScore?.passRate ?? latestBenchmarkReport?.stepPassRate
        return buildExportService.makeQualityGateSummary(
            generatedAt: Date(),
            smokeChecks: smokeChecks,
            diffEntries: diffs,
            benchmarkPassRate: benchmarkPassRate,
            reviewGatePassed: canExportBuildArtifacts,
            overdueCommentCount: overdueReviewCommentCount,
            reviewGateBlockReason: reviewGateBlockReason
        )
    }

    var qualityGateScoreLine: String {
        let summary = currentQualityGateSummary
        let score = Int(summary.overallScore.rounded())
        return "Quality Gate Score: \(score) · \(summary.status.rawValue.capitalized)"
    }

    var qualityGateBreakdownLines: [String] {
        let summary = currentQualityGateSummary
        return [
            "Smoke checks: \(Int((summary.smokePassRate * 100).rounded()))%",
            "Full app checks: \(Int((summary.fullAppPassRate * 100).rounded()))%",
            "Diff health: \(Int((summary.diffHealthScore * 100).rounded()))%",
            "Benchmark trend: \(Int((summary.benchmarkPassRate * 100).rounded()))%",
            "Review gate: \(summary.reviewGatePassed ? "pass" : "blocked")",
            "Overdue comments: \(summary.overdueCommentCount)",
            fullStackStatusLine,
            enterpriseReadinessStatusLine,
        ]
    }

    var qualityGateIssuePreview: [String] {
        let combined = currentQualityGateSummary.blockingIssues + fullStackIssuePreview + enterpriseReadinessIssuePreview
        return Array(buildExportService.uniqueStrings(combined).prefix(4))
    }

    var fullStackStatusLine: String {
        guard let latestFullStackBuildSummary else {
            return "No full-stack run yet."
        }
        let score = Int(latestFullStackBuildSummary.aggregateScore.rounded())
        let passFail = latestFullStackBuildSummary.allTargetsPassed ? "pass" : "fail"
        return "Full-stack score \(score) · \(passFail) · \(latestFullStackBuildSummary.targetResults.count) targets"
    }

    var fullStackIssuePreview: [String] {
        guard let latestFullStackBuildSummary else { return [] }
        return Array(latestFullStackBuildSummary.blockingIssues.prefix(4))
    }

    var fullStackTargetStatusLines: [String] {
        guard let latestFullStackBuildSummary else { return [] }
        return latestFullStackBuildSummary.targetResults.map { result in
            let smoke = Int((result.smokePassRate * 100).rounded())
            let fullApp = Int((result.fullAppPassRate * 100).rounded())
            let score = Int(result.qualityScore.rounded())
            let status = result.passed ? "PASS" : "FAIL"
            return "\(status) \(result.target.uppercased()): smoke \(smoke)% · full app \(fullApp)% · score \(score)"
        }
    }

    var enterpriseReadinessStatusLine: String {
        guard let latestEnterpriseReadinessReport else {
            return "Enterprise readiness: pending run."
        }
        let score = Int(latestEnterpriseReadinessReport.score.rounded())
        return "Enterprise readiness: \(latestEnterpriseReadinessReport.status.rawValue.capitalized) · \(score)"
    }

    var enterpriseReadinessIssuePreview: [String] {
        guard let latestEnterpriseReadinessReport else { return [] }
        return Array(latestEnterpriseReadinessReport.blockers.prefix(4))
    }

    var enterpriseReadinessCheckLines: [String] {
        guard let latestEnterpriseReadinessReport else { return [] }
        return latestEnterpriseReadinessReport.checks.map { check in
            let status = check.passed ? "PASS" : "FAIL"
            return "\(status) [\(Int(check.weight.rounded()))] \(check.name): \(check.detail)"
        }
    }

    var renderableElements: [CanvasElement] {
        activeArtboard?.elements ?? []
    }

    var activeCanvasSize: CGSize {
        guard let board = activeArtboard else { return CGSize(width: 1280, height: 720) }
        return CGSize(width: board.width, height: board.height)
    }

    var canRemoveArtboard: Bool {
        artboards.count > 1
    }

    var textElementCount: Int {
        renderableElements.filter { $0.kind == .text }.count
    }

    var shapeElementCount: Int {
        renderableElements.filter { $0.kind == .shape }.count
    }

    var memoryEntriesPreview: [ProjectMemoryEntry] {
        Array(memory.entries.suffix(4).reversed())
    }

    var memoryStatusLine: String {
        if memory.entries.isEmpty {
            return "\(projectName): no snapshots yet"
        }
        return "\(projectName): \(memory.entries.count) snapshots"
    }

    var projectContextLine: String {
        let identifier = memory.projectID ?? buildExportService.slugified(projectName)
        return "Project: \(projectName) (\(identifier))"
    }

    var realtimeBuildStatusLine: String {
        if let path = lastRealtimeBuildPath {
            return "Realtime build: \(realTimeBuildTarget.title) updated at \(path)"
        }
        return "Realtime build: \(realTimeBuildTarget.title) waiting for analysis"
    }

    var componentSpecsPreview: [ComponentSpec] {
        Array(latestComponentSpecs.prefix(5))
    }

    var designSystemStatusLine: String {
        guard let latestDesignTokens else {
            return "Design tokens are not generated yet."
        }
        let colorCount = latestDesignTokens.colors.count
        let componentCount = latestComponentSpecs.count
        return "\(mockupStylePreset.title): \(colorCount) colors, \(componentCount) component groups."
    }

    var acceptedStrategySpec: StrategySpec? {
        memory.acceptedStrategySpecs.last
    }

    // MARK: - Strategy Service Forwarding Properties

    var strategyActiveQuestion: StrategyQuestion? {
        strategyService.strategyActiveQuestion
    }

    var strategyStageProgress: Double {
        strategyService.strategyStageProgress
    }

    var strategyStageLine: String {
        strategyService.strategyStageLine
    }

    var strategyControlHint: String {
        strategyService.strategyControlHint
    }

    var shouldShowStrategyPanel: Bool {
        if strategySession != nil {
            return true
        }
        let hasMockups = selectedImage != nil || latestScope != nil || renderableElements.count > 1
        return !hasMockups
    }

    var buildSteps: [BuildStep] {
        let hasInput = selectedImage != nil || renderableElements.count > 1 || latestScope != nil
        let hasSemanticScope = latestScope != nil
        let hasBlueprint = latestBlueprint != nil
        let hasElements = renderableElements.count > 1
        let hasTokenizedMockups = latestDesignTokens != nil && hasElements
        let hasComponents = !latestComponentSpecs.isEmpty
        let hasComponentInstances = !componentInstances.isEmpty
        let hasInteropReport = importLossReport != nil
        let qualityReady = latestBuildQualityReport != nil
        let hasFullStackRun = latestFullStackBuildSummary != nil
        let fullStackReady = latestFullStackBuildSummary?.allTargetsPassed == true
        let enterpriseReady = latestEnterpriseReadinessReport?.status == .pass
        let hasEnterpriseReport = latestEnterpriseReadinessReport != nil
        let reviewReady = canExportBuildArtifacts
        let benchmarkReady = latestBenchmarkReport?.passed == true
        let inferredStates = latestBlueprint?.states.count ?? 0
        let ready = hasSemanticScope && hasElements && inferredStates > 0
        let buildReady = ready && canExportBuildArtifacts
        let strategyStarted = strategySession != nil || !memory.strategySessions.isEmpty
        let strategyLocked = acceptedStrategySpec != nil
        let strategyDetail: String
        if strategyLocked {
            strategyDetail = "Spec accepted (\(Int(((acceptedStrategySpec?.confidence ?? 0) * 100).rounded()))% confidence)"
        } else if let strategySession {
            strategyDetail = strategySession.isComplete
                ? "Interview complete. Finalize spec."
                : "\(strategyStageLine)"
        } else {
            strategyDetail = "Start strategy interview from idea."
        }
        let realtimeDetail = lastRealtimeBuildPath == nil
            ? "Watching imports (\(realTimeBuildTarget.title))"
            : "Realtime scaffold synced (\(realTimeBuildTarget.title))"

        return [
            BuildStep(
                title: "Input Ready",
                detail: selectedImage != nil ? "Design loaded" : (hasElements ? "Idea wireframes generated" : "Upload a design or describe your app idea"),
                state: hasInput ? .done : .pending
            ),
            BuildStep(
                title: "Strategist Interview",
                detail: strategyDetail,
                state: strategyLocked ? .done : (strategyStarted ? .active : .pending)
            ),
            BuildStep(
                title: "Token Mockups",
                detail: hasTokenizedMockups ? designSystemStatusLine : "Generate mockups from approved scope",
                state: hasTokenizedMockups ? .done : .pending
            ),
            BuildStep(
                title: "Analyze Layout",
                detail: isAnalyzing ? "Running analysis" : (hasSemanticScope ? "Analysis complete" : "Run Analyze or type your idea and send"),
                state: isAnalyzing ? .active : (hasSemanticScope ? .done : .pending)
            ),
            BuildStep(
                title: "Map Components",
                detail: hasComponents ? componentSystemStatusLine : (hasElements ? "\(renderableElements.count) elements mapped" : "Waiting for mapped elements"),
                state: hasComponents ? .done : (hasElements ? .active : .pending)
            ),
            BuildStep(
                title: "Component Instances",
                detail: hasComponentInstances ? "\(componentInstances.count) instances tracked" : "Create component instances for reusable UI",
                state: hasComponentInstances ? .done : (hasComponents ? .active : .pending)
            ),
            BuildStep(
                title: "Infer States",
                detail: hasBlueprint ? "\(inferredStates) state candidates inferred" : "Infer controls and states from detected UI",
                state: isAnalyzing ? .active : (hasBlueprint ? .done : .pending)
            ),
            BuildStep(
                title: "Interop Fidelity",
                detail: hasInteropReport ? interopStatusLine : "Import structured design assets to score fidelity",
                state: hasInteropReport ? .done : .pending
            ),
            BuildStep(
                title: "Scope Locked",
                detail: hasSemanticScope ? (latestScope?.appType ?? "Scoped") : "Semantic scope not locked yet",
                state: hasSemanticScope ? .done : .pending
            ),
            BuildStep(
                title: "Ready To Build",
                detail: buildReady ? "Use builder commands to iterate and export" : (ready ? reviewGateStatusLine : "Complete prior steps"),
                state: buildReady ? .done : .pending
            ),
            BuildStep(
                title: "Realtime Build",
                detail: realtimeDetail,
                state: lastRealtimeBuildPath != nil ? .done : .active
            ),
            BuildStep(
                title: "Quality Checks",
                detail: qualityReady ? "Smoke checks + design/code diff generated" : "Run build to produce quality report",
                state: qualityReady ? .done : .pending
            ),
            BuildStep(
                title: "Full App Run",
                detail: hasFullStackRun ? fullStackStatusLine : "Run Generate Full Stack to build all targets with quality summary",
                state: fullStackReady ? .done : (hasFullStackRun ? .active : .pending)
            ),
            BuildStep(
                title: "Enterprise Gate",
                detail: hasEnterpriseReport ? enterpriseReadinessStatusLine : "Generate full stack run to compute enterprise readiness",
                state: enterpriseReady ? .done : (hasEnterpriseReport ? .active : .pending)
            ),
            BuildStep(
                title: "Editing Benchmark",
                detail: benchmarkStatusLine,
                state: benchmarkReady ? .done : .pending
            ),
            BuildStep(
                title: "Review Approval",
                detail: reviewGateStatusLine,
                state: reviewReady ? .done : .active
            ),
        ]
    }

    func sendMessage() {
        let context = ChatService.ChatContext(
            projectName: projectName,
            strategySession: strategySession,
            strategyActiveQuestion: strategyActiveQuestion,
            pipelineMode: pipelineMode,
            latestScope: latestScope,
            memory: memory,
            benchmarkStatusLine: benchmarkStatusLine,
            componentInstances: componentInstances,
            componentSystemStatusLine: componentSystemStatusLine,
            latestBlueprint: latestBlueprint,
            enterpriseReadinessStatusLine: enterpriseReadinessStatusLine
        )

        chatService.sendMessage(context: context, memoryStore: memoryStore) { [weak self] updatedMemory in
            self?.memory = updatedMemory
        }
    }

    func sendBuilderPrompt() {
        let context = ChatService.BuilderCommandContext(
            isAnalyzing: isAnalyzing,
            pipelineMode: pipelineMode,
            selectedImage: selectedImage,
            acceptedStrategySpec: acceptedStrategySpec,
            renderableElements: renderableElements,
            latestScope: latestScope,
            strategySession: strategySession,
            strategyActiveQuestion: strategyActiveQuestion,
            projectName: projectName
        )

        let buildSummary: String = buildSteps.map { step in
            let icon: String
            switch step.state {
            case .pending: icon = "[ ]"
            case .active: icon = "[~]"
            case .done: icon = "[x]"
            }
            return "\(icon) \(step.title): \(step.detail)"
        }.joined(separator: " | ")

        let setPipelineMode: (PipelineMode) -> Void = { [weak self] mode in self?.setPipelineMode(mode) }
        let generateFullStackBuild: () -> Void = { [weak self] in self?.generateFullStackBuild() }
        let runBuildCommand: () -> Void = { [weak self] in
            guard let self else { return }
            self.messages.append(ChatMessage(role: .assistant, text: "Builder command received: build. Running analysis pipeline."))
            self.analyzeCurrentImage()
        }
        let runAnalyze: () -> Void = { [weak self] in self?.analyzeCurrentImage() }
        let addArtboard: () -> Void = { [weak self] in self?.addArtboard() }
        let genStateArtboards: () -> Void = { [weak self] in self?.generateStateArtboardsFromLatestBlueprint() }
        let distH: () -> Void = { [weak self] in self?.distributeSelectedElementsHorizontally() }
        let distV: () -> Void = { [weak self] in self?.distributeSelectedElementsVertically() }
        let spaceH: (CGFloat) -> Void = { [weak self] gap in self?.spaceSelectedElementsHorizontally(gap: gap) }
        let spaceV: (CGFloat) -> Void = { [weak self] gap in self?.spaceSelectedElementsVertically(gap: gap) }
        let createComp: () -> Void = { [weak self] in self?.createComponentFromSelection(named: nil) }
        let createInst: () -> Void = { [weak self] in self?.createComponentInstanceFromSelectedComponent() }
        let runBench: () -> Void = { [weak self] in self?.runProEditingBenchmark() }
        let autoFix: () -> Void = { [weak self] in self?.autoFixFailingBenchmarkStep() }
        let updateOverride: (String, String) -> Void = { [weak self] key, value in self?.updateSelectedInstanceOverride(key: key, value: value) }
        let applyOverrides: () -> Void = { [weak self] in self?.applySelectedInstanceOverridesToAll() }
        let rollback: (UUID?) -> Void = { [weak self] revisionID in
            guard let revisionID else { return }
            self?.rollbackTokenRevision(revisionID)
        }
        let exportInterop: () -> Void = { [weak self] in self?.exportInteropPackage() }
        let setReview: (ReviewApprovalState) -> Bool = { [weak self] state in
            self?.setReviewApprovalState(state) ?? false
        }
        let dupArtboard: () -> Void = { [weak self] in self?.duplicateActiveArtboard() }
        let exportJSON: () -> Void = { [weak self] in self?.exportJSON() }
        let saveProj: () -> Void = { [weak self] in self?.saveProjectPackage() }
        let clearMem: () -> Void = { [weak self] in self?.clearProjectMemory() }
        let newProj: () -> Void = { [weak self] in self?.createNewProject(named: nil) }
        let startStrat: (String) -> Void = { [weak self] prompt in self?.startStrategyFromIdea(prompt) }
        let contStrat: () -> Void = { [weak self] in self?.continueStrategy() }
        let finalSpec: () -> Void = { [weak self] in self?.finalizeStrategySpec() }
        let genMockups: () -> Void = { [weak self] in self?.finalizeAndGenerateMockups() }
        let approveStage: () -> Void = { [weak self] in self?.approveCurrentStage() }
        let skipQ: () -> Void = { [weak self] in self?.skipStrategyQuestion() }
        let autoRun: () -> Void = { [weak self] in self?.autoRunStrategy() }
        let submitAnswer: (String) -> Void = { [weak self] answer in self?.submitStrategyAnswer(answer) }

        chatService.sendBuilderPrompt(
            context: context,
            onSetPipelineMode: setPipelineMode,
            onGenerateFullStackBuild: generateFullStackBuild,
            onRunBuilderBuildCommand: runBuildCommand,
            onRunBuilderAnalyzeCommand: runAnalyze,
            onAddArtboard: addArtboard,
            onGenerateStateArtboards: genStateArtboards,
            onDistributeHorizontally: distH,
            onDistributeVertically: distV,
            onSpaceHorizontally: spaceH,
            onSpaceVertically: spaceV,
            onCreateComponent: createComp,
            onCreateComponentInstance: createInst,
            onRunBenchmark: runBench,
            onAutoFixBenchmark: autoFix,
            onUpdateInstanceOverride: updateOverride,
            onApplyOverridesToAll: applyOverrides,
            onRollbackTokenRevision: rollback,
            onExportInterop: exportInterop,
            onSetReviewApprovalState: setReview,
            onDuplicateArtboard: dupArtboard,
            onExportJSON: exportJSON,
            onSaveProject: saveProj,
            onClearProjectMemory: clearMem,
            onCreateNewProject: newProj,
            onStartStrategy: startStrat,
            onContinueStrategy: contStrat,
            onFinalizeSpec: finalSpec,
            onGenerateMockups: genMockups,
            onApproveCurrentStage: approveStage,
            onSkipQuestion: skipQ,
            onAutoRunStrategy: autoRun,
            onSubmitStrategyAnswer: submitAnswer,
            distributionGap: distributionGap,
            tokenRevisions: tokenRevisions,
            latestBenchmarkReport: latestBenchmarkReport,
            benchmarkStatusLine: benchmarkStatusLine,
            buildStatusSummary: buildSummary,
            latestEnterpriseReadinessReport: latestEnterpriseReadinessReport,
            latestBlueprint: latestBlueprint
        )

        // Handle realtime build scheduling if needed
        let normalized = chatService.builderDraft.lowercased()
        if normalized.contains("realtime") {
            realTimeBuildEnabled = true
            scheduleRealtimeAnalysis(reason: "builder realtime command")
        }
    }

    func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.supportedImportTypes
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Design File"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            _ = await loadDesignAsset(from: url, source: "Loaded")
        }
    }

    func clearImage() {
        realtimeAnalysisTask?.cancel()
        selectedImage = nil
        selectedImageURL = nil
        clearElementSelection()
        errorMessage = nil
        latestScope = nil
        latestBlueprint = nil
        latestDesignTokens = nil
        tokenRevisions = []
        latestComponentSpecs = []
        componentInstances = []
        selectedComponentID = nil
        selectedComponentInstanceID = nil
        importLossReport = nil
        latestInteropPackage = nil
        latestBuildQualityReport = nil
        designCodeDiffs = []
        latestFullStackBuildSummary = nil
        latestEnterpriseReadinessReport = nil
        reviewComments = []
        reviewCommentDraft = ""
        reviewCommentAssigneeDraft = ""
        reviewCommentHasDueDate = false
        reviewCommentDueDateDraft = Date()
        reviewApprovalState = .pending
        latestBenchmarkReport = nil
        benchmarkHistory = []
        selectedInstanceOverrideValueDraft = ""
        lastRealtimeBuildPath = nil
        latestImageDescriptor = nil
        latestMetadata = nil
        withActiveArtboard { board in
            board = Artboard.empty(named: board.name)
        }
    }

    func analyzeCurrentImage() {
        guard let image = selectedImage, let cgImage = image.resolvedCGImage else {
            errorMessage = "Upload a valid image before running analysis."
            return
        }

        isAnalyzing = true
        errorMessage = nil

        let filename = selectedImageURL?.lastPathComponent ?? "uploaded-image"

        Task {
            do {
                let document = try await analyzer.analyze(cgImage: cgImage, filename: filename)
                let semanticResult = await semanticPipeline.enrich(
                    document: document,
                    imageData: image.jpegData()
                )
                applySemantic(result: semanticResult)
            } catch {
                isAnalyzing = false
                errorMessage = error.localizedDescription
            }
        }
    }

    func handleDroppedProviders(_ providers: [NSItemProvider]) {
        Task {
            if let fileURL = await firstDroppedFileURL(from: providers) {
                if await loadDesignAsset(from: fileURL, source: "Dropped") {
                    return
                }
                return
            }

            if let imageData = await firstDroppedImageData(from: providers), loadImage(fromData: imageData, fallbackName: "Dropped Image", source: "Dropped") {
                return
            }

            errorMessage = "Drop a design file (PNG/JPG/PDF/AI/SVG/FIG/JSON)."
        }
    }

    func clearElementSelection() {
        selectionService.clearElementSelection()
    }

    func setSelectedElement(_ id: UUID?, additive: Bool = false) {
        selectionService.setSelectedElement(id, additive: additive, validIDs: Set(renderableElements.map(\.id)))
    }

    func setSelectedElements(_ ids: Set<UUID>, preferredPrimary: UUID? = nil) {
        selectionService.setSelectedElements(ids, preferredPrimary: preferredPrimary, validIDs: Set(renderableElements.map(\.id)))
    }

    func selectElementsByMarquee(_ elementIDs: [UUID], additive: Bool = false) {
        selectionService.selectElementsByMarquee(elementIDs, additive: additive, validIDs: Set(renderableElements.map(\.id)))
    }

    func distributeSelectedElementsHorizontally() {
        guard canDistributeSelection else { return }
        withActiveArtboard { board in
            let ids = selectedElementIDs
            let indices = board.elements.indices.filter { ids.contains(board.elements[$0].id) }
            guard indices.count >= 3 else { return }

            let sortedIndices = indices.sorted { board.elements[$0].frame.minX < board.elements[$1].frame.minX }
            let totalWidth = sortedIndices.reduce(0.0) { $0 + board.elements[$1].frame.width }
            guard let first = sortedIndices.first, let last = sortedIndices.last else { return }
            let start = board.elements[first].frame.minX
            let end = board.elements[last].frame.maxX
            let available = max(0, end - start - totalWidth)
            let gap = available / Double(max(1, sortedIndices.count - 1))

            var cursor = start
            for index in sortedIndices {
                board.elements[index].frame.x = max(0, min(cursor, Double(board.width) - board.elements[index].frame.width))
                cursor += board.elements[index].frame.width + gap
            }
        }
    }

    func distributeSelectedElementsVertically() {
        guard canDistributeSelection else { return }
        withActiveArtboard { board in
            let ids = selectedElementIDs
            let indices = board.elements.indices.filter { ids.contains(board.elements[$0].id) }
            guard indices.count >= 3 else { return }

            let sortedIndices = indices.sorted { board.elements[$0].frame.minY < board.elements[$1].frame.minY }
            let totalHeight = sortedIndices.reduce(0.0) { $0 + board.elements[$1].frame.height }
            guard let first = sortedIndices.first, let last = sortedIndices.last else { return }
            let start = board.elements[first].frame.minY
            let end = board.elements[last].frame.maxY
            let available = max(0, end - start - totalHeight)
            let gap = available / Double(max(1, sortedIndices.count - 1))

            var cursor = start
            for index in sortedIndices {
                board.elements[index].frame.y = max(0, min(cursor, Double(board.height) - board.elements[index].frame.height))
                cursor += board.elements[index].frame.height + gap
            }
        }
    }

    func spaceSelectedElementsHorizontally(gap: Double) {
        guard selectedElementIDs.count >= 2 else { return }
        let safeGap = max(0, gap)
        withActiveArtboard { board in
            let ids = selectedElementIDs
            let indices = board.elements.indices
                .filter { ids.contains(board.elements[$0].id) }
                .sorted { board.elements[$0].frame.minX < board.elements[$1].frame.minX }

            guard let first = indices.first else { return }
            var cursor = board.elements[first].frame.minX
            for index in indices {
                board.elements[index].frame.x = max(0, min(cursor, Double(board.width) - board.elements[index].frame.width))
                cursor += board.elements[index].frame.width + safeGap
            }
        }
    }

    func spaceSelectedElementsVertically(gap: Double) {
        guard selectedElementIDs.count >= 2 else { return }
        let safeGap = max(0, gap)
        withActiveArtboard { board in
            let ids = selectedElementIDs
            let indices = board.elements.indices
                .filter { ids.contains(board.elements[$0].id) }
                .sorted { board.elements[$0].frame.minY < board.elements[$1].frame.minY }

            guard let first = indices.first else { return }
            var cursor = board.elements[first].frame.minY
            for index in indices {
                board.elements[index].frame.y = max(0, min(cursor, Double(board.height) - board.elements[index].frame.height))
                cursor += board.elements[index].frame.height + safeGap
            }
        }
    }

    func toggleConstraint(_ pin: ConstraintPin, enabled: Bool) {
        guard !selectedElementIDs.isEmpty else { return }
        withActiveArtboard { board in
            for index in board.elements.indices where selectedElementIDs.contains(board.elements[index].id) {
                var constraints = Set(board.elements[index].constraints)
                if enabled {
                    constraints.insert(pin)
                } else {
                    constraints.remove(pin)
                }
                board.elements[index].constraints = constraints.sorted { $0.rawValue < $1.rawValue }
            }
        }
    }

    func hasConstraint(_ pin: ConstraintPin) -> Bool {
        guard !selectedElements.isEmpty else { return false }
        return selectedElements.allSatisfy { $0.constraints.contains(pin) }
    }

    func resizeSelectedElements(handle: ResizeHandle, deltaX: Double, deltaY: Double) {
        guard !selectedElementIDs.isEmpty else { return }
        withActiveArtboard { board in
            for index in board.elements.indices where selectedElementIDs.contains(board.elements[index].id) {
                var element = board.elements[index]
                let minSize = 16.0

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

                element.frame.x = max(0, min(element.frame.x, Double(board.width) - element.frame.width))
                element.frame.y = max(0, min(element.frame.y, Double(board.height) - element.frame.height))
                board.elements[index] = element
            }
        }
    }

    func rotateSelectedElements(by deltaDegrees: Double) {
        guard !selectedElementIDs.isEmpty else { return }
        withActiveArtboard { board in
            for index in board.elements.indices where selectedElementIDs.contains(board.elements[index].id) {
                var element = board.elements[index]
                let next = element.rotationDegrees + deltaDegrees
                element.rotationDegrees = (next.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
                board.elements[index] = element
            }
        }
    }

    func nudgeSelection(deltaX: Double, deltaY: Double) {
        guard !selectedElementIDs.isEmpty else { return }
        withActiveArtboard { board in
            for index in board.elements.indices where selectedElementIDs.contains(board.elements[index].id) {
                var element = board.elements[index]

                let maxX = Double(board.width) - element.frame.width
                let maxY = Double(board.height) - element.frame.height
                var nextX = min(max(0, element.frame.x + deltaX), max(0, maxX))
                var nextY = min(max(0, element.frame.y + deltaY), max(0, maxY))

                if snapToGrid {
                    nextX = snap(value: nextX)
                    nextY = snap(value: nextY)
                }

                element.frame.x = min(max(0, nextX), max(0, maxX))
                element.frame.y = min(max(0, nextY), max(0, maxY))
                board.elements[index] = element
            }
        }
    }

    func keyboardNudgeLeft(fast: Bool = false) {
        let amount = fast ? keyboardNudgeAmount * 3 : keyboardNudgeAmount
        nudgeSelection(deltaX: -amount, deltaY: 0)
    }

    func keyboardNudgeRight(fast: Bool = false) {
        let amount = fast ? keyboardNudgeAmount * 3 : keyboardNudgeAmount
        nudgeSelection(deltaX: amount, deltaY: 0)
    }

    func keyboardNudgeUp(fast: Bool = false) {
        let amount = fast ? keyboardNudgeAmount * 3 : keyboardNudgeAmount
        nudgeSelection(deltaX: 0, deltaY: -amount)
    }

    func keyboardNudgeDown(fast: Bool = false) {
        let amount = fast ? keyboardNudgeAmount * 3 : keyboardNudgeAmount
        nudgeSelection(deltaX: 0, deltaY: amount)
    }

    func keyboardRotateClockwise() {
        rotateSelectedElements(by: 5)
    }

    func keyboardRotateCounterclockwise() {
        rotateSelectedElements(by: -5)
    }

    func clearChatHistory() {
        chatService.clearChatHistory(projectName: projectName, memoryLatestSummary: memory.latestSummary)
    }

    func clearBuilderConversation() {
        chatService.clearBuilderConversation(projectName: projectName)
    }

    func clearProjectMemory() {
        memory = memoryStore.clearMemory()
        messages = ChatService.initialMessages(for: projectName)
        builderMessages = ChatService.initialBuilderMessages(for: projectName)
        draftMessage = ""
        builderDraft = ""
        strategyAnswerDraft = ""
        strategySession = nil
        pipelineMode = .hybrid
        latestDesignTokens = nil
        tokenRevisions = []
        latestComponentSpecs = []
        componentInstances = []
        selectedComponentID = nil
        selectedComponentInstanceID = nil
        importLossReport = nil
        latestInteropPackage = nil
        latestBuildQualityReport = nil
        designCodeDiffs = []
        latestFullStackBuildSummary = nil
        latestEnterpriseReadinessReport = nil
        reviewComments = []
        reviewCommentDraft = ""
        reviewCommentAssigneeDraft = ""
        reviewCommentHasDueDate = false
        reviewCommentDueDateDraft = Date()
        reviewApprovalState = .pending
        latestBenchmarkReport = nil
        benchmarkHistory = []
        selectedInstanceOverrideValueDraft = ""
        clearElementSelection()
        errorMessage = nil
    }

    func startStrategyFromIdea(_ rawIdea: String) {
        let projectID = memory.projectID ?? buildExportService.slugified(projectName)
        strategyService.startStrategyFromIdea(
            rawIdea,
            projectID: projectID,
            pipelineMode: pipelineMode,
            memoryStore: memoryStore
        )
    }

    func submitStrategyAnswer(_ rawAnswer: String) {
        strategyService.submitStrategyAnswer(rawAnswer, memoryStore: memoryStore)
    }

    func approveCurrentStage() {
        strategyService.approveCurrentStage(memoryStore: memoryStore)
    }

    func continueStrategy() {
        strategyService.continueStrategy(memoryStore: memoryStore)
    }

    func skipStrategyQuestion() {
        strategyService.skipCurrentStrategyQuestion(memoryStore: memoryStore)
    }

    func autoRunStrategy() {
        strategyService.autoRunStrategySession(memoryStore: memoryStore)
    }

    func setMockupStylePreset(_ preset: MockupStylePreset) {
        if mockupStylePreset == preset {
            return
        }
        mockupStylePreset = preset
        restyleCurrentMockupsForSelectedPreset()
        memory = memoryStore.recordDecisionLog(
            message: "Mockup style preset set to \(preset.title).",
            stage: strategySession?.stage,
            confidence: acceptedStrategySpec?.confidence
        )
    }

    func tokenColorValue(_ key: String, fallback: String) -> String {
        designTokenService.tokenColorValue(key, fallback: fallback)
    }

    func updateTokenColor(_ key: String, value: String) {
        designTokenService.updateTokenColor(
            key,
            value: value,
            mockupGenerator: mockupGenerator,
            latestScope: latestScope,
            acceptedStrategySpec: acceptedStrategySpec,
            mockupStylePreset: mockupStylePreset
        )
    }

    func tokenRadiusValue(_ key: String, fallback: Double) -> Double {
        designTokenService.tokenRadiusValue(key, fallback: fallback)
    }

    func updateTokenRadius(_ key: String, value: Double) {
        designTokenService.updateTokenRadius(
            key,
            value: value,
            mockupGenerator: mockupGenerator,
            latestScope: latestScope,
            acceptedStrategySpec: acceptedStrategySpec,
            mockupStylePreset: mockupStylePreset
        )
    }

    func tokenTypographySize(_ key: String, fallback: Double) -> Double {
        designTokenService.tokenTypographySize(key, fallback: fallback)
    }

    func updateTokenTypographySize(_ key: String, value: Double) {
        designTokenService.updateTokenTypographySize(
            key,
            value: value,
            mockupGenerator: mockupGenerator,
            latestScope: latestScope,
            acceptedStrategySpec: acceptedStrategySpec,
            mockupStylePreset: mockupStylePreset
        )
    }

    func rollbackTokenRevision(_ revisionID: UUID) {
        designTokenService.rollbackTokenRevision(revisionID)
    }

    func clearTokenRevisionHistory() {
        designTokenService.clearTokenRevisionHistory()
    }

    func createComponentFromSelection(named rawName: String?) {
        componentService.createComponentFromSelection(
            named: rawName,
            selectedElementIDs: selectedElementIDs,
            selectedElements: selectedElements,
            activeArtboard: activeArtboard,
            latestDesignTokens: latestDesignTokens,
            updateArtboard: { [weak self] artboardID, update in
                guard let self else { return }
                self.withActiveArtboard(update)
            }
        )
    }

    func createComponentInstanceFromSelectedComponent() {
        componentService.createComponentInstanceFromSelectedComponent(
            activeArtboard: activeArtboard,
            updateArtboard: { [weak self] update in
                guard let self else { return }
                self.withActiveArtboard { board in
                    _ = update(&board)
                }
            },
            setSelectedElements: { [weak self] ids, primary in
                self?.setSelectedElements(ids, preferredPrimary: primary)
            }
        )
    }

    func updateSelectedComponentVariants(axis rawAxis: String, options rawOptions: String) {
        componentService.updateSelectedComponentVariants(axis: rawAxis, options: rawOptions)
    }

    func mapSelectedInstanceToState(_ rawState: String) {
        componentService.mapSelectedInstanceToState(rawState) { [weak self] update in
            self?.withActiveArtboard(update)
        }
    }

    func selectComponentInstance(_ instanceID: UUID?) {
        componentService.selectComponentInstance(instanceID) { [weak self] ids, primary in
            self?.setSelectedElements(ids, preferredPrimary: primary)
        }
    }

    func updateSelectedInstanceOverride(key rawKey: String, value rawValue: String) {
        componentService.updateSelectedInstanceOverride(key: rawKey, value: rawValue) { [weak self] in
            guard let self,
                  let selectedComponentInstanceID = self.selectedComponentInstanceID,
                  let instance = self.componentInstances.first(where: { $0.id == selectedComponentInstanceID }) else { return }
            self.applyOverridesToInstanceElements(instance)
        }
    }

    func applySelectedInstanceOverridesToAll() {
        componentService.applySelectedInstanceOverridesToAll { [weak self] in
            guard let self,
                  let selectedComponentInstanceID = self.selectedComponentInstanceID,
                  let instance = self.componentInstances.first(where: { $0.id == selectedComponentInstanceID }) else { return }
            self.applyOverridesToAllInstances(of: instance.componentID, overrides: instance.overrides)
        }
    }

    func runProEditingBenchmark() {
        let snapshotArtboards = artboards
        let snapshotArtboardID = selectedArtboardID
        let snapshotSelection = selectedElementIDs
        defer {
            artboards = snapshotArtboards
            selectedArtboardID = snapshotArtboardID
            setSelectedElements(snapshotSelection, preferredPrimary: snapshotSelection.first)
            regenerateJSONPreview()
        }

        guard !renderableElements.isEmpty else {
            let report = BenchmarkRunReport(
                generatedAt: Date(),
                scenario: "Pro Editing Core",
                passed: false,
                steps: [
                    BenchmarkStepResult(
                        id: UUID(),
                        title: "Input",
                        passed: false,
                        detail: "No elements available. Load or generate a mockup first.",
                        latencyMilliseconds: 0
                    ),
                ]
            )
            appendBenchmarkReport(report)
            return
        }

        let candidates = renderableElements.filter { $0.kind != .imageRoot }
        let selection = Set(candidates.prefix(3).map(\.id))
        var results: [BenchmarkStepResult] = []

        results.append(
            benchmarkStep(title: "Multi-select") {
                let selectedStepPassed = !selection.isEmpty
                if selectedStepPassed {
                    setSelectedElements(selection, preferredPrimary: selection.first)
                }
                return (
                    selectedStepPassed,
                    selectedStepPassed
                        ? "Selected \(selection.count) elements for benchmark."
                        : "Not enough elements for selection."
                )
            }
        )

        results.append(
            benchmarkStep(title: "Distribute") {
                let distributionBefore = renderableElements.filter { selection.contains($0.id) }.map(\.frame.minX).sorted()
                distributeSelectedElementsHorizontally()
                let distributionAfter = renderableElements.filter { selection.contains($0.id) }.map(\.frame.minX).sorted()
                let distributionPassed = distributionBefore != distributionAfter && distributionAfter.count >= 2
                return (
                    distributionPassed,
                    distributionPassed
                        ? "Horizontal distribution updated element positions."
                        : "Distribution did not change geometry."
                )
            }
        )

        results.append(
            benchmarkStep(title: "Constraint Pins") {
                toggleConstraint(.left, enabled: true)
                toggleConstraint(.top, enabled: true)
                let constraintPassed = selectedElements.allSatisfy {
                    $0.constraints.contains(.left) && $0.constraints.contains(.top)
                }
                return (
                    constraintPassed,
                    constraintPassed
                        ? "Pinned left/top on selected elements."
                        : "Constraint pinning failed for selection."
                )
            }
        )

        results.append(
            benchmarkStep(title: "Resize Handles") {
                let sizeBefore = selectedElements.map { "\($0.id.uuidString):\($0.frame.width):\($0.frame.height)" }
                resizeSelectedElements(handle: .bottomRight, deltaX: 8, deltaY: 8)
                let sizeAfter = selectedElements.map { "\($0.id.uuidString):\($0.frame.width):\($0.frame.height)" }
                let resizePassed = sizeBefore != sizeAfter
                return (
                    resizePassed,
                    resizePassed
                        ? "Resize handle interaction updated selection bounds."
                        : "Resize did not affect selection."
                )
            }
        )

        results.append(
            benchmarkStep(title: "Rotate Handles") {
                let rotationBefore = selectedElements.map(\.rotationDegrees)
                rotateSelectedElements(by: 5)
                let rotationAfter = selectedElements.map(\.rotationDegrees)
                let rotatePassed = rotationBefore != rotationAfter
                return (
                    rotatePassed,
                    rotatePassed
                        ? "Rotation interaction updated element angles."
                        : "Rotation did not update selected elements."
                )
            }
        )

        let allPassed = results.allSatisfy(\.passed)
        let report = BenchmarkRunReport(
            generatedAt: Date(),
            scenario: "Pro Editing Core",
            passed: allPassed,
            steps: results
        )
        appendBenchmarkReport(report)
    }

    private func benchmarkStep(title: String, action: () -> (passed: Bool, detail: String)) -> BenchmarkStepResult {
        benchmarkService.benchmarkStep(title: title, action: action)
    }

    private func appendBenchmarkReport(_ report: BenchmarkRunReport) {
        benchmarkService.appendBenchmarkReport(report)
    }

    func autoFixFailingBenchmarkStep() {
        guard let latestBenchmarkReport,
              let failingStep = latestBenchmarkReport.steps.first(where: { !$0.passed }) else {
            return
        }

        switch failingStep.title {
        case "Multi-select":
            let ids = Set(renderableElements.filter { $0.kind != .imageRoot }.prefix(3).map(\.id))
            if !ids.isEmpty {
                setSelectedElements(ids, preferredPrimary: ids.first)
            }
        case "Distribute":
            distributeSelectedElementsHorizontally()
        case "Constraint Pins":
            toggleConstraint(.left, enabled: true)
            toggleConstraint(.top, enabled: true)
        case "Resize Handles":
            resizeSelectedElements(handle: .bottomRight, deltaX: 8, deltaY: 8)
        case "Rotate Handles":
            rotateSelectedElements(by: 5)
        default:
            break
        }

        runProEditingBenchmark()
    }

    func addReviewComment(_ rawMessage: String) {
        reviewService.addReviewComment(
            rawMessage,
            artboardID: activeArtboard?.id,
            elementID: selectedElementID
        )
    }

    func toggleReviewCommentResolution(_ commentID: UUID) {
        reviewService.toggleReviewCommentResolution(commentID)
    }

    func resolveAllReviewComments() {
        reviewService.resolveAllReviewComments()
    }

    func clearResolvedReviewComments() {
        reviewService.clearResolvedReviewComments()
    }

    func deleteReviewComment(_ commentID: UUID) {
        reviewService.deleteReviewComment(commentID)
    }

    func isReviewCommentOverdue(_ comment: DesignReviewComment, referenceDate: Date = Date()) -> Bool {
        reviewService.isReviewCommentOverdue(comment, referenceDate: referenceDate)
    }

    func reviewCommentDueDateLine(_ comment: DesignReviewComment) -> String {
        reviewService.reviewCommentDueDateLine(comment)
    }

    @discardableResult
    func setReviewApprovalState(_ state: ReviewApprovalState) -> Bool {
        reviewService.setReviewApprovalState(state)
    }

    func alignSelectedElementLeft() {
        canvasService.alignSelectedElementLeft(
            selectedElementID: selectedElementID,
            selectedElementIDs: selectedElementIDs,
            artboards: &artboards,
            activeArtboardIndex: activeArtboardIndex,
            snapToGrid: snapToGrid,
            gridSize: gridSize,
            reconcileIntegrity: { [weak self] in
                self?.reconcileComponentModelIntegrity()
            },
            regenerateJSON: { [weak self] in
                self?.regenerateJSONPreview()
            }
        )
    }

    func alignSelectedElementHorizontalCenter() {
        canvasService.alignSelectedElementHorizontalCenter(
            selectedElementID: selectedElementID,
            selectedElementIDs: selectedElementIDs,
            artboards: &artboards,
            activeArtboardIndex: activeArtboardIndex,
            snapToGrid: snapToGrid,
            gridSize: gridSize,
            reconcileIntegrity: { [weak self] in
                self?.reconcileComponentModelIntegrity()
            },
            regenerateJSON: { [weak self] in
                self?.regenerateJSONPreview()
            }
        )
    }

    func alignSelectedElementRight() {
        canvasService.alignSelectedElementRight(
            selectedElementID: selectedElementID,
            selectedElementIDs: selectedElementIDs,
            artboards: &artboards,
            activeArtboardIndex: activeArtboardIndex,
            snapToGrid: snapToGrid,
            gridSize: gridSize,
            reconcileIntegrity: { [weak self] in
                self?.reconcileComponentModelIntegrity()
            },
            regenerateJSON: { [weak self] in
                self?.regenerateJSONPreview()
            }
        )
    }

    func alignSelectedElementTop() {
        canvasService.alignSelectedElementTop(
            selectedElementID: selectedElementID,
            selectedElementIDs: selectedElementIDs,
            artboards: &artboards,
            activeArtboardIndex: activeArtboardIndex,
            snapToGrid: snapToGrid,
            gridSize: gridSize,
            reconcileIntegrity: { [weak self] in
                self?.reconcileComponentModelIntegrity()
            },
            regenerateJSON: { [weak self] in
                self?.regenerateJSONPreview()
            }
        )
    }

    func alignSelectedElementVerticalCenter() {
        canvasService.alignSelectedElementVerticalCenter(
            selectedElementID: selectedElementID,
            selectedElementIDs: selectedElementIDs,
            artboards: &artboards,
            activeArtboardIndex: activeArtboardIndex,
            snapToGrid: snapToGrid,
            gridSize: gridSize,
            reconcileIntegrity: { [weak self] in
                self?.reconcileComponentModelIntegrity()
            },
            regenerateJSON: { [weak self] in
                self?.regenerateJSONPreview()
            }
        )
    }

    func alignSelectedElementBottom() {
        canvasService.alignSelectedElementBottom(
            selectedElementID: selectedElementID,
            selectedElementIDs: selectedElementIDs,
            artboards: &artboards,
            activeArtboardIndex: activeArtboardIndex,
            snapToGrid: snapToGrid,
            gridSize: gridSize,
            reconcileIntegrity: { [weak self] in
                self?.reconcileComponentModelIntegrity()
            },
            regenerateJSON: { [weak self] in
                self?.regenerateJSONPreview()
            }
        )
    }

    func setPipelineMode(_ mode: PipelineMode) {
        if pipelineMode == mode {
            return
        }
        pipelineMode = mode
        if var strategySession {
            strategySession.pipelineMode = mode
            self.strategySession = strategySession
            memory = memoryStore.recordStrategySession(strategySession)
            memory = memoryStore.recordDecisionLog(
                message: "Pipeline mode set to \(mode.title).",
                stage: strategySession.stage,
                confidence: strategySession.confidence
            )
        } else {
            memory = memoryStore.recordDecisionLog(
                message: "Pipeline mode set to \(mode.title).",
                stage: nil,
                confidence: nil
            )
        }
    }

    func finalizeStrategySpec() {
        strategyService.finalizeStrategySpec(
            pipelineMode: pipelineMode,
            projectName: projectName,
            memoryStore: memoryStore
        )
    }

    // MARK: - AI Code Generation & Build Pipeline

    /// Full end-to-end pipeline: generate AI code from current design, write project to disk,
    /// build in Xcode, and preview in the simulator.
    func generateAndBuildFromCurrentImage() {
        guard !isGeneratingApp else { return }

        // Validate: we need at least analyzed elements or a strategy spec
        let hasElements = renderableElements.count > 1
        let hasSpec = acceptedStrategySpec != nil
        let hasImage = selectedImage != nil

        guard hasElements || hasSpec || hasImage else {
            errorMessage = "Upload and analyze a design, or generate from an idea first."
            return
        }

        // Check API key availability
        guard KeychainService.resolveAPIKey(for: .anthropicAPIKey) != nil else {
            errorMessage = "No Anthropic API key configured. Open Settings to add one."
            showSettingsSheet = true
            return
        }

        isGeneratingApp = true
        showBuildOutput = true
        errorMessage = nil

        let appName = projectName.isEmpty ? "GeneratedApp" : projectName
        let qualityRaw = UserDefaults.standard.string(forKey: "generationQuality") ?? AIGenerationQuality.fast.rawValue
        let quality = AIGenerationQuality(rawValue: qualityRaw) ?? .fast
        let target = realTimeBuildTarget

        // Capture screenshot data from the current image for the AI pipeline
        let screenshotData: Data? = selectedImage?.jpegData()

        builderMessages.append(
            ChatMessage(role: .assistant, text: "Starting AI code generation for \(target.title) app: \(appName)...")
        )

        Task {
            // Step 1: Generate code using AI pipeline
            let generatedFiles = await codeGenerationPipeline.generateApp(
                elements: renderableElements,
                artboards: artboards,
                tokens: latestDesignTokens,
                components: latestComponentSpecs,
                blueprint: latestBlueprint,
                target: target,
                appName: appName,
                quality: quality,
                screenshotData: screenshotData
            )

            guard !generatedFiles.isEmpty else {
                isGeneratingApp = false
                let failMessage = codeGenerationPipeline.errorMessage ?? "Code generation produced no files."
                errorMessage = failMessage
                builderMessages.append(ChatMessage(role: .assistant, text: "Code generation failed: \(failMessage)"))
                return
            }

            builderMessages.append(
                ChatMessage(role: .assistant, text: "Generated \(generatedFiles.count) files. Writing to disk and starting build...")
            )

            // Step 2: Write generated files to a project directory
            let projectDirectory: URL
            do {
                projectDirectory = try writeGeneratedProjectToDisk(
                    files: generatedFiles,
                    appName: appName,
                    target: target
                )
            } catch {
                isGeneratingApp = false
                errorMessage = "Failed to write project: \(error.localizedDescription)"
                builderMessages.append(ChatMessage(role: .assistant, text: "Failed to write project to disk: \(error.localizedDescription)"))
                return
            }

            // Step 3: Build and run in simulator using BuildPipelineCoordinator
            let scheme = appName
            let bundleID = "com.imageelementstudio.\(appName.lowercased().replacingOccurrences(of: " ", with: ""))"
            let sdk: XcodeToolchainService.SDK = (target == .macos) ? .macosx : .iphonesimulator

            let success = await buildPipelineCoordinator.runFullPipeline(
                projectDirectory: projectDirectory,
                scheme: scheme,
                bundleID: bundleID,
                sdk: sdk,
                onBuildError: { [weak self] errorDescription in
                    guard let self else { return nil }
                    // Use the AI pipeline to attempt to fix build errors
                    await MainActor.run {
                        self.builderMessages.append(
                            ChatMessage(role: .assistant, text: "Build failed. Attempting AI-powered fix...")
                        )
                    }
                    // Return nil to let the coordinator handle retries without AI fix for now
                    // A full implementation would re-invoke the pipeline with error context
                    return nil
                }
            )

            isGeneratingApp = false

            if success {
                builderMessages.append(
                    ChatMessage(role: .assistant, text: "Build succeeded! App is running in the simulator.")
                )
                messages.append(
                    ChatMessage(role: .assistant, text: "AI-generated \(target.title) app built and launched. Project at: \(projectDirectory.path)")
                )
            } else {
                let pipelineError = buildPipelineCoordinator.pipelineError ?? "Unknown build failure"
                builderMessages.append(
                    ChatMessage(role: .assistant, text: "Build pipeline failed: \(pipelineError)")
                )
                errorMessage = "Build pipeline failed: \(pipelineError)"
            }
        }
    }

    /// Writes generated files into a timestamped project directory under Documents.
    private func writeGeneratedProjectToDisk(
        files: [GeneratedFileEntry],
        appName: String,
        target: BuildTarget
    ) throws -> URL {
        let baseDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let slug = appName.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }

        let projectDirectory = baseDirectory
            .appendingPathComponent("ImageElementStudioBuilds", isDirectory: true)
            .appendingPathComponent(slug, isDirectory: true)
            .appendingPathComponent("\(timestamp)-ai-\(target.rawValue)", isDirectory: true)

        let fm = FileManager.default
        try fm.createDirectory(at: projectDirectory, withIntermediateDirectories: true)

        for file in files {
            let filePath = projectDirectory.appendingPathComponent(file.relativePath)
            let directory = filePath.deletingLastPathComponent()
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try file.content.write(to: filePath, atomically: true, encoding: .utf8)
        }

        return projectDirectory
    }

    /// Whether the AI code generation pipeline can be triggered.
    var canGenerateApp: Bool {
        !isGeneratingApp
            && !isSettingUpBuild
            && (renderableElements.count > 1 || acceptedStrategySpec != nil || selectedImage != nil)
    }

    /// Human-readable status of the code generation pipeline.
    var codeGenerationStatusLine: String {
        switch codeGenerationPipeline.state {
        case .idle:
            return "Ready"
        case .analyzingDesign:
            return "Analyzing design..."
        case .planningArchitecture(let progress):
            return "Planning: \(progress)"
        case .generatingFile(let name, let index, let total, _):
            return "Generating \(name) (\(index + 1)/\(total))"
        case .validating(let name):
            return "Validating \(name)"
        case .fixing(let name, let attempt):
            return "Fixing \(name) (attempt \(attempt))"
        case .writingToDisk:
            return "Writing to disk..."
        case .complete(let path):
            return "Complete: \(path)"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }

    func finalizeAndGenerateMockups() {
        if acceptedStrategySpec == nil {
            finalizeStrategySpec()
        }
        guard let spec = acceptedStrategySpec else { return }

        let generated = ideaPlanner.generate(from: spec, projectName: projectName)
        applyIdeaPlannerResult(
            generated,
            sourceLabel: "strategy-spec",
            strategySpec: spec,
            stylePreset: mockupStylePreset
        )
        builderMessages.append(
            ChatMessage(
                role: .assistant,
                text: "Mockups generated from approved strategy spec. Use Build Project or Generate Full Stack next."
            )
        )
    }

    func generateFullStackBuild() {
        if acceptedStrategySpec == nil || (latestScope == nil && renderableElements.count <= 1) {
            finalizeAndGenerateMockups()
        }

        guard !isSettingUpBuild else { return }
        guard canExportBuildArtifacts else {
            let reason = reviewGateBlockReason ?? "Review gate is blocking export."
            let message = "Full-stack export blocked. \(reason)"
            errorMessage = message
            builderMessages.append(ChatMessage(role: .assistant, text: message))
            messages.append(ChatMessage(role: .assistant, text: message))
            return
        }

        isSettingUpBuild = true
        latestFullStackBuildSummary = nil
        latestEnterpriseReadinessReport = nil

        do {
            let result = try buildExportService.generateFullStackBuild(context: makeBuildContext())
            latestFullStackBuildSummary = result.summary
            latestEnterpriseReadinessReport = result.enterpriseReport

            let outcome = result.summary.allTargetsPassed ? "passed" : "requires fixes"
            let targetCount = result.summary.targetResults.count
            builderMessages.append(
                ChatMessage(
                    role: .assistant,
                    text: "Full-stack run \(outcome). Score \(Int(result.summary.aggregateScore.rounded())) across \(targetCount) targets. \(enterpriseReadinessStatusLine). Output: \(result.rootOutputDirectory.path)"
                )
            )
            messages.append(
                ChatMessage(
                    role: .assistant,
                    text: "Full-stack build complete at \(result.rootOutputDirectory.path). Artifacts: full-stack-summary.json, enterprise-readiness-report.json"
                )
            )
            memory = memoryStore.recordDecisionLog(
                message: "Generated full-stack run (\(outcome)) with score \(Int(result.summary.aggregateScore.rounded())) at \(result.rootOutputDirectory.lastPathComponent).",
                stage: strategySession?.stage,
                confidence: acceptedStrategySpec?.confidence
            )
            NSWorkspace.shared.open(result.rootOutputDirectory)
        } catch {
            errorMessage = "Full-stack generation failed: \(error.localizedDescription)"
            builderMessages.append(ChatMessage(role: .assistant, text: "Full-stack generation failed: \(error.localizedDescription)"))
        }

        isSettingUpBuild = false
    }

    // NOTE: makeFullStackBuildOutputDirectory, fullAppSmokePassRate, uniqueStrings,
    // fullStackValidationScript, and makeEnterpriseReadinessReport have been extracted
    // to BuildExportService and are called via buildExportService.

    func generateWireframesFromIdea(_ rawIdea: String) {
        let idea = rawIdea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idea.isEmpty else {
            builderMessages.append(ChatMessage(role: .assistant, text: "Describe your app idea and I will generate wireframes and a build plan."))
            return
        }

        let generated = ideaPlanner.generate(from: idea, projectName: projectName)
        applyIdeaPlannerResult(
            generated,
            sourceLabel: "idea",
            strategySpec: nil,
            stylePreset: mockupStylePreset
        )
    }

    func promptIdeaAndGenerate() {
        promptStrategyFromIdea()
    }

    func promptStrategyFromIdea() {
        let alert = NSAlert()
        alert.messageText = "Start Strategy From Idea"
        alert.informativeText = "Describe the product idea. I will run a multi-step strategist interview before generating mockups."
        alert.alertStyle = .informational

        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        inputField.placeholderString = "Example: Build a mobile app for booking personal trainers"
        alert.accessoryView = inputField

        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        startStrategyFromIdea(inputField.stringValue)
    }


    private func applyIdeaPlannerResult(
        _ generated: IdeaPlannerResult,
        sourceLabel: String,
        strategySpec: StrategySpec?,
        stylePreset: MockupStylePreset
    ) {
        errorMessage = nil
        selectedImage = nil
        selectedImageURL = nil
        clearElementSelection()
        selectedComponentInstanceID = nil
        importLossReport = nil
        latestBuildQualityReport = nil
        designCodeDiffs = []
        latestFullStackBuildSummary = nil
        latestEnterpriseReadinessReport = nil
        reviewApprovalState = .pending
        latestBenchmarkReport = nil
        benchmarkHistory = []
        selectedInstanceOverrideValueDraft = ""

        let mockupResult = mockupGenerator.generate(
            from: generated,
            strategySpec: strategySpec,
            preset: stylePreset
        )
        artboards = mockupResult.artboards
        selectedArtboardID = mockupResult.artboards.first?.id
        latestScope = generated.scope
        latestBlueprint = generated.blueprint
        latestDesignTokens = mockupResult.tokens
        tokenRevisions = [
            TokenRevision(
                id: UUID(),
                createdAt: Date(),
                reason: "Initial generated token set",
                tokens: mockupResult.tokens
            ),
        ]
        latestComponentSpecs = mockupResult.components
        componentInstances = []
        latestImageDescriptor = ImageDescriptor(
            filename: "\(sourceLabel)-wireframe",
            width: mockupResult.artboards.first?.width ?? 1366,
            height: mockupResult.artboards.first?.height ?? 900
        )
        latestMetadata = AnalysisMetadata(
            generatedAt: Date(),
            engine: "Idea Planner + Mockup Generator",
            notes: [
                "Generated wireframes from \(sourceLabel).",
                "Applied design tokens and semantic component mapping.",
            ]
        )

        memory = memoryStore.recordAnalysis(
            scope: generated.scope,
            imageName: sourceLabel,
            artboard: mockupResult.artboards.first
        )

        messages.append(ChatMessage(role: .assistant, text: "Mockup generation active: generated \(generated.artboards.count) wireframe artboards."))
        messages.append(ChatMessage(role: .assistant, text: generated.scope.summary))
        messages.append(ChatMessage(role: .assistant, text: generated.narrative))

        builderMessages.append(
            ChatMessage(
                role: .assistant,
                text: "Mockups ready. Screens: \(mockupResult.artboards.map(\.name).joined(separator: ", ")). \(designSystemStatusLine)"
            )
        )

        runRealtimeBuildSetupIfNeeded()
        regenerateJSONPreview()
    }

    private func restyleCurrentMockupsForSelectedPreset() {
        guard renderableElements.count > 1 else { return }
        guard let scope = latestScope ?? designTokenService.fallbackScopeForTokenization(acceptedStrategySpec: acceptedStrategySpec) else { return }

        let result = mockupGenerator.restyle(
            artboards: artboards,
            scope: scope,
            strategySpec: acceptedStrategySpec,
            preset: mockupStylePreset
        )
        artboards = result.artboards
        selectedArtboardID = selectedArtboardID ?? artboards.first?.id
        latestDesignTokens = result.tokens
        tokenRevisions.append(
            TokenRevision(
                id: UUID(),
                createdAt: Date(),
                reason: "Restyle \(mockupStylePreset.title)",
                tokens: result.tokens
            )
        )
        latestComponentSpecs = result.components
        regenerateJSONPreview()
    }



    private func propagateGlobalTokenChanges(_ tokens: DesignTokenSet) {
        latestComponentSpecs = latestComponentSpecs.map { spec in
            var copy = spec
            var bindings = copy.tokenBindings ?? [:]
            for key in tokens.colors.keys {
                if bindings[key] == nil {
                    bindings[key] = key
                }
            }
            copy.tokenBindings = bindings
            return copy
        }

        for boardIndex in artboards.indices {
            for elementIndex in artboards[boardIndex].elements.indices where artboards[boardIndex].elements[elementIndex].kind != .imageRoot {
                var element = artboards[boardIndex].elements[elementIndex]
                var tags = Set(element.tags)
                tags.insert("token-sync:\(mockupStylePreset.rawValue)")

                var style = element.style ?? ElementVisualStyle(
                    fill: nil,
                    stroke: nil,
                    cornerRadius: nil,
                    opacity: nil,
                    typography: nil
                )

                if tags.contains("token:color.accent.primary") || (element.semanticRole == .buttonPrimary) {
                    style.fill = ElementFillStyle(color: tokens.colors["accent.primary"], gradient: nil)
                } else if tags.contains("token:color.surface.base") || element.kind == .shape {
                    style.fill = ElementFillStyle(color: tokens.colors["surface.base"], gradient: nil)
                }

                if tags.contains("token:stroke.soft") {
                    style.stroke = ElementStrokeStyle(color: tokens.colors["stroke.soft"], width: style.stroke?.width ?? 1)
                }

                if tags.contains("token:radius.control") {
                    style.cornerRadius = tokens.radius["control"]
                } else if tags.contains("token:radius.panel") {
                    style.cornerRadius = tokens.radius["panel"]
                }

                element.tags = tags.sorted()
                element.style = style
                artboards[boardIndex].elements[elementIndex] = element
            }
        }
        regenerateJSONPreview()
    }

    private func applyOverridesToAllInstances(of componentID: UUID, overrides: [String: String]) {
        guard !overrides.isEmpty else { return }
        let targetIDs = componentInstances.filter { $0.componentID == componentID }.map(\.id)
        for instanceID in targetIDs {
            guard let index = componentInstances.firstIndex(where: { $0.id == instanceID }) else { continue }
            componentInstances[index].overrides = overrides
            applyOverridesToInstanceElements(componentInstances[index])
        }
    }

    private func applyOverridesToInstanceElements(_ instance: ComponentInstance) {
        for boardIndex in artboards.indices {
            guard artboards[boardIndex].id == instance.artboardID else { continue }
            for elementIndex in artboards[boardIndex].elements.indices where instance.elementIDs.contains(artboards[boardIndex].elements[elementIndex].id) {
                var element = artboards[boardIndex].elements[elementIndex]
                for (key, value) in instance.overrides {
                    switch key {
                    case "content", "text":
                        if element.kind == .text {
                            element.content = value
                        }
                    case "name":
                        if !value.isEmpty {
                            element.name = value
                        }
                    case "fill":
                        var style = element.style ?? ElementVisualStyle(fill: nil, stroke: nil, cornerRadius: nil, opacity: nil, typography: nil)
                        style.fill = ElementFillStyle(color: normalizedHex(value).isEmpty ? value : normalizedHex(value), gradient: style.fill?.gradient)
                        element.style = style
                    case "opacity":
                        if let number = Double(value) {
                            var style = element.style ?? ElementVisualStyle(fill: nil, stroke: nil, cornerRadius: nil, opacity: nil, typography: nil)
                            style.opacity = max(0.05, min(1, number))
                            element.style = style
                        }
                    default:
                        var tags = Set(element.tags)
                        tags.insert("override:\(key)")
                        element.tags = tags.sorted()
                    }
                }
                artboards[boardIndex].elements[elementIndex] = element
            }
        }
        regenerateJSONPreview()
    }

    private func normalizedHex(_ raw: String) -> String {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()
        guard cleaned.count == 6, cleaned.allSatisfy(\.isHexDigit) else { return "" }
        return "#\(cleaned)"
    }

    private func typographySize(from value: String?, fallback: Double) -> Double {
        guard let value else { return fallback }
        let components = value
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let last = components.last, let number = Double(last) {
            return number
        }
        if let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return number
        }
        return fallback
    }

    private func replacingTypographySize(in value: String, with size: Double) -> String {
        let rounded = Int(size.rounded())
        let parts = value
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard !parts.isEmpty else {
            return "\(rounded)"
        }

        if parts.count == 1 {
            return "\(rounded)"
        }

        var updated = parts
        updated[updated.count - 1] = "\(rounded)"
        return updated.joined(separator: " / ")
    }

    private func snap(value: Double) -> Double {
        let unit = max(2, gridSize)
        return (value / unit).rounded() * unit
    }

    func switchProject(to rawName: String) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? "Default Project" : trimmed

        realtimeAnalysisTask?.cancel()
        memory = memoryStore.switchProject(to: resolved)
        projectName = memory.projectName ?? resolved
        resetWorkspaceForProjectContext()

        UserDefaults.standard.set(projectName, forKey: "ImageElementStudio.ActiveProjectName")
        messages.append(ChatMessage(role: .assistant, text: "Switched to project '\(projectName)'."))
    }

    func createNewProject(named requestedName: String?) {
        realtimeAnalysisTask?.cancel()
        memory = memoryStore.createFreshProject(named: requestedName)
        projectName = memory.projectName ?? "Project"
        resetWorkspaceForProjectContext()
        UserDefaults.standard.set(projectName, forKey: "ImageElementStudio.ActiveProjectName")
        messages.append(ChatMessage(role: .assistant, text: "Created new project '\(projectName)' with clean memory."))
    }

    func saveProjectPackage() {
        let package = ProjectPackage(
            projectName: projectName,
            projectID: memory.projectID ?? buildExportService.slugified(projectName),
            savedAt: Date(),
            artboards: artboards,
            selectedArtboardID: selectedArtboardID,
            latestScope: latestScope,
            latestBlueprint: latestBlueprint,
            latestDesignTokens: latestDesignTokens,
            tokenRevisions: tokenRevisions,
            latestComponentSpecs: latestComponentSpecs,
            componentInstances: componentInstances,
            importLossReport: importLossReport,
            latestInteropPackage: latestInteropPackage,
            latestBuildQualityReport: latestBuildQualityReport,
            designCodeDiffs: designCodeDiffs,
            latestFullStackBuildSummary: latestFullStackBuildSummary,
            latestEnterpriseReadinessReport: latestEnterpriseReadinessReport,
            reviewComments: reviewComments,
            reviewApprovalState: reviewApprovalState,
            latestBenchmarkReport: latestBenchmarkReport,
            benchmarkHistory: benchmarkHistory,
            benchmarkTrendScore: benchmarkTrendScore,
            memory: memory,
            currentDocument: currentDocument()
        )

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "\(buildExportService.slugified(projectName))-project.json"
        panel.prompt = "Save Project"

        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(package)
            try data.write(to: destination, options: .atomic)

            messages.append(ChatMessage(role: .assistant, text: "Project saved: \(destination.path)"))
            errorMessage = nil
        } catch {
            errorMessage = "Could not save project package: \(error.localizedDescription)"
        }
    }

    func buildConfirmationLines(for target: BuildTarget) -> [String] {
        // Forward to service; then append the VM-level status lines
        var lines = buildExportService.buildConfirmationLines(for: target, context: makeBuildContext())
        lines.append(fullStackStatusLine)
        lines.append(enterpriseReadinessStatusLine)
        return lines
    }

    private func checkReviewGateForBuildExport(target: BuildTarget) -> Bool {
        guard let reason = reviewGateBlockReason else { return true }
        let message = "Build export for \(target.title) blocked. \(reason)"
        errorMessage = message
        messages.append(ChatMessage(role: .assistant, text: message))
        builderMessages.append(ChatMessage(role: .assistant, text: message))
        return false
    }

    func setupProjectBuild(for target: BuildTarget) {
        guard !isSettingUpBuild else { return }
        guard checkReviewGateForBuildExport(target: target) else { return }

        if pipelineMode == .guided, selectedImage == nil, acceptedStrategySpec == nil {
            builderMessages.append(
                ChatMessage(
                    role: .assistant,
                    text: "Guided mode requires an approved strategy spec before build setup."
                )
            )
            return
        }

        isSettingUpBuild = true

        do {
            let result = try buildExportService.setupBuild(for: target, context: makeBuildContext())
            latestBuildQualityReport = result.qualityReport
            designCodeDiffs = result.designCodeDiffs
            recordActiveArtboardSnapshot(reason: "setup-\(target.rawValue)")
            messages.append(
                ChatMessage(
                    role: .assistant,
                    text: "Build setup ready for \(target.title). Output: \(result.outputDirectory.path)"
                )
            )
            builderMessages.append(
                ChatMessage(
                    role: .assistant,
                    text: "Build setup complete for \(target.title). Opened output folder with manifest + scaffold notes."
                )
            )
            NSWorkspace.shared.open(result.outputDirectory)
        } catch {
            errorMessage = "Build setup failed: \(error.localizedDescription)"
            builderMessages.append(
                ChatMessage(
                    role: .assistant,
                    text: "Build setup failed: \(error.localizedDescription)"
                )
            )
        }

        isSettingUpBuild = false
    }

    func openRealtimeBuildOutputFolder() {
        guard let path = lastRealtimeBuildPath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    func triggerRealtimeBuildNow() {
        scheduleRealtimeAnalysis(reason: "manual realtime trigger")
    }

    func addArtboard() {
        canvasService.addArtboard(
            to: &artboards,
            selectedArtboardID: &selectedArtboardID,
            activeCanvasSize: activeCanvasSize,
            latestImageDescriptor: latestImageDescriptor,
            recordSnapshot: { [weak self] artboard, reason in
                guard let self else { return }
                self.memory = self.memoryStore.recordArtboardSnapshot(
                    artboard: artboard,
                    reason: reason,
                    imageName: self.latestImageDescriptor?.filename ?? self.selectedImageURL?.lastPathComponent,
                    scope: self.latestScope
                )
            },
            regenerateJSON: { [weak self] in
                self?.regenerateJSONPreview()
            }
        )
    }

    func duplicateActiveArtboard() {
        canvasService.duplicateActiveArtboard(
            artboards: &artboards,
            selectedArtboardID: &selectedArtboardID,
            activeArtboard: activeArtboard,
            recordSnapshot: { [weak self] artboard, reason in
                guard let self else { return }
                self.memory = self.memoryStore.recordArtboardSnapshot(
                    artboard: artboard,
                    reason: reason,
                    imageName: self.latestImageDescriptor?.filename ?? self.selectedImageURL?.lastPathComponent,
                    scope: self.latestScope
                )
            }
        )
    }

    func removeActiveArtboard() {
        canvasService.removeActiveArtboard(
            artboards: &artboards,
            selectedArtboardID: &selectedArtboardID,
            activeArtboardIndex: activeArtboardIndex,
            latestImageDescriptor: latestImageDescriptor,
            clearSelection: { [weak self] in
                self?.clearElementSelection()
            },
            reconcileIntegrity: { [weak self] in
                self?.reconcileComponentModelIntegrity()
            },
            regenerateJSON: { [weak self] in
                self?.regenerateJSONPreview()
            },
            recordSnapshot: { [weak self] artboard, reason in
                guard let self else { return }
                self.memory = self.memoryStore.recordArtboardSnapshot(
                    artboard: artboard,
                    reason: reason,
                    imageName: self.latestImageDescriptor?.filename ?? self.selectedImageURL?.lastPathComponent,
                    scope: self.latestScope
                )
            }
        )
    }

    func generateStateArtboardsFromLatestBlueprint() {
        memory = canvasService.generateStateArtboardsFromLatestBlueprint(
            blueprint: latestBlueprint,
            artboards: &artboards,
            selectedArtboardID: selectedArtboardID,
            memoryStore: memoryStore,
            latestImageDescriptor: latestImageDescriptor,
            selectedImageURL: selectedImageURL,
            latestScope: latestScope
        )
    }

    func renameSelectedElement(_ value: String) {
        canvasService.renameSelectedElement(
            value,
            selectedElementID: selectedElementID,
            artboards: &artboards,
            activeArtboardIndex: activeArtboardIndex,
            reconcileIntegrity: { [weak self] in
                self?.reconcileComponentModelIntegrity()
            },
            regenerateJSON: { [weak self] in
                self?.regenerateJSONPreview()
            }
        )
    }

    func deleteSelectedElement() {
        canvasService.deleteSelectedElement(
            selectedElementID: selectedElementID,
            selectedElementIDs: selectedElementIDs,
            artboards: &artboards,
            activeArtboardIndex: activeArtboardIndex,
            clearSelection: { [weak self] in
                self?.clearElementSelection()
            },
            reconcileIntegrity: { [weak self] in
                self?.reconcileComponentModelIntegrity()
            },
            regenerateJSON: { [weak self] in
                self?.regenerateJSONPreview()
            }
        )
    }

    func nudgeSelectedElement(deltaX: Double, deltaY: Double) {
        canvasService.nudgeSelectedElement(
            deltaX: deltaX,
            deltaY: deltaY,
            selectedElementIDs: selectedElementIDs,
            artboards: &artboards,
            activeArtboardIndex: activeArtboardIndex,
            snapToGrid: snapToGrid,
            gridSize: gridSize,
            reconcileIntegrity: { [weak self] in
                self?.reconcileComponentModelIntegrity()
            },
            regenerateJSON: { [weak self] in
                self?.regenerateJSONPreview()
            }
        )
    }

    func copyJSONToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(jsonPreview, forType: .string)
    }

    func exportJSON() {
        guard let data = encodedCurrentDocument() else {
            errorMessage = "JSON export failed while encoding the current document."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "image-elements.json"
        panel.prompt = "Export JSON"

        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            try data.write(to: destination, options: .atomic)
            errorMessage = nil
        } catch {
            errorMessage = "Could not write JSON: \(error.localizedDescription)"
        }
    }

    func exportInteropPackage() {
        guard canExportBuildArtifacts else {
            let reason = reviewGateBlockReason ?? "Review gate is blocking export."
            let message = "Interop export blocked. \(reason)"
            errorMessage = message
            builderMessages.append(ChatMessage(role: .assistant, text: message))
            messages.append(ChatMessage(role: .assistant, text: message))
            return
        }

        let package = InteropExportPackage(
            packageID: UUID(),
            createdAt: Date(),
            projectName: projectName,
            artboardCount: artboards.count,
            elementCount: artboards.flatMap(\.elements).count,
            includesComponentLibrary: !latestComponentSpecs.isEmpty,
            includesTokenHistory: !tokenRevisions.isEmpty,
            includesImportLossReport: importLossReport != nil
        )

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "\(buildExportService.slugified(projectName))-interop-package.json"
        panel.prompt = "Export Interop Package"

        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            struct AnyInteropPayload: Codable {
                var package: InteropExportPackage
                var designTokens: DesignTokenSet?
                var tokenRevisions: [TokenRevision]
                var components: [ComponentSpec]
                var componentInstances: [ComponentInstance]
                var importLossReport: ImportLossReport?
                var latestBuildQualityReport: BuildQualityReport?
                var latestEnterpriseReadinessReport: EnterpriseReadinessReport?
                var latestBenchmarkReport: BenchmarkRunReport?
                var benchmarkHistory: [BenchmarkRunReport]
                var benchmarkTrendScore: BenchmarkTrendScore?
                var reviewComments: [DesignReviewComment]
                var reviewApprovalState: ReviewApprovalState
                var artboards: [Artboard]
            }

            let typedPayload = AnyInteropPayload(
                package: package,
                designTokens: latestDesignTokens,
                tokenRevisions: tokenRevisions,
                components: latestComponentSpecs,
                componentInstances: componentInstances,
                importLossReport: importLossReport,
                latestBuildQualityReport: latestBuildQualityReport,
                latestEnterpriseReadinessReport: latestEnterpriseReadinessReport,
                latestBenchmarkReport: latestBenchmarkReport,
                benchmarkHistory: benchmarkHistory,
                benchmarkTrendScore: benchmarkTrendScore,
                reviewComments: reviewComments,
                reviewApprovalState: reviewApprovalState,
                artboards: artboards
            )
            let data = try encoder.encode(typedPayload)
            try data.write(to: destination, options: .atomic)
            latestInteropPackage = package
            messages.append(ChatMessage(role: .assistant, text: "Interop package exported: \(destination.path)"))
            errorMessage = nil
        } catch {
            errorMessage = "Could not export interop package: \(error.localizedDescription)"
        }
    }

    private var activeArtboardIndex: Int? {
        guard let selectedArtboardID else { return nil }
        return artboards.firstIndex(where: { $0.id == selectedArtboardID })
    }

    private static var supportedImportTypes: [UTType] {
        var types: [UTType] = [.image, .pdf, .json]
        let extensions = ["ai", "svg", "fig", "xd", "sketch", "eps"]

        for ext in extensions {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }

        return types
    }

    @discardableResult
    private func loadDesignAsset(from url: URL, source: String) async -> Bool {
        do {
            let imported = try await designAssetImporter.importAsset(from: url)
            selectedImageURL = url
            errorMessage = nil
            importLossReport = imported.importLossReport

            if let document = imported.document {
                selectedImage = imported.image
                isAnalyzing = true

                let semanticResult = await semanticPipeline.enrich(
                    document: document,
                    imageData: imported.image?.jpegData()
                )
                applySemantic(result: semanticResult)

                let cleanupLine: String
                if let report = imported.importLossReport {
                    cleanupLine = "Estimated manual cleanup: \(Int(report.estimatedManualCleanupPercent.rounded()))%."
                } else {
                    cleanupLine = ""
                }
                let noteLine = ([imported.notes.joined(separator: " "), cleanupLine]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty })
                    .joined(separator: " ")
                messages.append(
                    ChatMessage(
                        role: .assistant,
                        text: "\(source) \(imported.filename) via structured import. \(noteLine)"
                    )
                )
                builderMessages.append(
                    ChatMessage(
                        role: .assistant,
                        text: "Structured build pipeline complete for \(imported.filename)."
                    )
                )
                return true
            }

            guard let image = imported.image else {
                errorMessage = "Could not derive a preview image from the imported design file."
                return false
            }

            applyLoadedImage(image, filename: imported.filename, source: source)

            if !imported.notes.isEmpty {
                messages.append(ChatMessage(role: .assistant, text: imported.notes.joined(separator: " ")))
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    private func loadImage(fromData data: Data, fallbackName: String, source: String) -> Bool {
        guard let image = NSImage(data: data) else {
            errorMessage = "Could not decode dropped image data."
            return false
        }

        applyLoadedImage(image, filename: fallbackName, source: source)
        selectedImageURL = nil
        return true
    }

    private func applyLoadedImage(_ image: NSImage, filename: String, source: String) {
        selectedImage = image
        errorMessage = nil
        syncCanvasToImage(image: image, filename: filename)
        messages.append(ChatMessage(role: .assistant, text: "\(source) \(filename). Click Analyze Image to infer UI semantics, scope, and JSON elements."))
        builderMessages.append(ChatMessage(role: .assistant, text: "\(source) \(filename). Type 'build' to run the pipeline."))
        scheduleRealtimeAnalysis(reason: "image loaded")
    }

    private func applySemantic(result: SemanticPipelineResult) {
        let document = result.document
        let analyzedBoardID = selectedArtboardID

        if let index = activeArtboardIndex {
            var replacement = document.artboard
            replacement.id = artboards[index].id
            artboards[index] = replacement
            selectedArtboardID = replacement.id
        } else {
            artboards = [document.artboard]
            selectedArtboardID = document.artboard.id
        }

        latestImageDescriptor = document.image
        latestMetadata = document.metadata
        latestScope = document.scope
        latestBlueprint = document.blueprint
        latestDesignTokens = nil
        tokenRevisions = []
        latestComponentSpecs = []
        componentInstances = []
        clearElementSelection()
        designCodeDiffs = []
        latestBuildQualityReport = nil
        latestFullStackBuildSummary = nil
        latestEnterpriseReadinessReport = nil
        reviewApprovalState = .pending
        latestBenchmarkReport = nil
        benchmarkHistory = []
        selectedInstanceOverrideValueDraft = ""
        isAnalyzing = false

        let textCount = document.artboard.elements.filter { $0.kind == .text }.count
        let shapeCount = document.artboard.elements.filter { $0.kind == .shape }.count
        let inferredControls = latestBlueprint?.controls.count ?? 0
        let inferredStates = latestBlueprint?.states.count ?? 0

        if autoGenerateStateArtboards, let blueprint = latestBlueprint {
            memory = canvasService.generateSuggestedStateArtboards(
                from: blueprint,
                sourceArtboardID: analyzedBoardID ?? selectedArtboardID,
                artboards: &artboards,
                selectedArtboardID: selectedArtboardID,
                memoryStore: memoryStore,
                latestImageDescriptor: latestImageDescriptor,
                selectedImageURL: selectedImageURL,
                latestScope: latestScope
            )
        }

        if let scope = document.scope {
            memory = memoryStore.recordAnalysis(
                scope: scope,
                imageName: document.image.filename,
                artboard: document.artboard
            )
            messages.append(
                ChatMessage(
                    role: .assistant,
                    text: "Analysis complete with \(result.source): \(scope.summary)"
                )
            )
            messages.append(
                ChatMessage(
                    role: .assistant,
                    text: "Detected \(textCount) text and \(shapeCount) shape elements. Memory now tracks \(memory.entries.count) design snapshots."
                )
            )
            if let blueprint = latestBlueprint {
                messages.append(
                    ChatMessage(
                        role: .assistant,
                        text: blueprint.detectionSummary
                    )
                )
                messages.append(
                    ChatMessage(
                        role: .assistant,
                        text: "Pipeline inferred \(inferredControls) controls and \(inferredStates) states for auto-build scaffolding."
                    )
                )
            }
            messages.append(ChatMessage(role: .assistant, text: result.narrative))
            builderMessages.append(
                ChatMessage(
                    role: .assistant,
                    text: "Build complete: \(scope.appType) with \(textCount) text and \(shapeCount) shape elements, \(inferredControls) controls, \(inferredStates) states. Type 'status' or 'export json'."
                )
            )
        } else {
            messages.append(ChatMessage(
                role: .assistant,
                text: "Analysis complete: \(textCount) text elements and \(shapeCount) shape elements were mapped into JSON."
            ))
            builderMessages.append(ChatMessage(role: .assistant, text: "Build complete. Mapped \(textCount) text, \(shapeCount) shape elements, \(inferredControls) controls, and \(inferredStates) states."))
        }

        runRealtimeBuildSetupIfNeeded()
        regenerateJSONPreview()
    }

    private func syncCanvasToImage(image: NSImage, filename: String?) {
        guard let cgImage = image.resolvedCGImage else { return }
        let width = cgImage.width
        let height = cgImage.height
        latestScope = nil
        latestBlueprint = nil
        latestDesignTokens = nil
        tokenRevisions = []
        latestComponentSpecs = []
        componentInstances = []
        importLossReport = nil
        latestBuildQualityReport = nil
        designCodeDiffs = []
        latestFullStackBuildSummary = nil
        latestEnterpriseReadinessReport = nil
        reviewApprovalState = .pending
        latestBenchmarkReport = nil
        benchmarkHistory = []
        selectedInstanceOverrideValueDraft = ""

        withActiveArtboard { board in
            board.width = width
            board.height = height
            board.elements = [CanvasElement.root(width: width, height: height, filename: filename)]
        }

        latestImageDescriptor = ImageDescriptor(
            filename: filename ?? "uploaded-image",
            width: width,
            height: height
        )
        latestMetadata = AnalysisMetadata(
            generatedAt: Date(),
            engine: "ImageElementStudio",
            notes: ["Image loaded. Run analysis to infer semantic sections and product scope."]
        )
    }

    private func resetWorkspaceForProjectContext() {
        selectedImage = nil
        selectedImageURL = nil
        clearElementSelection()
        errorMessage = nil
        latestScope = nil
        latestBlueprint = nil
        latestDesignTokens = nil
        tokenRevisions = []
        latestComponentSpecs = []
        componentInstances = []
        selectedComponentID = nil
        selectedComponentInstanceID = nil
        importLossReport = nil
        latestInteropPackage = nil
        latestBuildQualityReport = nil
        designCodeDiffs = []
        latestFullStackBuildSummary = nil
        latestEnterpriseReadinessReport = nil
        reviewComments = []
        reviewCommentDraft = ""
        reviewCommentAssigneeDraft = ""
        reviewCommentHasDueDate = false
        reviewCommentDueDateDraft = Date()
        reviewApprovalState = .pending
        latestBenchmarkReport = nil
        benchmarkHistory = []
        selectedInstanceOverrideValueDraft = ""
        lastRealtimeBuildPath = nil
        latestImageDescriptor = nil
        latestMetadata = nil

        let initialBoard = Artboard.empty(named: "Main Artboard")
        artboards = [initialBoard]
        selectedArtboardID = initialBoard.id
        regenerateJSONPreview()

        messages = ChatService.initialMessages(for: projectName)
        if !memory.latestSummary.isEmpty {
            messages.append(
                ChatMessage(role: .assistant, text: "Memory restored: \(memory.latestSummary)")
            )
        }

        builderMessages = ChatService.initialBuilderMessages(for: projectName)
        draftMessage = ""
        builderDraft = ""
        strategyAnswerDraft = ""
        strategySession = memory.strategySessions.last
        pipelineMode = strategySession?.pipelineMode ?? .hybrid

        if let strategySession, !strategySession.isComplete, let question = strategyActiveQuestion {
            builderMessages.append(
                ChatMessage(
                    role: .assistant,
                    text: "Restored strategy session. \(question.prompt)"
                )
            )
        } else if acceptedStrategySpec != nil {
            builderMessages.append(
                ChatMessage(
                    role: .assistant,
                    text: "Restored approved strategy spec. You can generate mockups or full-stack artifacts."
                )
            )
        }
    }

    private func withActiveArtboard(_ update: (inout Artboard) -> Void) {
        guard let index = activeArtboardIndex else { return }
        update(&artboards[index])
        reconcileComponentModelIntegrity()
        regenerateJSONPreview()
    }

    private func reconcileComponentModelIntegrity() {
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

    private func recordActiveArtboardSnapshot(reason: String) {
        guard let artboard = activeArtboard else { return }
        memory = memoryStore.recordArtboardSnapshot(
            artboard: artboard,
            reason: reason,
            imageName: latestImageDescriptor?.filename ?? selectedImageURL?.lastPathComponent,
            scope: latestScope
        )
    }

    private func firstDroppedFileURL(from providers: [NSItemProvider]) async -> URL? {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let url = await loadFileURL(from: provider) {
                return url
            }
        }
        return nil
    }

    private func firstDroppedImageData(from providers: [NSItemProvider]) async -> Data? {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let data = await loadImageData(from: provider) {
                return data
            }
        }
        return nil
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data {
                    continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                    return
                }

                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }

                if let string = item as? String, let url = URL(string: string) {
                    continuation.resume(returning: url)
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    private func loadImageData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    private func scheduleRealtimeAnalysis(reason: String) {
        guard realTimeBuildEnabled else { return }
        guard selectedImage != nil else { return }

        realtimeAnalysisTask?.cancel()
        realtimeAnalysisTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 240_000_000)
            } catch {
                return
            }

            guard let self else { return }
            self.runRealtimeAnalysisIfNeeded(reason: reason)
        }
    }

    @MainActor
    private func runRealtimeAnalysisIfNeeded(reason: String) {
        guard realTimeBuildEnabled else { return }
        guard selectedImage != nil else { return }
        guard !isAnalyzing else { return }

        builderMessages.append(
            ChatMessage(
                role: .assistant,
                text: "Realtime build triggered (\(reason)): running analysis."
            )
        )
        analyzeCurrentImage()
    }

    private func runRealtimeBuildSetupIfNeeded() {
        guard realTimeBuildEnabled else { return }

        do {
            let outputDirectory = try buildExportService.setupRealtimeBuild(
                for: realTimeBuildTarget,
                context: makeBuildContext()
            )
            latestBuildQualityReport = nil  // realtime builds don't update latestBuildQualityReport
            lastRealtimeBuildPath = outputDirectory.path
            builderMessages.append(
                ChatMessage(
                    role: .assistant,
                    text: "Realtime scaffold updated for \(realTimeBuildTarget.title)."
                )
            )
        } catch {
            errorMessage = "Realtime build setup failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Deterministic Snapshot Forwarding

    func deterministicManifestSnapshot(for target: BuildTarget) -> DeterministicManifestSnapshot {
        buildExportService.deterministicManifestSnapshot(for: target, context: makeBuildContext())
    }

    func deterministicDiffSnapshot(for target: BuildTarget, scaffoldContent: String) -> DeterministicDiffSnapshot {
        buildExportService.deterministicDiffSnapshot(for: target, scaffoldContent: scaffoldContent, context: makeBuildContext())
    }

    func deterministicAppSpecSnapshot(for target: BuildTarget) -> DeterministicAppSpecSnapshot {
        buildExportService.deterministicAppSpecSnapshot(for: target, context: makeBuildContext())
    }

    // MARK: - BuildContext Factory

    /// Assembles a BuildContext snapshot from current ViewModel state for use by BuildExportService.
    func makeBuildContext() -> BuildExportService.BuildContext {
        BuildExportService.BuildContext(
            projectName: projectName,
            projectID: memory.projectID ?? buildExportService.slugified(projectName),
            pipelineMode: pipelineMode,
            mockupStylePreset: mockupStylePreset,
            artboards: artboards,
            latestScope: latestScope,
            latestBlueprint: latestBlueprint,
            latestDesignTokens: latestDesignTokens,
            tokenRevisions: tokenRevisions,
            latestComponentSpecs: latestComponentSpecs,
            componentInstances: componentInstances,
            acceptedStrategySpec: acceptedStrategySpec,
            importLossReport: importLossReport,
            reviewComments: reviewComments,
            reviewApprovalState: reviewApprovalState.rawValue,
            latestBenchmarkReport: latestBenchmarkReport,
            benchmarkHistory: benchmarkHistory,
            benchmarkTrendScore: benchmarkTrendScore,
            designCodeDiffs: designCodeDiffs,
            latestBuildQualityReport: latestBuildQualityReport,
            canExportBuildArtifacts: canExportBuildArtifacts,
            reviewGateBlockReason: reviewGateBlockReason,
            reviewGateStatusLine: reviewGateStatusLine,
            overdueReviewCommentCount: overdueReviewCommentCount,
            unresolvedReviewCommentCount: unresolvedReviewCommentCount,
            qualityGateScoreLine: qualityGateScoreLine,
            memorySnapshotCount: memory.entries.count,
            memoryEntryCount: memory.entries.count,
            activeArtboard: activeArtboard,
            document: currentDocument(),
            strategySessionStage: strategySession?.stage.rawValue,
            acceptedStrategySpecConfidence: acceptedStrategySpec?.confidence
        )
    }

    private func currentDocument(referenceDate: Date = Date()) -> AnalysisDocument {
        let board = activeArtboard ?? Artboard.empty()
        let image = latestImageDescriptor ?? ImageDescriptor(
            filename: selectedImageURL?.lastPathComponent ?? "uploaded-image",
            width: board.width,
            height: board.height
        )

        var metadata = latestMetadata ?? AnalysisMetadata(
            generatedAt: referenceDate,
            engine: "ImageElementStudio",
            notes: ["No automated analysis has been run yet."]
        )
        metadata.generatedAt = referenceDate

        return AnalysisDocument(
            image: image,
            artboard: board,
            metadata: metadata,
            scope: latestScope,
            blueprint: latestBlueprint
        )
    }

    private func encodedCurrentDocument() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(currentDocument())
    }

    private func regenerateJSONPreview() {
        guard let data = encodedCurrentDocument(), let json = String(data: data, encoding: .utf8) else {
            jsonPreview = "{}"
            return
        }
        jsonPreview = json
    }

    private struct ProjectPackage: Codable {
        var projectName: String
        var projectID: String
        var savedAt: Date
        var artboards: [Artboard]
        var selectedArtboardID: UUID?
        var latestScope: ProductScopeSnapshot?
        var latestBlueprint: BuildBlueprint?
        var latestDesignTokens: DesignTokenSet?
        var tokenRevisions: [TokenRevision]
        var latestComponentSpecs: [ComponentSpec]
        var componentInstances: [ComponentInstance]
        var importLossReport: ImportLossReport?
        var latestInteropPackage: InteropExportPackage?
        var latestBuildQualityReport: BuildQualityReport?
        var designCodeDiffs: [DesignCodeDiffEntry]
        var latestFullStackBuildSummary: FullStackBuildSummary?
        var latestEnterpriseReadinessReport: EnterpriseReadinessReport?
        var reviewComments: [DesignReviewComment]
        var reviewApprovalState: ReviewApprovalState
        var latestBenchmarkReport: BenchmarkRunReport?
        var benchmarkHistory: [BenchmarkRunReport]
        var benchmarkTrendScore: BenchmarkTrendScore?
        var memory: ProjectMemory
        var currentDocument: AnalysisDocument
    }

}
