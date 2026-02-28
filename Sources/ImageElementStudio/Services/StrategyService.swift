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
