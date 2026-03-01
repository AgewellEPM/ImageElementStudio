import Foundation

extension StudioViewModel {

    // MARK: - Chat & Memory Clearing

    func clearChatHistory() { chatService.clearChatHistory(projectName: projectName, memoryLatestSummary: memory.latestSummary) }
    func clearBuilderConversation() { chatService.clearBuilderConversation(projectName: projectName) }

    func clearProjectMemory() {
        memory = memoryStore.clearMemory()
        resetAnalysisAndReviewState()
        messages = ChatService.initialMessages(for: projectName)
        builderMessages = ChatService.initialBuilderMessages(for: projectName)
        draftMessage = ""; builderDraft = ""; strategyAnswerDraft = ""; strategySession = nil; pipelineMode = .hybrid
        clearElementSelection(); errorMessage = nil
    }

    // MARK: - Strategy Delegation

    func startStrategyFromIdea(_ rawIdea: String) { strategyService.startStrategyFromIdea(rawIdea, projectID: memory.projectID ?? buildExportService.slugified(projectName), pipelineMode: pipelineMode, memoryStore: memoryStore) }
    func submitStrategyAnswer(_ rawAnswer: String) { strategyService.submitStrategyAnswer(rawAnswer, memoryStore: memoryStore) }
    func approveCurrentStage() { strategyService.approveCurrentStage(memoryStore: memoryStore) }
    func continueStrategy() { strategyService.continueStrategy(memoryStore: memoryStore) }
    func skipStrategyQuestion() { strategyService.skipCurrentStrategyQuestion(memoryStore: memoryStore) }
    func autoRunStrategy() { strategyService.autoRunStrategySession(memoryStore: memoryStore) }
    func finalizeStrategySpec() { strategyService.finalizeStrategySpec(pipelineMode: pipelineMode, projectName: projectName, memoryStore: memoryStore) }

    // MARK: - Mockup Style Preset

    func setMockupStylePreset(_ preset: MockupStylePreset) {
        if mockupStylePreset == preset { return }
        mockupStylePreset = preset
        restyleCurrentMockupsForSelectedPreset()
        memory = memoryStore.recordDecisionLog(message: "Mockup style preset set to \(preset.title).", stage: strategySession?.stage, confidence: acceptedStrategySpec?.confidence)
    }

    // MARK: - Design Token Delegation

    func tokenColorValue(_ key: String, fallback: String) -> String { designTokenService.tokenColorValue(key, fallback: fallback) }
    func updateTokenColor(_ key: String, value: String) { designTokenService.updateTokenColor(key, value: value, mockupGenerator: mockupGenerator, latestScope: latestScope, acceptedStrategySpec: acceptedStrategySpec, mockupStylePreset: mockupStylePreset) }
    func tokenRadiusValue(_ key: String, fallback: Double) -> Double { designTokenService.tokenRadiusValue(key, fallback: fallback) }
    func updateTokenRadius(_ key: String, value: Double) { designTokenService.updateTokenRadius(key, value: value, mockupGenerator: mockupGenerator, latestScope: latestScope, acceptedStrategySpec: acceptedStrategySpec, mockupStylePreset: mockupStylePreset) }
    func tokenTypographySize(_ key: String, fallback: Double) -> Double { designTokenService.tokenTypographySize(key, fallback: fallback) }
    func updateTokenTypographySize(_ key: String, value: Double) { designTokenService.updateTokenTypographySize(key, value: value, mockupGenerator: mockupGenerator, latestScope: latestScope, acceptedStrategySpec: acceptedStrategySpec, mockupStylePreset: mockupStylePreset) }
    func rollbackTokenRevision(_ revisionID: UUID) { designTokenService.rollbackTokenRevision(revisionID) }
    func clearTokenRevisionHistory() { designTokenService.clearTokenRevisionHistory() }

    // MARK: - Component Delegation

    func createComponentFromSelection(named rawName: String?) {
        componentService.createComponentFromSelection(named: rawName, selectedElementIDs: selectedElementIDs, selectedElements: selectedElements, activeArtboard: activeArtboard, latestDesignTokens: latestDesignTokens, updateArtboard: { [weak self] _, update in self?.withActiveArtboard(update) })
    }

    func createComponentInstanceFromSelectedComponent() {
        componentService.createComponentInstanceFromSelectedComponent(activeArtboard: activeArtboard, updateArtboard: { [weak self] update in self?.withActiveArtboard { board in _ = update(&board) } }, setSelectedElements: { [weak self] ids, primary in self?.setSelectedElements(ids, preferredPrimary: primary) })
    }

    func updateSelectedComponentVariants(axis rawAxis: String, options rawOptions: String) { componentService.updateSelectedComponentVariants(axis: rawAxis, options: rawOptions) }

    func mapSelectedInstanceToState(_ rawState: String) { componentService.mapSelectedInstanceToState(rawState) { [weak self] update in self?.withActiveArtboard(update) } }

    func selectComponentInstance(_ instanceID: UUID?) { componentService.selectComponentInstance(instanceID) { [weak self] ids, primary in self?.setSelectedElements(ids, preferredPrimary: primary) } }

