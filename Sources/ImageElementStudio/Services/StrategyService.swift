import AppKit
import Foundation

@MainActor
final class StrategyService: ObservableObject {
    // MARK: - Published Properties

    @Published var strategySession: StrategySession?
    @Published var strategyAnswerDraft: String = ""

    // MARK: - Dependencies

    private let strategistEngine: ProductStrategistEngine

    // MARK: - Callbacks

    /// Called when strategy methods need to append a message to the builder chat.
    var onAppendBuilderMessage: ((ChatMessage) -> Void)?

    /// Called when strategy methods need to append a message to the main chat.
    var onAppendMessage: ((ChatMessage) -> Void)?

    /// Called when strategy methods update memory via the memory store.
    var onMemoryUpdated: ((ProjectMemory) -> Void)?

    /// Called when the pipeline mode is set to `.auto` inside `autoRunStrategySession`.
    var onSetPipelineMode: ((PipelineMode) -> Void)?

    /// Called when strategy finalization produces a scope snapshot (from `finalizeStrategySpec`).
    var onScopeProduced: ((ProductScopeSnapshot) -> Void)?

    /// Called after `finalizeStrategySpec` completes or after `autoRunStrategySession`
    /// to trigger mockup generation in the ViewModel.
    var onFinalizeAndGenerateMockups: (() -> Void)?

    // MARK: - Initialization

    init(strategistEngine: ProductStrategistEngine) {
        self.strategistEngine = strategistEngine
    }

    // MARK: - Computed Properties

    var strategyActiveQuestion: StrategyQuestion? {
        guard let strategySession, !strategySession.isComplete else { return nil }
        return strategistEngine.activeQuestion(in: strategySession)
    }

    var strategyStageProgress: Double {
        guard let strategySession else { return 0.0 }
        let index = StrategyStage.allCases.firstIndex(of: strategySession.stage) ?? 0
        return Double(index + (strategySession.isComplete ? 1 : 0)) / Double(StrategyStage.allCases.count)
    }

    var strategyStageLine: String {
        guard let strategySession else { return "Not started" }
        let index = (StrategyStage.allCases.firstIndex(of: strategySession.stage) ?? 0) + 1
        let total = StrategyStage.allCases.count
        return "Stage \(index)/\(total): \(strategySession.stage.title)"
    }

    var strategyControlHint: String {
        guard let strategySession else {
            return "Start with an idea prompt to begin a 6-step product strategy interview."
        }
        if strategySession.isComplete {
            return "Strategy session complete. Finalize spec to generate mockups."
        }
        if let question = strategyActiveQuestion {
            return question.whyAsked
        }
        if strategistEngine.canApproveCurrentStage(strategySession) {
            return "Required questions complete. Approve/Continue to move to the next stage."
        }
        return strategySession.stage.shortInstruction
    }

    // MARK: - Public Methods

    func startStrategyFromIdea(
        _ rawIdea: String,
        projectID: String,
        pipelineMode: PipelineMode,
        memoryStore: ProjectMemoryStore
    ) {
        let idea = rawIdea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idea.isEmpty else {
            onAppendBuilderMessage?(
                ChatMessage(
                    role: .assistant,
                    text: "Describe your app idea first, then I will start a 6-step strategy interview."
                )
            )
            return
        }

        var session = strategistEngine.startSession(projectID: projectID, idea: idea, mode: pipelineMode)

        if pipelineMode == .auto {
            session = strategistEngine.autoRun(session: session)
        }

        strategySession = session
        strategyAnswerDraft = ""
        onMemoryUpdated?(memoryStore.recordUserIntent(idea))
        onMemoryUpdated?(memoryStore.recordStrategySession(session))
        onMemoryUpdated?(memoryStore.recordDecisionLog(
            message: "Started strategy session from idea prompt.",
            stage: session.stage,
            confidence: session.confidence
        ))

        if let question = strategistEngine.activeQuestion(in: session), !session.isComplete {
            onAppendBuilderMessage?(
                ChatMessage(
                    role: .assistant,
                    text: "Strategy started (\(strategyStageLine)). \(question.prompt)"
                )
            )
        } else {
            onAppendBuilderMessage?(
                ChatMessage(
                    role: .assistant,
                    text: "Strategy auto-run completed. Finalize spec to continue."
                )
            )
        }

        if pipelineMode == .auto {
            onFinalizeAndGenerateMockups?()
        }
    }

