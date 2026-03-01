import Foundation

extension StudioViewModel {
    func sendMessage() {
        let context = ChatService.ChatContext(projectName: projectName, strategySession: strategySession, strategyActiveQuestion: strategyActiveQuestion, pipelineMode: pipelineMode, latestScope: latestScope, memory: memory, benchmarkStatusLine: benchmarkStatusLine, componentInstances: componentInstances, componentSystemStatusLine: componentSystemStatusLine, latestBlueprint: latestBlueprint, enterpriseReadinessStatusLine: enterpriseReadinessStatusLine)
        chatService.sendMessage(context: context, memoryStore: memoryStore) { [weak self] updatedMemory in self?.memory = updatedMemory }
    }

    func sendBuilderPrompt() {
        let context = ChatService.BuilderCommandContext(isAnalyzing: isAnalyzing, pipelineMode: pipelineMode, selectedImage: selectedImage, acceptedStrategySpec: acceptedStrategySpec, renderableElements: renderableElements, latestScope: latestScope, strategySession: strategySession, strategyActiveQuestion: strategyActiveQuestion, projectName: projectName)
        let buildSummary = buildSteps.map { s in let i: String; switch s.state { case .pending: i = "[ ]"; case .active: i = "[~]"; case .done: i = "[x]" }; return "\(i) \(s.title): \(s.detail)" }.joined(separator: " | ")

        var registry = ChatService.BuilderCommandRegistry()
        registry.onSetPipelineMode = { [weak self] mode in self?.setPipelineMode(mode) }
        registry.onGenerateFullStackBuild = { [weak self] in self?.generateFullStackBuild() }
        registry.onRunBuilderBuildCommand = { [weak self] in
            self?.messages.append(ChatMessage(role: .assistant, text: "Builder command received: build. Running analysis pipeline."))
            self?.analyzeCurrentImage()
        }
        registry.onRunBuilderAnalyzeCommand = { [weak self] in self?.analyzeCurrentImage() }
        registry.onAddArtboard = { [weak self] in self?.addArtboard() }
        registry.onGenerateStateArtboards = { [weak self] in self?.generateStateArtboardsFromLatestBlueprint() }
        registry.onDistributeHorizontally = { [weak self] in self?.distributeSelectedElementsHorizontally() }
        registry.onDistributeVertically = { [weak self] in self?.distributeSelectedElementsVertically() }
        registry.onSpaceHorizontally = { [weak self] gap in self?.spaceSelectedElementsHorizontally(gap: gap) }
        registry.onSpaceVertically = { [weak self] gap in self?.spaceSelectedElementsVertically(gap: gap) }
        registry.onCreateComponent = { [weak self] in self?.createComponentFromSelection(named: nil) }
        registry.onCreateComponentInstance = { [weak self] in self?.createComponentInstanceFromSelectedComponent() }
        registry.onRunBenchmark = { [weak self] in self?.runProEditingBenchmark() }
        registry.onAutoFixBenchmark = { [weak self] in self?.autoFixFailingBenchmarkStep() }
        registry.onUpdateInstanceOverride = { [weak self] key, value in self?.updateSelectedInstanceOverride(key: key, value: value) }
        registry.onApplyOverridesToAll = { [weak self] in self?.applySelectedInstanceOverridesToAll() }
        registry.onRollbackTokenRevision = { [weak self] (revisionID: UUID?) in guard let revisionID else { return }; self?.rollbackTokenRevision(revisionID) }
        registry.onExportInterop = { [weak self] in self?.exportInteropPackage() }
        registry.onSetReviewApprovalState = { [weak self] state in self?.setReviewApprovalState(state) ?? false }
        registry.onDuplicateArtboard = { [weak self] in self?.duplicateActiveArtboard() }
        registry.onExportJSON = { [weak self] in self?.exportJSON() }
        registry.onSaveProject = { [weak self] in self?.saveProjectPackage() }
        registry.onClearProjectMemory = { [weak self] in self?.clearProjectMemory() }
        registry.onCreateNewProject = { [weak self] in self?.createNewProject(named: nil) }
        registry.onStartStrategy = { [weak self] prompt in self?.startStrategyFromIdea(prompt) }
        registry.onContinueStrategy = { [weak self] in self?.continueStrategy() }
        registry.onFinalizeSpec = { [weak self] in self?.finalizeStrategySpec() }
        registry.onGenerateMockups = { [weak self] in self?.finalizeAndGenerateMockups() }
        registry.onApproveCurrentStage = { [weak self] in self?.approveCurrentStage() }
        registry.onSkipQuestion = { [weak self] in self?.skipStrategyQuestion() }
        registry.onAutoRunStrategy = { [weak self] in self?.autoRunStrategy() }
        registry.onSubmitStrategyAnswer = { [weak self] answer in self?.submitStrategyAnswer(answer) }
        registry.distributionGap = distributionGap
        registry.tokenRevisions = tokenRevisions
        registry.latestBenchmarkReport = latestBenchmarkReport
        registry.benchmarkStatusLine = benchmarkStatusLine
        registry.buildStatusSummary = buildSummary
        registry.latestEnterpriseReadinessReport = latestEnterpriseReadinessReport
        registry.latestBlueprint = latestBlueprint

        chatService.sendBuilderPrompt(context: context, registry: registry)

        if chatService.builderDraft.lowercased().contains("realtime") {
            realTimeBuildEnabled = true
            scheduleRealtimeAnalysis(reason: "builder realtime command")
        }
    }
}