    func updateSelectedInstanceOverride(key rawKey: String, value rawValue: String) {
        componentService.updateSelectedInstanceOverride(key: rawKey, value: rawValue) { [weak self] in
            guard let self, let id = self.selectedComponentInstanceID, let instance = self.componentInstances.first(where: { $0.id == id }) else { return }
            componentService.applyOverridesToInstanceElements(instance, artboards: &artboards, activeArtboardIndex: activeArtboardIndex, latestDesignTokens: latestDesignTokens, latestComponentSpecs: latestComponentSpecs)
        }
    }

    func applySelectedInstanceOverridesToAll() {
        guard let id = selectedComponentInstanceID, let instance = componentInstances.first(where: { $0.id == id }) else { return }
        var instances = componentInstances
        componentService.applyOverridesToAllInstances(of: instance.componentID, overrides: instance.overrides, componentInstances: &instances)
        componentInstances = instances
        for inst in componentInstances { componentService.applyOverridesToInstanceElements(inst, artboards: &artboards, activeArtboardIndex: activeArtboardIndex, latestDesignTokens: latestDesignTokens, latestComponentSpecs: latestComponentSpecs) }
        regenerateJSONPreview()
    }

    // MARK: - Benchmark Delegation

    func runProEditingBenchmark() {
        let snap = (artboards: artboards, boardID: selectedArtboardID, selection: selectedElementIDs)
        defer { artboards = snap.artboards; selectedArtboardID = snap.boardID; setSelectedElements(snap.selection, preferredPrimary: snap.selection.first); regenerateJSONPreview() }
        benchmarkService.runProEditingBenchmark(context: makeBenchmarkContext())
    }

    func autoFixFailingBenchmarkStep() { benchmarkService.autoFixFailingBenchmarkStep(context: makeBenchmarkContext()) { _ in } }

    // MARK: - Review Delegation

    func addReviewComment(_ rawMessage: String) { reviewService.addReviewComment(rawMessage, artboardID: activeArtboard?.id, elementID: selectedElementID) }
    func toggleReviewCommentResolution(_ commentID: UUID) { reviewService.toggleReviewCommentResolution(commentID) }
    func resolveAllReviewComments() { reviewService.resolveAllReviewComments() }
    func clearResolvedReviewComments() { reviewService.clearResolvedReviewComments() }
    func deleteReviewComment(_ commentID: UUID) { reviewService.deleteReviewComment(commentID) }
    func isReviewCommentOverdue(_ comment: DesignReviewComment, referenceDate: Date = Date()) -> Bool { reviewService.isReviewCommentOverdue(comment, referenceDate: referenceDate) }
    func reviewCommentDueDateLine(_ comment: DesignReviewComment) -> String { reviewService.reviewCommentDueDateLine(comment) }
    @discardableResult func setReviewApprovalState(_ state: ReviewApprovalState) -> Bool { reviewService.setReviewApprovalState(state) }

    // MARK: - Alignment Delegation

    func alignSelectedElementLeft() { let a = alignArgs(); canvasService.alignSelectedElementLeft(selectedElementID: a.0, selectedElementIDs: a.1, artboards: &artboards, activeArtboardIndex: a.2, snapToGrid: a.3, gridSize: a.4, reconcileIntegrity: a.5, regenerateJSON: a.6) }
    func alignSelectedElementHorizontalCenter() { let a = alignArgs(); canvasService.alignSelectedElementHorizontalCenter(selectedElementID: a.0, selectedElementIDs: a.1, artboards: &artboards, activeArtboardIndex: a.2, snapToGrid: a.3, gridSize: a.4, reconcileIntegrity: a.5, regenerateJSON: a.6) }
    func alignSelectedElementRight() { let a = alignArgs(); canvasService.alignSelectedElementRight(selectedElementID: a.0, selectedElementIDs: a.1, artboards: &artboards, activeArtboardIndex: a.2, snapToGrid: a.3, gridSize: a.4, reconcileIntegrity: a.5, regenerateJSON: a.6) }
    func alignSelectedElementTop() { let a = alignArgs(); canvasService.alignSelectedElementTop(selectedElementID: a.0, selectedElementIDs: a.1, artboards: &artboards, activeArtboardIndex: a.2, snapToGrid: a.3, gridSize: a.4, reconcileIntegrity: a.5, regenerateJSON: a.6) }
    func alignSelectedElementVerticalCenter() { let a = alignArgs(); canvasService.alignSelectedElementVerticalCenter(selectedElementID: a.0, selectedElementIDs: a.1, artboards: &artboards, activeArtboardIndex: a.2, snapToGrid: a.3, gridSize: a.4, reconcileIntegrity: a.5, regenerateJSON: a.6) }
    func alignSelectedElementBottom() { let a = alignArgs(); canvasService.alignSelectedElementBottom(selectedElementID: a.0, selectedElementIDs: a.1, artboards: &artboards, activeArtboardIndex: a.2, snapToGrid: a.3, gridSize: a.4, reconcileIntegrity: a.5, regenerateJSON: a.6) }

    // MARK: - Pipeline Mode

    func setPipelineMode(_ mode: PipelineMode) {
        strategyService.setPipelineMode(mode, currentMode: pipelineMode, memoryStore: memoryStore, onModeChanged: { [weak self] m in self?.pipelineMode = m }, onMemoryUpdated: { [weak self] m in self?.memory = m })
    }
}
