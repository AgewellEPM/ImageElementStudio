import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class StudioViewModel: ObservableObject {
    struct BuildStep: Identifiable {
        enum State { case pending, active, done }
        var id: String { title }
        var title: String
        var detail: String
        var state: State
    }

    enum BuildTarget: String, CaseIterable, Identifiable {
        case ios, macos, web
        var id: String { rawValue }
        var title: String {
            switch self { case .ios: return "iOS"; case .macos: return "macOS"; case .web: return "Web" }
        }
        var symbolName: String {
            switch self { case .ios: return "iphone"; case .macos: return "desktopcomputer"; case .web: return "globe" }
        }
        var buildLabel: String {
            switch self { case .ios: return "Mobile App"; case .macos: return "Desktop App"; case .web: return "Web App" }
        }
    }

    enum ResizeHandle: String, CaseIterable, Identifiable {
        case topLeft, topRight, bottomLeft, bottomRight, left, right, top, bottom
        var id: String { rawValue }
    }

    // Chat properties forwarded to ChatService
    var messages: [ChatMessage] { get { chatService.messages } set { chatService.messages = newValue } }
    var draftMessage: String { get { chatService.draftMessage } set { chatService.draftMessage = newValue } }
    var builderMessages: [ChatMessage] { get { chatService.builderMessages } set { chatService.builderMessages = newValue } }
    var builderDraft: String { get { chatService.builderDraft } set { chatService.builderDraft = newValue } }

    @Published var selectedImage: NSImage?
    @Published var selectedImageURL: URL?
    @Published var artboards: [Artboard]
    @Published var selectedArtboardID: UUID? { didSet { clearElementSelection(); regenerateJSONPreview() } }
    var selectedElementID: UUID? { get { selectionService.selectedElementID } set { selectionService.selectedElementID = newValue } }
    var selectedElementIDs: Set<UUID> { get { selectionService.selectedElementIDs } set { selectionService.selectedElementIDs = newValue } }

    @Published var isAnalyzing: Bool = false
    @Published var isSettingUpBuild: Bool = false
    @Published var errorMessage: String?
    @Published var jsonPreview: String = "{}"
    @Published var projectName: String
    @Published var latestScope: ProductScopeSnapshot?
    @Published var latestBlueprint: BuildBlueprint?
    var latestComponentSpecs: [ComponentSpec] { get { componentService.latestComponentSpecs } set { componentService.latestComponentSpecs = newValue } }
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
    var strategySession: StrategySession? { get { strategyService.strategySession } set { strategyService.strategySession = newValue } }
    var strategyAnswerDraft: String { get { strategyService.strategyAnswerDraft } set { strategyService.strategyAnswerDraft = newValue } }
    var componentInstances: [ComponentInstance] { get { componentService.componentInstances } set { componentService.componentInstances = newValue } }
    var selectedComponentID: UUID? { get { componentService.selectedComponentID } set { componentService.selectedComponentID = newValue } }
    var selectedComponentInstanceID: UUID? { get { componentService.selectedComponentInstanceID } set { componentService.selectedComponentInstanceID = newValue } }
    @Published var importLossReport: ImportLossReport?
    @Published var latestInteropPackage: InteropExportPackage?
    @Published var latestBuildQualityReport: BuildQualityReport?
    @Published var designCodeDiffs: [DesignCodeDiffEntry] = []
    @Published var latestFullStackBuildSummary: FullStackBuildSummary?
    @Published var latestEnterpriseReadinessReport: EnterpriseReadinessReport?
    @Published var selectedVariantAxisName: String = "state"
    @Published var selectedVariantOptionsDraft: String = "default,hover,pressed"
    var selectedComponentStateDraft: String { get { componentService.selectedComponentStateDraft } set { componentService.selectedComponentStateDraft = newValue } }
    var selectedInstanceOverrideKeyDraft: String { get { componentService.selectedInstanceOverrideKeyDraft } set { componentService.selectedInstanceOverrideKeyDraft = newValue } }
    var selectedInstanceOverrideValueDraft: String { get { componentService.selectedInstanceOverrideValueDraft } set { componentService.selectedInstanceOverrideValueDraft = newValue } }
    @Published var distributionGap: Double = 12
    @Published var keyboardNudgeAmount: Double = 4
    var isMarqueeSelecting: Bool { get { selectionService.isMarqueeSelecting } set { selectionService.isMarqueeSelecting = newValue } }
    var marqueeSelectionCount: Int { get { selectionService.marqueeSelectionCount } set { selectionService.marqueeSelectionCount = newValue } }

    let analyzer = ImageAnalyzer()
    let designAssetImporter = DesignAssetImporter()
    let ideaPlanner = IdeaPlanner()
    let mockupGenerator = MockupGenerator()
    let semanticPipeline: SemanticPipeline
    let memoryStore: ProjectMemoryStore
    var latestMetadata: AnalysisMetadata?
    var latestImageDescriptor: ImageDescriptor?
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
    let imageLoadingService = ImageLoadingService()
    let projectService = ProjectService()
    let exportService = ExportService()
    let deviceCatalogService = DeviceCatalogService()
    let signingService = SigningService()
    let wireframeService = AIWireframeService()
    private(set) lazy var deploymentService: DeploymentService = {
        DeploymentService(
            toolchainService: buildPipelineCoordinator.toolchainService,
            signingService: signingService
        )
    }()

    typealias BuildManifest = BuildExportService.BuildManifest
    typealias DeterministicManifestSnapshot = BuildExportService.DeterministicManifestSnapshot
    typealias DeterministicDiffSnapshot = BuildExportService.DeterministicDiffSnapshot
    typealias DeterministicAppSpecSnapshot = BuildExportService.DeterministicAppSpecSnapshot

    let codeGenerationPipeline = CodeGenerationPipeline()
    let buildPipelineCoordinator = BuildPipelineCoordinator()
    @Published var isGeneratingApp: Bool = false
    @Published var showBuildOutput: Bool = false
    @Published var showSettingsSheet: Bool = false
    @Published var showDeploymentWizard: Bool = false
    @Published var showSelfTestPanel: Bool = false
    @Published var canvasZoom: CGFloat = 1.0
    @Published var isChatCollapsed: Bool = false
    let selfTestService = SelfTestService()
    let tokenCostService = TokenCostService()

    // MARK: - Zoom Controls

    func zoomIn() { canvasZoom = min(canvasZoom + 0.25, 5.0) }
    func zoomOut() { canvasZoom = max(canvasZoom - 0.25, 0.25) }
    func zoomToFit() { canvasZoom = 1.0 }
    func setZoom(_ value: CGFloat) { canvasZoom = min(max(value, 0.25), 5.0) }

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
            self.messages.append(ChatMessage(role: .assistant, text: "Memory restored: \(memory.latestSummary)"))
        }

        reviewService.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        selectionService.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        benchmarkService.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        chatService.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        designTokenService.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        componentService.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        canvasService.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        strategyService.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        codeGenerationPipeline.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        buildPipelineCoordinator.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        buildExportService.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        deviceCatalogService.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        signingService.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        deploymentService.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        wireframeService.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        selfTestService.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        tokenCostService.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)

        codeGenerationPipeline.tokenCostService = tokenCostService
        wireframeService.tokenCostService = tokenCostService

        strategyService.onAppendBuilderMessage = { [weak self] msg in self?.builderMessages.append(msg) }
        strategyService.onAppendMessage = { [weak self] msg in self?.messages.append(msg) }
        strategyService.onMemoryUpdated = { [weak self] updatedMemory in self?.memory = updatedMemory }
        strategyService.onSetPipelineMode = { [weak self] mode in self?.pipelineMode = mode }
        strategyService.onScopeProduced = { [weak self] scope in self?.latestScope = scope }
        strategyService.onFinalizeAndGenerateMockups = { [weak self] in self?.finalizeAndGenerateMockups() }

        designTokenService.onTokenChangesPropagated = { [weak self] tokens in
            guard let self else { return }
            designTokenService.propagateGlobalTokenChanges(
                tokens, artboards: artboards, mockupStylePreset: mockupStylePreset,
                latestComponentSpecs: latestComponentSpecs,
                onArtboardsUpdated: { [weak self] updated in self?.artboards = updated },
                onComponentSpecsUpdated: { [weak self] updated in self?.latestComponentSpecs = updated },
                onRegenerateJSON: { [weak self] in self?.regenerateJSONPreview() }
            )
        }

        regenerateJSONPreview()
    }

    // MARK: - Computed Properties

    var activeArtboardIndex: Int? {
        guard let selectedArtboardID else { return nil }
        return artboards.firstIndex(where: { $0.id == selectedArtboardID })
    }

    static var supportedImportTypes: [UTType] { ImageLoadingService.supportedImportTypes }

    var activeArtboard: Artboard? { guard let index = activeArtboardIndex else { return nil }; return artboards[index] }
    var selectedElement: CanvasElement? { guard let id = selectedElementID else { return nil }; return activeArtboard?.elements.first(where: { $0.id == id }) }
    var selectedElements: [CanvasElement] { guard !selectedElementIDs.isEmpty else { return [] }; return renderableElements.filter { selectedElementIDs.contains($0.id) } }
    var hasMultiSelection: Bool { selectionService.hasMultiSelection }
    var canDistributeSelection: Bool { selectionService.canDistributeSelection }

    // Review Service Forwarding
    var reviewComments: [DesignReviewComment] { get { reviewService.reviewComments } set { reviewService.reviewComments = newValue } }
    var reviewApprovalState: ReviewApprovalState { get { reviewService.reviewApprovalState } set { reviewService.reviewApprovalState = newValue } }
    var reviewCommentDraft: String { get { reviewService.reviewCommentDraft } set { reviewService.reviewCommentDraft = newValue } }
    var reviewCommentAssigneeDraft: String { get { reviewService.reviewCommentAssigneeDraft } set { reviewService.reviewCommentAssigneeDraft = newValue } }
    var reviewCommentHasDueDate: Bool { get { reviewService.reviewCommentHasDueDate } set { reviewService.reviewCommentHasDueDate = newValue } }
    var reviewCommentDueDateDraft: Date { get { reviewService.reviewCommentDueDateDraft } set { reviewService.reviewCommentDueDateDraft = newValue } }

    // Benchmark Service Forwarding
    var latestBenchmarkReport: BenchmarkRunReport? { get { benchmarkService.latestBenchmarkReport } set { benchmarkService.latestBenchmarkReport = newValue } }
    var benchmarkHistory: [BenchmarkRunReport] { get { benchmarkService.benchmarkHistory } set { benchmarkService.benchmarkHistory = newValue } }

    // Design Token Forwarding
    var latestDesignTokens: DesignTokenSet? { get { designTokenService.latestDesignTokens } set { designTokenService.latestDesignTokens = newValue } }
    var tokenRevisions: [TokenRevision] { get { designTokenService.tokenRevisions } set { designTokenService.tokenRevisions = newValue } }

    var tokenRevisionStatusLine: String { tokenRevisions.isEmpty ? "No token revisions yet." : "\(tokenRevisions.count) revisions available for rollback." }
    var componentSystemStatusLine: String { "\(latestComponentSpecs.count) components, \(componentInstances.count) instances." }
    var selectedComponentSpec: ComponentSpec? { guard let id = selectedComponentID else { return nil }; return latestComponentSpecs.first(where: { $0.id == id }) }
    var selectedComponentInstance: ComponentInstance? { guard let id = selectedComponentInstanceID else { return nil }; return componentInstances.first(where: { $0.id == id }) }
    var variantMatrixPreview: [String] { componentService.variantMatrixPreview(for: selectedComponentSpec) }
    var benchmarkStatusLine: String { benchmarkService.benchmarkStatusLine }
    var benchmarkHistoryPreview: [BenchmarkRunReport] { benchmarkService.benchmarkHistoryPreview }
    var benchmarkTrendScore: BenchmarkTrendScore? { benchmarkService.benchmarkTrendScore }
    var benchmarkTrendPoints: [BenchmarkTrendPoint] { benchmarkService.benchmarkTrendPoints }
    var benchmarkTrendStatusLine: String { benchmarkService.benchmarkTrendStatusLine }
    var benchmarkTrendDirectionLine: String { benchmarkService.benchmarkTrendDirectionLine }
    var interopStatusLine: String { guard let r = importLossReport else { return "No interop report yet." }; return "Estimated manual cleanup: \(Int(r.estimatedManualCleanupPercent.rounded()))%." }
    var reviewStatusLine: String { reviewService.reviewStatusLine }
    var unresolvedReviewCommentCount: Int { reviewService.unresolvedReviewCommentCount }
    var resolvedReviewCommentCount: Int { reviewService.resolvedReviewCommentCount }
    var reviewCommentsPreview: [DesignReviewComment] { reviewService.reviewCommentsPreview }
    var overdueReviewCommentCount: Int { reviewService.overdueReviewCommentCount }
    var reviewGateBlockReason: String? { reviewService.reviewGateBlockReason }
    var canExportBuildArtifacts: Bool { reviewService.canExportBuildArtifacts }
    var reviewGateStatusLine: String { reviewService.reviewGateStatusLine }

    var currentQualityGateSummary: QualityGateSummary {
        let smokeChecks = latestBuildQualityReport?.smokeChecks ?? []
        let diffs = designCodeDiffs.isEmpty ? (latestBuildQualityReport?.diffs ?? []) : designCodeDiffs
        let benchmarkPassRate = benchmarkTrendScore?.passRate ?? latestBenchmarkReport?.stepPassRate
        return buildExportService.makeQualityGateSummary(
            generatedAt: Date(), smokeChecks: smokeChecks, diffEntries: diffs,
            benchmarkPassRate: benchmarkPassRate, reviewGatePassed: canExportBuildArtifacts,
            overdueCommentCount: overdueReviewCommentCount, reviewGateBlockReason: reviewGateBlockReason
        )
    }

    var qualityGateScoreLine: String {
        let s = currentQualityGateSummary
        return "Quality Gate Score: \(Int(s.overallScore.rounded())) · \(s.status.rawValue.capitalized)"
    }

    var qualityGateBreakdownLines: [String] {
        let s = currentQualityGateSummary
        return ["Smoke checks: \(Int((s.smokePassRate * 100).rounded()))%",
                "Full app checks: \(Int((s.fullAppPassRate * 100).rounded()))%",
                "Diff health: \(Int((s.diffHealthScore * 100).rounded()))%",
                "Benchmark trend: \(Int((s.benchmarkPassRate * 100).rounded()))%",
                "Review gate: \(s.reviewGatePassed ? "pass" : "blocked")",
                "Overdue comments: \(s.overdueCommentCount)",
                fullStackStatusLine, enterpriseReadinessStatusLine]
    }

    var qualityGateIssuePreview: [String] {
        Array(buildExportService.uniqueStrings(currentQualityGateSummary.blockingIssues + fullStackIssuePreview + enterpriseReadinessIssuePreview).prefix(Constants.Preview.issuePreviewCount))
    }

    var fullStackStatusLine: String {
        guard let r = latestFullStackBuildSummary else { return "No full-stack run yet." }
        return "Full-stack score \(Int(r.aggregateScore.rounded())) · \(r.allTargetsPassed ? "pass" : "fail") · \(r.targetResults.count) targets"
    }
    var fullStackIssuePreview: [String] { guard let r = latestFullStackBuildSummary else { return [] }; return Array(r.blockingIssues.prefix(Constants.Preview.issuePreviewCount)) }
    var fullStackTargetStatusLines: [String] {
        guard let r = latestFullStackBuildSummary else { return [] }
        return r.targetResults.map { res in "\(res.passed ? "PASS" : "FAIL") \(res.target.uppercased()): smoke \(Int((res.smokePassRate * 100).rounded()))% · full app \(Int((res.fullAppPassRate * 100).rounded()))% · score \(Int(res.qualityScore.rounded()))" }
    }
    var enterpriseReadinessStatusLine: String {
        guard let r = latestEnterpriseReadinessReport else { return "Enterprise readiness: pending run." }
        return "Enterprise readiness: \(r.status.rawValue.capitalized) · \(Int(r.score.rounded()))"
    }
    var enterpriseReadinessIssuePreview: [String] { guard let r = latestEnterpriseReadinessReport else { return [] }; return Array(r.blockers.prefix(Constants.Preview.issuePreviewCount)) }
    var enterpriseReadinessCheckLines: [String] {
        guard let r = latestEnterpriseReadinessReport else { return [] }
        return r.checks.map { c in "\(c.passed ? "PASS" : "FAIL") [\(Int(c.weight.rounded()))] \(c.name): \(c.detail)" }
    }

    var renderableElements: [CanvasElement] { activeArtboard?.elements ?? [] }
    var activeCanvasSize: CGSize { guard let b = activeArtboard else { return CGSize(width: Constants.Canvas.defaultCanvasWidth, height: Constants.Canvas.defaultCanvasHeight) }; return CGSize(width: b.width, height: b.height) }
    var canRemoveArtboard: Bool { artboards.count > 1 }
    var textElementCount: Int { renderableElements.filter { $0.kind == .text }.count }
    var shapeElementCount: Int { renderableElements.filter { $0.kind == .shape }.count }
    var memoryEntriesPreview: [ProjectMemoryEntry] { Array(memory.entries.suffix(Constants.Preview.memoryEntriesCount).reversed()) }
    var memoryStatusLine: String { memory.entries.isEmpty ? "\(projectName): no snapshots yet" : "\(projectName): \(memory.entries.count) snapshots" }
    var projectContextLine: String { "Project: \(projectName) (\(memory.projectID ?? buildExportService.slugified(projectName)))" }
    var realtimeBuildStatusLine: String { lastRealtimeBuildPath.map { "Realtime build: \(realTimeBuildTarget.title) updated at \($0)" } ?? "Realtime build: \(realTimeBuildTarget.title) waiting for analysis" }
    var componentSpecsPreview: [ComponentSpec] { Array(latestComponentSpecs.prefix(Constants.Preview.componentSpecsCount)) }
    var designSystemStatusLine: String {
        guard let t = latestDesignTokens else { return "Design tokens are not generated yet." }
        return "\(mockupStylePreset.title): \(t.colors.count) colors, \(latestComponentSpecs.count) component groups."
    }
    var acceptedStrategySpec: StrategySpec? { memory.acceptedStrategySpecs.last }

    // Strategy Service Forwarding
    var strategyActiveQuestion: StrategyQuestion? { strategyService.strategyActiveQuestion }
    var strategyStageProgress: Double { strategyService.strategyStageProgress }
    var strategyStageLine: String { strategyService.strategyStageLine }
    var strategyControlHint: String { strategyService.strategyControlHint }
    var shouldShowStrategyPanel: Bool { strategyService.shouldShowStrategyPanel(selectedImage: selectedImage, latestScope: latestScope, renderableElementCount: renderableElements.count) }

    var canGenerateApp: Bool { !isGeneratingApp && !isSettingUpBuild && (renderableElements.count > 1 || acceptedStrategySpec != nil || selectedImage != nil) }

    var codeGenerationStatusLine: String {
        switch codeGenerationPipeline.state {
        case .idle: return "Ready"
        case .analyzingDesign: return "Analyzing design..."
        case .planningArchitecture(let p): return "Planning: \(p)"
        case .generatingFile(let name, let idx, let total, _): return "Generating \(name) (\(idx + 1)/\(total))"
        case .validating(let name): return "Validating \(name)"
        case .fixing(let name, let attempt): return "Fixing \(name) (attempt \(attempt))"
        case .writingToDisk: return "Writing to disk..."
        case .complete(let path): return "Complete: \(path)"
        case .failed(let message): return "Failed: \(message)"
        }
    }

    var buildSteps: [BuildStep] {
        canvasService.buildSteps(from: .init(from: self)).map { s in
            let st: BuildStep.State; switch s.state { case .pending: st = .pending; case .active: st = .active; case .done: st = .done }
            return BuildStep(title: s.title, detail: s.detail, state: st)
        }
    }
}