    func submitStrategyAnswer(_ rawAnswer: String, memoryStore: ProjectMemoryStore) {
        guard let currentSession = strategySession else {
            onAppendBuilderMessage?(ChatMessage(role: .assistant, text: "Start strategy first by providing an idea prompt."))
            return
        }
        guard let question = strategistEngine.activeQuestion(in: currentSession) else {
            onAppendBuilderMessage?(ChatMessage(role: .assistant, text: "No active strategy question. Approve/Continue or finalize spec."))
            return
        }

        let answer = rawAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { return }

        let updated = strategistEngine.submit(
            answerText: answer,
            questionID: question.id,
            in: currentSession
        )
        strategySession = updated
        strategyAnswerDraft = ""
        onMemoryUpdated?(memoryStore.recordStrategySession(updated))
        onMemoryUpdated?(memoryStore.recordDecisionLog(
            message: "Answered strategy question \(question.id).",
            stage: question.stage,
            confidence: updated.answers.last(where: { $0.questionID == question.id })?.confidence
        ))

        if let next = strategistEngine.activeQuestion(in: updated), !updated.isComplete {
            onAppendBuilderMessage?(ChatMessage(role: .assistant, text: next.prompt))
            return
        }

        if strategistEngine.canApproveCurrentStage(updated) {
            onAppendBuilderMessage?(
                ChatMessage(
                    role: .assistant,
                    text: "Stage complete: \(updated.stage.title). Use Approve/Continue for the next stage."
                )
            )
            if updated.pipelineMode == .auto {
                approveCurrentStage(memoryStore: memoryStore)
            }
        }
    }

    func approveCurrentStage(memoryStore: ProjectMemoryStore) {
        guard let currentSession = strategySession else {
            onAppendBuilderMessage?(ChatMessage(role: .assistant, text: "No active strategy session."))
            return
        }

        guard strategistEngine.canApproveCurrentStage(currentSession) else {
            if let next = strategistEngine.activeQuestion(in: currentSession) {
                onAppendBuilderMessage?(ChatMessage(role: .assistant, text: "Answer required question first: \(next.prompt)"))
            }
            return
        }

        let updated = strategistEngine.approveCurrentStage(in: currentSession)
        strategySession = updated
        onMemoryUpdated?(memoryStore.recordStrategySession(updated))
        onMemoryUpdated?(memoryStore.recordDecisionLog(
            message: "Approved strategy stage \(currentSession.stage.title).",
            stage: currentSession.stage,
            confidence: updated.confidence
        ))

        if updated.isComplete {
            onAppendBuilderMessage?(ChatMessage(role: .assistant, text: "All strategy stages complete. Finalize spec to generate mockups."))
            if updated.pipelineMode == .auto {
                onFinalizeAndGenerateMockups?()
            }
            return
        }

        if let question = strategistEngine.activeQuestion(in: updated) {
            onAppendBuilderMessage?(ChatMessage(role: .assistant, text: "Next \(updated.stage.title): \(question.prompt)"))
        }
    }

    func continueStrategy(memoryStore: ProjectMemoryStore) {
        guard let strategySession else {
            onAppendBuilderMessage?(ChatMessage(role: .assistant, text: "No active strategy session. Start with an idea first."))
            return
        }

        if strategySession.isComplete {
            onAppendBuilderMessage?(ChatMessage(role: .assistant, text: "Strategy interview is complete. Finalize spec to continue."))
            return
        }

        if strategistEngine.canApproveCurrentStage(strategySession) {
            approveCurrentStage(memoryStore: memoryStore)
            return
        }

        if let question = strategistEngine.activeQuestion(in: strategySession) {
            onAppendBuilderMessage?(ChatMessage(role: .assistant, text: question.prompt))
        }
    }

    func skipCurrentStrategyQuestion(memoryStore: ProjectMemoryStore) {
        guard let currentSession = strategySession, let question = strategistEngine.activeQuestion(in: currentSession) else {
            return
        }

        let skipped = strategistEngine.submit(
            answerText: "Skipped by user",
            questionID: question.id,
            in: currentSession,
            skipped: true
        )
        strategySession = skipped
        onMemoryUpdated?(memoryStore.recordStrategySession(skipped))
        onMemoryUpdated?(memoryStore.recordDecisionLog(
            message: "Skipped strategy question \(question.id).",
            stage: question.stage,
            confidence: 0.62
        ))

        if let next = strategistEngine.activeQuestion(in: skipped), !skipped.isComplete {
            onAppendBuilderMessage?(ChatMessage(role: .assistant, text: next.prompt))
        } else if strategistEngine.canApproveCurrentStage(skipped) {
            onAppendBuilderMessage?(ChatMessage(role: .assistant, text: "Stage ready to approve."))
        }
    }

