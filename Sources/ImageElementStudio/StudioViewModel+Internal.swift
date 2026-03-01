import Foundation
import SwiftUI

extension StudioViewModel {

    // MARK: - Artboard Helpers

    func withActiveArtboard(_ update: (inout Artboard) -> Void) {
        guard let index = activeArtboardIndex else { return }
        update(&artboards[index]); reconcileComponentModelIntegrity(); regenerateJSONPreview()
    }

    func reconcileComponentModelIntegrity() {
        canvasService.reconcileComponentModelIntegrity(artboards: &artboards, latestComponentSpecs: &latestComponentSpecs, componentInstances: &componentInstances)
    }

    func recordActiveArtboardSnapshot(reason: String) {
        guard let artboard = activeArtboard else { return }
        memory = memoryStore.recordArtboardSnapshot(artboard: artboard, reason: reason, imageName: latestImageDescriptor?.filename ?? selectedImageURL?.lastPathComponent, scope: latestScope)
    }

    // MARK: - JSON Preview

    func regenerateJSONPreview() {
        guard let data = encodedCurrentDocument(), let json = String(data: data, encoding: .utf8) else { jsonPreview = "{}"; return }
        jsonPreview = json
    }

    func encodedCurrentDocument() -> Data? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        do {
            return try encoder.encode(currentDocument())
        } catch {
            // Non-fatal: caller falls back to "{}" for the JSON preview pane.
            AppLogger.error("Failed to encode current document: \(error.localizedDescription)", category: .project)
            return nil
        }
    }

    func currentDocument(referenceDate: Date = Date()) -> AnalysisDocument {
        let board = activeArtboard ?? Artboard.empty()
        let image = latestImageDescriptor ?? ImageDescriptor(filename: selectedImageURL?.lastPathComponent ?? "uploaded-image", width: board.width, height: board.height)
        var metadata = latestMetadata ?? AnalysisMetadata(generatedAt: referenceDate, engine: "ImageElementStudio", notes: ["No automated analysis has been run yet."])
        metadata.generatedAt = referenceDate
        return AnalysisDocument(image: image, artboard: board, metadata: metadata, scope: latestScope, blueprint: latestBlueprint)
    }

    // MARK: - Realtime Analysis

    func scheduleRealtimeAnalysis(reason: String) {
        imageLoadingService.scheduleRealtimeAnalysis(reason: reason, realTimeBuildEnabled: realTimeBuildEnabled, hasImage: selectedImage != nil, onRun: { [weak self] in self?.runRealtimeAnalysisIfNeeded(reason: reason) })
    }

    @MainActor func runRealtimeAnalysisIfNeeded(reason: String) {
        imageLoadingService.runRealtimeAnalysisIfNeeded(reason: reason, realTimeBuildEnabled: realTimeBuildEnabled, hasImage: selectedImage != nil, isAnalyzing: isAnalyzing, onAppendBuilderMessage: { [weak self] msg in self?.builderMessages.append(msg) }, onRunAnalysis: { [weak self] in self?.analyzeCurrentImage() })
    }

    func runRealtimeBuildSetupIfNeeded() {
        guard realTimeBuildEnabled else { return }
        do {
            let outputDirectory = try buildExportService.setupRealtimeBuild(for: realTimeBuildTarget, context: makeBuildContext())
            latestBuildQualityReport = nil; lastRealtimeBuildPath = outputDirectory.path
            builderMessages.append(ChatMessage(role: .assistant, text: "Realtime scaffold updated for \(realTimeBuildTarget.title)."))
        } catch { errorMessage = "Realtime build setup failed: \(error.localizedDescription)" }
    }

    // MARK: - State Reset

    /// Shared reset covering analysis, review, benchmark, component, and build state.
    func resetAnalysisAndReviewState() {
        latestScope = nil; latestBlueprint = nil; latestDesignTokens = nil; tokenRevisions = []
        latestComponentSpecs = []; componentInstances = []; selectedComponentID = nil; selectedComponentInstanceID = nil
        importLossReport = nil; latestInteropPackage = nil; latestBuildQualityReport = nil; designCodeDiffs = []
        latestFullStackBuildSummary = nil; latestEnterpriseReadinessReport = nil
        reviewComments = []; reviewCommentDraft = ""; reviewCommentAssigneeDraft = ""
        reviewCommentHasDueDate = false; reviewCommentDueDateDraft = Date(); reviewApprovalState = .pending
        latestBenchmarkReport = nil; benchmarkHistory = []; selectedInstanceOverrideValueDraft = ""
        lastRealtimeBuildPath = nil; latestImageDescriptor = nil; latestMetadata = nil
    }

    func resetImageAnalysisState() { resetAnalysisAndReviewState() }

    func resetWorkspaceForProjectContext() {
        selectedImage = nil; selectedImageURL = nil; clearElementSelection(); errorMessage = nil
        resetAnalysisAndReviewState()
        let initialBoard = Artboard.empty(named: "Main Artboard")
        artboards = [initialBoard]; selectedArtboardID = initialBoard.id; regenerateJSONPreview()
        messages = ChatService.initialMessages(for: projectName)
        if !memory.latestSummary.isEmpty { messages.append(ChatMessage(role: .assistant, text: "Memory restored: \(memory.latestSummary)")) }
        builderMessages = ChatService.initialBuilderMessages(for: projectName)
        draftMessage = ""; builderDraft = ""; strategyAnswerDraft = ""
        strategySession = memory.strategySessions.last; pipelineMode = strategySession?.pipelineMode ?? .hybrid
        if let session = strategySession, !session.isComplete, let question = strategyActiveQuestion {
            builderMessages.append(ChatMessage(role: .assistant, text: "Restored strategy session. \(question.prompt)"))
        } else if acceptedStrategySpec != nil {
            builderMessages.append(ChatMessage(role: .assistant, text: "Restored approved strategy spec. You can generate mockups or full-stack artifacts."))
        }
    }

    // MARK: - Canvas Edit Helper

    func withCanvasEdit(_ body: () -> Void) { body(); reconcileComponentModelIntegrity(); regenerateJSONPreview() }

    // MARK: - Alignment Helpers

    func alignArgs() -> (UUID?, Set<UUID>, Int?, Bool, Double, () -> Void, () -> Void) {
        (selectedElementID, selectedElementIDs, activeArtboardIndex, snapToGrid, gridSize,
         { [weak self] in self?.reconcileComponentModelIntegrity() }, { [weak self] in self?.regenerateJSONPreview() })
    }

    // MARK: - Context Factories

    func makeBenchmarkContext() -> BenchmarkContext { BenchmarkContext(from: self) }
    func makeBuildContext() -> BuildExportService.BuildContext { BuildExportService.BuildContext(from: self) }

    // MARK: - Deterministic Snapshot Forwarding

    func deterministicManifestSnapshot(for target: BuildTarget) -> DeterministicManifestSnapshot { buildExportService.deterministicManifestSnapshot(for: target, context: makeBuildContext()) }
    func deterministicDiffSnapshot(for target: BuildTarget, scaffoldContent: String) -> DeterministicDiffSnapshot { buildExportService.deterministicDiffSnapshot(for: target, scaffoldContent: scaffoldContent, context: makeBuildContext()) }
    func deterministicAppSpecSnapshot(for target: BuildTarget) -> DeterministicAppSpecSnapshot { buildExportService.deterministicAppSpecSnapshot(for: target, context: makeBuildContext()) }
}