    func autoRunStrategySession(memoryStore: ProjectMemoryStore) {
        guard let strategySession else {
            onAppendBuilderMessage?(ChatMessage(role: .assistant, text: "No strategy session found. Start from an idea first."))
            return
        }

        let auto = strategistEngine.autoRun(session: strategySession)
        self.strategySession = auto
        onSetPipelineMode?(.auto)
        onMemoryUpdated?(memoryStore.recordStrategySession(auto))
        onMemoryUpdated?(memoryStore.recordDecisionLog(
            message: "Auto-run completed strategist stages.",
            stage: auto.stage,
            confidence: auto.confidence
        ))
        onAppendBuilderMessage?(ChatMessage(role: .assistant, text: "Auto-run completed. Finalizing strategy spec now."))
        onFinalizeAndGenerateMockups?()
    }

    func finalizeStrategySpec(
        pipelineMode: PipelineMode,
        projectName: String,
        memoryStore: ProjectMemoryStore
    ) {
        guard var session = strategySession else {
            onAppendBuilderMessage?(ChatMessage(role: .assistant, text: "No strategy session to finalize."))
            return
        }

        if !session.isComplete {
            if session.pipelineMode == .auto || pipelineMode == .auto {
                session = strategistEngine.autoRun(session: session)
                strategySession = session
                onMemoryUpdated?(memoryStore.recordStrategySession(session))
            } else {
                onAppendBuilderMessage?(
                    ChatMessage(
                        role: .assistant,
                        text: "Strategy is still in progress. Continue answering questions or use Auto-run."
                    )
                )
                return
            }
        }

        guard let spec = strategistEngine.finalizeSpec(from: session) else {
            onAppendBuilderMessage?(ChatMessage(role: .assistant, text: "Unable to finalize strategy spec. Complete all required stages first."))
            return
        }

        onMemoryUpdated?(memoryStore.recordAcceptedStrategySpec(spec))
        onMemoryUpdated?(memoryStore.recordDecisionLog(
            message: "Finalized strategy spec \(spec.id.uuidString).",
            stage: session.stage,
            confidence: spec.confidence
        ))

        let scope = ProductScopeSnapshot(
            appType: inferredAppType(from: spec),
            confidence: spec.confidence,
            productIntent: spec.vision,
            targetUsers: spec.targetUsers,
            keyCapabilities: spec.mustHaveFeatures,
            openQuestions: spec.laterFeatures.map { "Defer after V1: \($0)" },
            implementationRoadmap: [
                "Validate strategy assumptions with quick mockups.",
                "Generate tokenized screens from approved scope.",
                "Prepare full-stack scaffolds from locked launch scope.",
            ],
            summary: spec.summary
        )
        onScopeProduced?(scope)

        onAppendMessage?(ChatMessage(role: .assistant, text: "Strategy spec finalized for \(projectName)."))
        onAppendBuilderMessage?(
            ChatMessage(
                role: .assistant,
                text: "Strategy spec ready (\(Int((spec.confidence * 100).rounded()))% confidence). Use Generate Mockups to continue."
            )
        )
    }

    // MARK: - Mockup & Pipeline Methods

    /// Finalizes the strategy spec (if not yet done) and then generates mockups from it.
    ///
    /// - Parameters:
    ///   - mockupGenerator: Generates the artboard/token/component result from a planner result.
    ///   - ideaPlanner: Converts the accepted strategy spec into an `IdeaPlannerResult`.
    ///   - pipelineMode: Current pipeline mode (needed by `finalizeStrategySpec`).
    ///   - projectName: Active project name.
    ///   - memoryStore: Project memory store.
    ///   - acceptedStrategySpec: The latest accepted spec, if any.
    ///   - mockupStylePreset: Active mockup style preset.
    ///   - onApplyIdeaPlannerResult: Called with the generated result and spec so the ViewModel can
    ///     apply artboards, tokens, and components to its published state.
    func finalizeAndGenerateMockups(
        mockupGenerator: MockupGenerator,
        ideaPlanner: IdeaPlanner,
        pipelineMode: PipelineMode,
        projectName: String,
        memoryStore: ProjectMemoryStore,
        acceptedStrategySpec: StrategySpec?,
        mockupStylePreset: MockupStylePreset,
        onApplyIdeaPlannerResult: (IdeaPlannerResult, StrategySpec?, MockupStylePreset) -> Void
    ) {
        // Finalize the spec first if one isn't already accepted
        var resolvedSpec = acceptedStrategySpec
        if resolvedSpec == nil {
            finalizeStrategySpec(
                pipelineMode: pipelineMode,
                projectName: projectName,
                memoryStore: memoryStore
            )
            // onScopeProduced callback sets the scope but we need the spec; re-derive it
            if let session = strategySession {
                resolvedSpec = strategistEngine.finalizeSpec(from: session)
            }
        }

        guard let spec = resolvedSpec else { return }
        let generated = ideaPlanner.generate(from: spec, projectName: projectName)
        onApplyIdeaPlannerResult(generated, spec, mockupStylePreset)

        onAppendBuilderMessage?(
            ChatMessage(
                role: .assistant,
                text: "Mockups generated from approved strategy spec. Use Build Project or Generate Full Stack next."
            )
        )
    }

    /// Generates wireframes directly from a raw idea string without a full strategy session.
    ///
    /// - Parameters:
    ///   - rawIdea: The raw idea text entered by the user.
    ///   - ideaPlanner: Converts the idea string into an `IdeaPlannerResult`.
    ///   - projectName: Active project name.
    ///   - mockupStylePreset: Active mockup style preset.
    ///   - onApplyIdeaPlannerResult: Called with the generated result so the ViewModel can update state.
    func generateWireframesFromIdea(
        _ rawIdea: String,
        ideaPlanner: IdeaPlanner,
        projectName: String,
        mockupStylePreset: MockupStylePreset,
        onApplyIdeaPlannerResult: (IdeaPlannerResult, StrategySpec?, MockupStylePreset) -> Void
    ) {
        let idea = rawIdea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idea.isEmpty else {
            onAppendBuilderMessage?(
                ChatMessage(
                    role: .assistant,
                    text: "Describe your app idea and I will generate wireframes and a build plan."
                )
            )
            return
        }

        let generated = ideaPlanner.generate(from: idea, projectName: projectName)
        onApplyIdeaPlannerResult(generated, nil, mockupStylePreset)
    }

    /// Convenience wrapper: shows an idea prompt dialog and starts strategy generation.
    ///
    /// - Parameter onStart: Called with the trimmed idea text when the user confirms.
    func promptIdeaAndGenerate(onStart: (String) -> Void) {
        promptStrategyFromIdea(onStart: onStart)
    }

    /// Shows an NSAlert with a text field, then calls `onStart` with the entered idea.
    ///
    /// - Parameter onStart: Called with the trimmed idea text when the user confirms the dialog.
    func promptStrategyFromIdea(onStart: (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Start Strategy From Idea"
        alert.informativeText =
            "Describe the product idea. I will run a multi-step strategist interview before generating mockups."
        alert.alertStyle = .informational

        let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        inputField.placeholderString = "Example: Build a mobile app for booking personal trainers"
        alert.accessoryView = inputField

        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        onStart(inputField.stringValue)
    }

    /// Applies a finished `IdeaPlannerResult` to the ViewModel's published state.
    ///
    /// All state mutations go through the provided callbacks so this method remains testable
    /// without a live ViewModel.
    ///
    /// - Parameters:
    ///   - generated: The planner result containing artboards, scope, blueprint, and narrative.
    ///   - sourceLabel: A human-readable label for the generation source (e.g. `"idea"`, `"strategy-spec"`).
    ///   - strategySpec: The accepted strategy spec, if any (used during mockup generation).
    ///   - stylePreset: The mockup style preset to apply.
    ///   - mockupGenerator: Produces the tokenized mockup result from the planner result.
    ///   - projectName: Active project name.
    ///   - onStateUpdate: Closure receiving the full mockup result so the ViewModel can publish it.
    ///   - onRecordAnalysis: Closure called to persist an analysis snapshot in memory.
    ///   - onAppendMessages: Closure called once per chat message that should be shown.
    ///   - onRunRealtimeBuildSetupIfNeeded: Called after state is applied to trigger realtime build.
    ///   - onRegenerateJSONPreview: Called to refresh the JSON preview after state is applied.
    func applyIdeaPlannerResult(
        _ generated: IdeaPlannerResult,
        sourceLabel: String,
        strategySpec: StrategySpec?,
        stylePreset: MockupStylePreset,
        mockupGenerator: MockupGenerator,
        projectName: String,
        onStateUpdate: (MockupGenerationResult, IdeaPlannerResult) -> Void,
        onRecordAnalysis: (ProductScopeSnapshot, String, Artboard?) -> Void,
        onAppendMessages: ([ChatMessage]) -> Void,
        onRunRealtimeBuildSetupIfNeeded: () -> Void,
        onRegenerateJSONPreview: () -> Void
    ) {
        let mockupResult = mockupGenerator.generate(
            from: generated,
            strategySpec: strategySpec,
            preset: stylePreset
        )

        // Let the ViewModel apply artboards, tokens, components, and scope.
        onStateUpdate(mockupResult, generated)

        // Persist an analysis snapshot.
        onRecordAnalysis(generated.scope, sourceLabel, mockupResult.artboards.first)

        // Post chat messages summarising the generation.
        let screenNames = mockupResult.artboards.map(\.name).joined(separator: ", ")
        let designSystemLine = "\(stylePreset.title): \(mockupResult.tokens.colors.count) colors, \(mockupResult.components.count) component groups."

        onAppendMessages([
            ChatMessage(
                role: .assistant,
                text: "Mockup generation active: generated \(generated.artboards.count) wireframe artboards."
            ),
            ChatMessage(role: .assistant, text: generated.scope.summary),
            ChatMessage(role: .assistant, text: generated.narrative),
        ])

        onAppendBuilderMessage?(
            ChatMessage(
                role: .assistant,
                text: "Mockups ready. Screens: \(screenNames). \(designSystemLine)"
            )
        )

        onRunRealtimeBuildSetupIfNeeded()
        onRegenerateJSONPreview()
    }

    /// Restyles the current mockup artboards with a new style preset without re-generating content.
    ///
    /// - Parameters:
    ///   - mockupGenerator: Produces the restyled result.
    ///   - artboards: The current artboard array.
    ///   - preset: The new style preset to apply.
    ///   - scope: The product scope snapshot (used as the restyle context).
    ///   - acceptedStrategySpec: The accepted strategy spec, if any.
    ///   - onRestyleComplete: Called with the restyle result so the ViewModel can update artboards,
    ///     tokens, and components and append a token revision.
    ///   - onRegenerateJSONPreview: Called after the restyle to refresh the JSON preview.
    func restyleCurrentMockupsForSelectedPreset(
        mockupGenerator: MockupGenerator,
        artboards: [Artboard],
        preset: MockupStylePreset,
        scope: ProductScopeSnapshot,
        acceptedStrategySpec: StrategySpec?,
        onRestyleComplete: (MockupGenerationResult) -> Void,
        onRegenerateJSONPreview: () -> Void
    ) {
        guard artboards.flatMap(\.elements).contains(where: { $0.kind != .imageRoot }) else { return }

        let result = mockupGenerator.restyle(
            artboards: artboards,
            scope: scope,
            strategySpec: acceptedStrategySpec,
            preset: preset
        )
        onRestyleComplete(result)
        onRegenerateJSONPreview()
    }

    /// Updates the pipeline mode, persisting the change to memory and strategy session.
    ///
    /// - Parameters:
    ///   - mode: The new pipeline mode.
    ///   - currentMode: The currently active pipeline mode (no-op if equal to `mode`).
    ///   - memoryStore: The project memory store.
    ///   - onModeChanged: Called with the new mode so the ViewModel can update its `@Published` property.
    ///   - onMemoryUpdated: Called with the updated memory after recording the decision log.
    func setPipelineMode(
        _ mode: PipelineMode,
        currentMode: PipelineMode,
        memoryStore: ProjectMemoryStore,
        onModeChanged: (PipelineMode) -> Void,
        onMemoryUpdated: (ProjectMemory) -> Void
    ) {
        guard currentMode != mode else { return }
        onModeChanged(mode)

        if var session = strategySession {
            session.pipelineMode = mode
            strategySession = session
            onMemoryUpdated(memoryStore.recordStrategySession(session))
            onMemoryUpdated(
                memoryStore.recordDecisionLog(
                    message: "Pipeline mode set to \(mode.title).",
                    stage: session.stage,
                    confidence: session.confidence
                )
            )
        } else {
            onMemoryUpdated(
                memoryStore.recordDecisionLog(
                    message: "Pipeline mode set to \(mode.title).",
                    stage: nil,
                    confidence: nil
                )
            )
        }
    }

    /// Returns whether the strategy panel should be presented to the user.
    ///
    /// - Parameters:
    ///   - selectedImage: The currently loaded design image, if any.
    ///   - latestScope: The latest product scope snapshot, if any.
    ///   - renderableElementCount: Number of elements on the active artboard.
    /// - Returns: `true` when the strategy panel should be shown.
    func shouldShowStrategyPanel(
        selectedImage: NSImage?,
        latestScope: ProductScopeSnapshot?,
        renderableElementCount: Int
    ) -> Bool {
        if strategySession != nil {
            return true
        }
        let hasMockups = selectedImage != nil || latestScope != nil || renderableElementCount > 1
        return !hasMockups
    }

    // MARK: - Result Structs

    /// Encapsulates all computed values from applying an `IdeaPlannerResult`, so the ViewModel
    /// can destructure and assign without computing anything itself.
    struct AppliedIdeaPlannerResult {
        let mockupResult: MockupGenerationResult
        let scope: ProductScopeSnapshot
        let blueprint: BuildBlueprint
        let imageDescriptor: ImageDescriptor
        let metadata: AnalysisMetadata
        let tokenRevision: TokenRevision
        let chatMessages: [ChatMessage]
        let builderMessage: ChatMessage
    }

    /// Computes all derived values from an `IdeaPlannerResult` without touching ViewModel state.
    static func computeAppliedResult(
        from generated: IdeaPlannerResult,
        sourceLabel: String,
        strategySpec: StrategySpec?,
        stylePreset: MockupStylePreset,
        mockupGenerator: MockupGenerator,
        designSystemStatusLine: String
    ) -> AppliedIdeaPlannerResult {
        let mockupResult = mockupGenerator.generate(from: generated, strategySpec: strategySpec, preset: stylePreset)
        let imageDescriptor = ImageDescriptor(
            filename: "\(sourceLabel)-wireframe",
            width: mockupResult.artboards.first?.width ?? 1366,
            height: mockupResult.artboards.first?.height ?? 900
        )
        let metadata = AnalysisMetadata(
            generatedAt: Date(),
            engine: "Idea Planner + Mockup Generator",
            notes: ["Generated wireframes from \(sourceLabel).", "Applied design tokens and semantic component mapping."]
        )
        let tokenRevision = TokenRevision(id: UUID(), createdAt: Date(), reason: "Initial generated token set", tokens: mockupResult.tokens)
        let chatMessages = [
            ChatMessage(role: .assistant, text: "Mockup generation active: generated \(generated.artboards.count) wireframe artboards."),
            ChatMessage(role: .assistant, text: generated.scope.summary),
            ChatMessage(role: .assistant, text: generated.narrative),
        ]
        let builderMessage = ChatMessage(role: .assistant, text: "Mockups ready. Screens: \(mockupResult.artboards.map(\.name).joined(separator: ", ")). \(designSystemStatusLine)")
        return AppliedIdeaPlannerResult(
            mockupResult: mockupResult, scope: generated.scope, blueprint: generated.blueprint,
            imageDescriptor: imageDescriptor, metadata: metadata, tokenRevision: tokenRevision,
            chatMessages: chatMessages, builderMessage: builderMessage
        )
    }

    /// Restyles artboards with a new preset, returning the result directly (nil if no non-imageRoot elements exist).
    func restyleResult(
        mockupGenerator: MockupGenerator,
        artboards: [Artboard],
        preset: MockupStylePreset,
        scope: ProductScopeSnapshot,
        acceptedStrategySpec: StrategySpec?
    ) -> MockupGenerationResult? {
        guard artboards.flatMap(\.elements).contains(where: { $0.kind != .imageRoot }) else { return nil }
        return mockupGenerator.restyle(artboards: artboards, scope: scope, strategySpec: acceptedStrategySpec, preset: preset)
    }

    // MARK: - Private Helpers

    private func inferredAppType(from spec: StrategySpec) -> String {
        let hint = "\(spec.vision) \(spec.mustHaveFeatures.joined(separator: " "))".lowercased()
        if hint.contains("dashboard") || hint.contains("analytics") || hint.contains("kpi") {
            return "Business Analytics Dashboard"
        }
        if hint.contains("shop") || hint.contains("checkout") || hint.contains("commerce") {
            return "E-commerce Platform"
        }
        if hint.contains("task") || hint.contains("project") || hint.contains("workflow") {
            return "Project Management Workspace"
        }
        if hint.contains("social") || hint.contains("feed") || hint.contains("community") {
            return "Social Collaboration App"
        }
        return "Product Experience App"
    }
}
