import Foundation
import AppKit

@MainActor
final class ChatService: ObservableObject {
    @Published var messages: [ChatMessage]
    @Published var draftMessage: String = ""
    @Published var builderMessages: [ChatMessage]
    @Published var builderDraft: String = ""

    // MARK: - Context

    /// Context provided by StudioViewModel for generating chat responses
    struct ChatContext {
        let projectName: String
        let strategySession: StrategySession?
        let strategyActiveQuestion: StrategyQuestion?
        let pipelineMode: PipelineMode
        let latestScope: ProductScopeSnapshot?
        let memory: ProjectMemory
        let benchmarkStatusLine: String
        let componentInstances: [ComponentInstance]
        let componentSystemStatusLine: String
        let latestBlueprint: BuildBlueprint?
        let enterpriseReadinessStatusLine: String
    }

    /// Context for builder commands that need to trigger actions
    struct BuilderCommandContext {
        let isAnalyzing: Bool
        let pipelineMode: PipelineMode
        let selectedImage: NSImage?
        let acceptedStrategySpec: StrategySpec?
        let renderableElements: [CanvasElement]
        let latestScope: ProductScopeSnapshot?
        let strategySession: StrategySession?
        let strategyActiveQuestion: StrategyQuestion?
        let projectName: String
    }

    /// Registry that holds all builder command handlers and supporting data,
    /// replacing the previous 30+ individual closure parameters.
    struct BuilderCommandRegistry {
        // MARK: - Command handlers

        var onSetPipelineMode: (PipelineMode) -> Void = { _ in }
        var onGenerateFullStackBuild: () -> Void = {}
        var onRunBuilderBuildCommand: () -> Void = {}
        var onRunBuilderAnalyzeCommand: () -> Void = {}
        var onAddArtboard: () -> Void = {}
        var onGenerateStateArtboards: () -> Void = {}
        var onDistributeHorizontally: () -> Void = {}
        var onDistributeVertically: () -> Void = {}
        var onSpaceHorizontally: (CGFloat) -> Void = { _ in }
        var onSpaceVertically: (CGFloat) -> Void = { _ in }
        var onCreateComponent: () -> Void = {}
        var onCreateComponentInstance: () -> Void = {}
        var onRunBenchmark: () -> Void = {}
        var onAutoFixBenchmark: () -> Void = {}
        var onUpdateInstanceOverride: (String, String) -> Void = { _, _ in }
        var onApplyOverridesToAll: () -> Void = {}
        var onRollbackTokenRevision: (UUID?) -> Void = { _ in }
        var onExportInterop: () -> Void = {}
        var onSetReviewApprovalState: (ReviewApprovalState) -> Bool = { _ in true }
        var onDuplicateArtboard: () -> Void = {}
        var onExportJSON: () -> Void = {}
        var onSaveProject: () -> Void = {}
        var onClearProjectMemory: () -> Void = {}
        var onCreateNewProject: () -> Void = {}
        var onStartStrategy: (String) -> Void = { _ in }
        var onContinueStrategy: () -> Void = {}
        var onFinalizeSpec: () -> Void = {}
        var onGenerateMockups: () -> Void = {}
        var onApproveCurrentStage: () -> Void = {}
        var onSkipQuestion: () -> Void = {}
        var onAutoRunStrategy: () -> Void = {}
        var onSubmitStrategyAnswer: (String) -> Void = { _ in }

        // MARK: - Supporting data

        var distributionGap: CGFloat = 10
        var tokenRevisions: [TokenRevision] = []
        var latestBenchmarkReport: BenchmarkRunReport?
        var benchmarkStatusLine: String = ""
        var buildStatusSummary: String = ""
        var latestEnterpriseReadinessReport: EnterpriseReadinessReport?
        var latestBlueprint: BuildBlueprint?
    }

    // MARK: - Initialization

    init(projectName: String) {
        self.messages = Self.initialMessages(for: projectName)
        self.builderMessages = Self.initialBuilderMessages(for: projectName)
    }

    // MARK: - Public Methods

    func sendMessage(
        context: ChatContext,
        memoryStore: ProjectMemoryStore,
        onMemoryUpdate: @escaping (ProjectMemory) -> Void
    ) {
        let trimmed = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(ChatMessage(role: .user, text: trimmed))
        draftMessage = ""

        // Record user intent in memory
        let updatedMemory = memoryStore.recordUserIntent(trimmed)
        onMemoryUpdate(updatedMemory)

        let response = assistantReply(for: trimmed, context: context)
        messages.append(ChatMessage(role: .assistant, text: response))
    }

    func sendBuilderPrompt(
        context: BuilderCommandContext,
        registry: BuilderCommandRegistry
    ) {
        let trimmed = builderDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        builderMessages.append(ChatMessage(role: .user, text: trimmed))
        builderDraft = ""

        let normalized = trimmed.lowercased()

        // Pipeline mode commands
        if normalized.contains("set mode auto") || normalized == "mode auto" {
            registry.onSetPipelineMode(.auto)
            builderMessages.append(ChatMessage(role: .assistant, text: "Pipeline mode set to Auto."))
            return
        }

        if normalized.contains("set mode guided") || normalized == "mode guided" {
            registry.onSetPipelineMode(.guided)
            builderMessages.append(ChatMessage(role: .assistant, text: "Pipeline mode set to Guided."))
            return
        }

        if normalized.contains("set mode hybrid") || normalized == "mode hybrid" {
            registry.onSetPipelineMode(.hybrid)
            builderMessages.append(ChatMessage(role: .assistant, text: "Pipeline mode set to Hybrid."))
            return
        }

        // Full stack build command
        if normalized.contains("build full app")
            || normalized.contains("full app build")
            || normalized.contains("build full stack")
            || normalized.contains("generate full app")
            || normalized.contains("full stack") {
            registry.onGenerateFullStackBuild()
            return
        }

        // Enterprise report
        if normalized.contains("enterprise") && normalized.contains("report") {
            if let report = registry.latestEnterpriseReadinessReport {
                let score = Int(report.score.rounded())
                builderMessages.append(
                    ChatMessage(
                        role: .assistant,
                        text: "Enterprise report: \(report.status.rawValue.capitalized) (\(score))."
                    )
                )
            } else {
                builderMessages.append(ChatMessage(role: .assistant, text: "No enterprise report yet. Run 'build full app' first."))
            }
            return
        }

        // Build command
        if normalized == "build" || normalized.contains("build it") || normalized.contains("run build") {
            runBuilderBuildCommand(
                context: context,
                onRunBuild: registry.onRunBuilderBuildCommand
            )
            return
        }

        // Analyze command
        if normalized.contains("analyze") {
            runBuilderAnalyzeCommand(
                context: context,
                onRunAnalyze: registry.onRunBuilderAnalyzeCommand
            )
            return
        }

        // Artboard commands
        if normalized.contains("new artboard") {
            registry.onAddArtboard()
            builderMessages.append(ChatMessage(role: .assistant, text: "Created a new artboard and saved a project snapshot."))
            return
        }

        if normalized.contains("state artboard") || normalized.contains("generate states") {
            guard registry.latestBlueprint != nil else {
                builderMessages.append(ChatMessage(role: .assistant, text: "Run analyze/build first so I can infer controls and states."))
                return
            }
            registry.onGenerateStateArtboards()
            builderMessages.append(ChatMessage(role: .assistant, text: "Generated suggested state artboards from the current mirror blueprint."))
            return
        }

        // Distribution commands
        if normalized.contains("distribute h") || normalized.contains("distribute horizontal") {
            registry.onDistributeHorizontally()
            builderMessages.append(ChatMessage(role: .assistant, text: "Applied horizontal distribution on selected elements."))
            return
        }

        if normalized.contains("distribute v") || normalized.contains("distribute vertical") {
            registry.onDistributeVertically()
            builderMessages.append(ChatMessage(role: .assistant, text: "Applied vertical distribution on selected elements."))
            return
        }

        if normalized.contains("space horizontal") {
            registry.onSpaceHorizontally(registry.distributionGap)
            builderMessages.append(ChatMessage(role: .assistant, text: "Applied horizontal spacing gap \(Int(registry.distributionGap))."))
            return
        }

        if normalized.contains("space vertical") {
            registry.onSpaceVertically(registry.distributionGap)
            builderMessages.append(ChatMessage(role: .assistant, text: "Applied vertical spacing gap \(Int(registry.distributionGap))."))
            return
        }

        // Component commands
        if normalized.contains("create component") {
            registry.onCreateComponent()
            builderMessages.append(ChatMessage(role: .assistant, text: "Created component from current selection."))
            return
        }

        if normalized.contains("new instance") || normalized.contains("create instance") {
            registry.onCreateComponentInstance()
            builderMessages.append(ChatMessage(role: .assistant, text: "Created component instance from selected component."))
            return
        }

        // Benchmark commands
        if normalized.contains("benchmark") || normalized.contains("pro editing check") {
            registry.onRunBenchmark()
            if let report = registry.latestBenchmarkReport {
                builderMessages.append(ChatMessage(role: .assistant, text: "Benchmark: \(registry.benchmarkStatusLine)."))
                if let failed = report.steps.first(where: { !$0.passed }) {
                    builderMessages.append(ChatMessage(role: .assistant, text: "First failing step: \(failed.title) - \(failed.detail)"))
                }
            }
            return
        }

        if normalized.contains("fix benchmark") || normalized.contains("auto-fix benchmark") {
            registry.onAutoFixBenchmark()
            builderMessages.append(ChatMessage(role: .assistant, text: "Auto-fix executed. Benchmark: \(registry.benchmarkStatusLine)."))
            return
        }

        // Instance override commands
        if normalized.hasPrefix("override ") {
            let payload = String(trimmed.dropFirst("override ".count))
            let parts = payload.split(separator: "=", maxSplits: 1).map { String($0) }
            if parts.count == 2 {
                registry.onUpdateInstanceOverride(parts[0], parts[1])
                builderMessages.append(ChatMessage(role: .assistant, text: "Applied instance override \(parts[0])."))
            } else {
                builderMessages.append(ChatMessage(role: .assistant, text: "Use override syntax: override key=value"))
            }
            return
        }

        if normalized.contains("apply overrides all") {
            registry.onApplyOverridesToAll()
            builderMessages.append(ChatMessage(role: .assistant, text: "Applied selected instance overrides to all sibling instances."))
            return
        }

        // Token revision rollback
        if normalized.contains("rollback token") {
            if let revision = registry.tokenRevisions.last {
                registry.onRollbackTokenRevision(revision.id)
                builderMessages.append(ChatMessage(role: .assistant, text: "Rolled back to latest token revision snapshot."))
            } else {
                builderMessages.append(ChatMessage(role: .assistant, text: "No token revision snapshots found yet."))
            }
            return
        }

        // Export commands
        if normalized.contains("export interop") || normalized.contains("export package") {
            registry.onExportInterop()
            builderMessages.append(ChatMessage(role: .assistant, text: "Opened export dialog for interop package."))
            return
        }

        // Review approval commands
        if normalized.contains("approve review") || normalized.contains("approve") && normalized.contains("review") {
            if registry.onSetReviewApprovalState(.approved) {
                builderMessages.append(ChatMessage(role: .assistant, text: "Review state set to approved."))
            } else {
                builderMessages.append(ChatMessage(role: .assistant, text: "Approval blocked: resolve open comments first."))
            }
            return
        }

        if normalized.contains("request changes") || normalized.contains("changes requested") {
            _ = registry.onSetReviewApprovalState(.changesRequested)
            builderMessages.append(ChatMessage(role: .assistant, text: "Review state set to changes requested."))
            return
        }

        // Artboard duplication
        if normalized.contains("duplicate artboard") {
            registry.onDuplicateArtboard()
            builderMessages.append(ChatMessage(role: .assistant, text: "Duplicated active artboard and saved a project snapshot."))
            return
        }

        // Export JSON
        if normalized.contains("export") && normalized.contains("json") {
            registry.onExportJSON()
            builderMessages.append(ChatMessage(role: .assistant, text: "Opened export dialog for JSON."))
            return
        }

        // Project management
        if normalized.contains("save project") {
            registry.onSaveProject()
            builderMessages.append(ChatMessage(role: .assistant, text: "Opened save dialog for the full project package."))
            return
        }

        if normalized.contains("clear memory") || normalized.contains("reset memory") {
            registry.onClearProjectMemory()
            builderMessages.append(ChatMessage(role: .assistant, text: "Project memory cleared for '\(context.projectName)'."))
            return
        }

        if normalized.contains("new project") {
            registry.onCreateNewProject()
            builderMessages.append(ChatMessage(role: .assistant, text: "Started a new project with clean memory and workspace."))
            return
        }

        // Strategy commands
        if normalized.contains("start strategy") {
            let ideaPrompt = extractIdeaPrompt(from: trimmed)
            registry.onStartStrategy(ideaPrompt)
            return
        }

        if normalized.contains("continue strategy") {
            registry.onContinueStrategy()
            return
        }

        if normalized.contains("finalize spec") {
            registry.onFinalizeSpec()
            return
        }

        if normalized.contains("generate mockups") {
            registry.onGenerateMockups()
            return
        }

        if normalized.contains("status") || normalized.contains("step") {
            builderMessages.append(ChatMessage(role: .assistant, text: registry.buildStatusSummary))
            return
        }

        // Realtime build - note: this is handled in ViewModel, not here
        if normalized.contains("realtime") {
            builderMessages.append(ChatMessage(role: .assistant, text: "Realtime build is always on. Queued a refresh pass."))
            return
        }

        // Strategy session interactions
        if let strategySession = context.strategySession, !strategySession.isComplete {
            if normalized == "approve"
                || normalized == "continue"
                || normalized == "approve/continue"
                || normalized == "next stage" {
                registry.onApproveCurrentStage()
                return
            }
            if normalized == "skip" || normalized.contains("skip question") {
                registry.onSkipQuestion()
                return
            }
            if normalized.contains("auto-run") || normalized.contains("autorun") {
                registry.onAutoRunStrategy()
                return
            }

            registry.onSubmitStrategyAnswer(trimmed)
            return
        }

        // Idea extraction and strategy start
        if normalized.hasPrefix("idea:")
            || normalized.hasPrefix("app idea:")
            || normalized.contains("build an app")
            || normalized.contains("i want to build")
            || (context.selectedImage == nil && context.latestScope == nil) {
            let prompt = extractIdeaPrompt(from: trimmed)
            registry.onStartStrategy(prompt)
            return
        }

        // Fallback to general assistant reply
        let chatContext = ChatContext(
            projectName: context.projectName,
            strategySession: context.strategySession,
            strategyActiveQuestion: context.strategyActiveQuestion,
            pipelineMode: context.pipelineMode,
            latestScope: context.latestScope,
            memory: ProjectMemory(
                createdAt: Date(),
                updatedAt: Date(),
                projectID: UUID().uuidString,
                projectName: context.projectName,
                workingHypothesis: "",
                latestSummary: "",
                productScope: [],
                entries: [],
                strategySessions: context.strategySession.map { [$0] } ?? [],
                acceptedStrategySpecs: [],
                decisionLog: []
            ),
            benchmarkStatusLine: registry.benchmarkStatusLine,
            componentInstances: [],
            componentSystemStatusLine: "",
            latestBlueprint: registry.latestBlueprint,
            enterpriseReadinessStatusLine: ""
        )
        let fallback = assistantReply(for: trimmed, context: chatContext)
        builderMessages.append(ChatMessage(role: .assistant, text: fallback))
    }

    func clearChatHistory(projectName: String, memoryLatestSummary: String) {
        messages = Self.initialMessages(for: projectName)
        if !memoryLatestSummary.isEmpty {
            messages.append(
                ChatMessage(role: .assistant, text: "Memory context retained: \(memoryLatestSummary)")
            )
        }
        draftMessage = ""
    }

    func clearBuilderConversation(projectName: String) {
        builderMessages = Self.initialBuilderMessages(for: projectName)
        builderDraft = ""
    }

    // MARK: - Private Helpers

    private func assistantReply(for prompt: String, context: ChatContext) -> String {
        let normalized = prompt.lowercased()

        if normalized.contains("strategy") || normalized.contains("interview") {
            if let strategySession = context.strategySession {
                let stage = strategySession.stage.title
                if strategySession.isComplete {
                    return "Strategy interview is complete. Finalize spec or generate mockups to continue."
                }
                if let question = context.strategyActiveQuestion {
                    return "Strategy stage: \(stage). Next question: \(question.prompt)"
                }
                return "Strategy stage \(stage) is ready for approval."
            }
            return "No active strategy session. Type your idea and I will start the 6-step strategist flow."
        }

        if normalized.contains("pipeline mode") || normalized == "mode" || normalized.hasPrefix("mode ") {
            return "Current pipeline mode is \(context.pipelineMode.title). Available: Auto, Guided, Hybrid."
        }

        if normalized.contains("what app") || normalized.contains("type of app") {
            if let scope = context.latestScope {
                return "It looks like a \(scope.appType) (\(Int((scope.confidence * 100).rounded()))% confidence). Intent: \(scope.productIntent)"
            }
            return "Run Analyze Image first and I will classify the app type and intent."
        }

        if normalized.contains("scope") || normalized.contains("features") {
            guard let scope = context.latestScope else {
                return "No semantic scope yet. Analyze an image and I will map capabilities and roadmap."
            }
            return "Current scope: \(scope.keyCapabilities.prefix(4).joined(separator: ", "))."
        }

        if normalized.contains("memory") || normalized.contains("remember") {
            if context.memory.entries.isEmpty {
                return "Project '\(context.projectName)' memory is active, but there are no snapshots yet."
            }
            return "Project '\(context.projectName)' memory has \(context.memory.entries.count) snapshots. Latest: \(context.memory.latestSummary)"
        }

        if normalized.contains("benchmark") || normalized.contains("pro editing") {
            return "Run 'benchmark' to execute the in-app pro editing benchmark. Current: \(context.benchmarkStatusLine)"
        }

        if normalized.contains("component") && normalized.contains("instance") {
            if context.componentInstances.isEmpty {
                return "No component instances yet. Create a component from selection, then create an instance."
            }
            return "Component system: \(context.componentSystemStatusLine). Selected instance overrides can be applied with 'override key=value'."
        }

        if normalized.contains("mirror") || normalized.contains("exact") {
            guard let blueprint = context.latestBlueprint else {
                return "Run Analyze Image and I will score mirror fidelity, controls, and inferred states."
            }
            let score = Int((blueprint.mirrorScore * 100).rounded())
            return "Mirror fidelity is \(score)%. I mapped \(blueprint.controls.count) controls and \(blueprint.states.count) state candidates from this screenshot."
        }

        if normalized.contains("state") || normalized.contains("artboard") {
            guard let blueprint = context.latestBlueprint else {
                return "No inferred states yet. Analyze the image and I can generate state artboards."
            }
            return "I inferred \(blueprint.states.count) states and \(blueprint.suggestedArtboards.count) suggested state artboards."
        }

        if normalized.contains("next") || normalized.contains("roadmap") {
            guard let roadmap = context.latestScope?.implementationRoadmap, !roadmap.isEmpty else {
                return "Analyze an image first and I will generate a scoped roadmap."
            }
            return "Next steps: \(roadmap.prefix(3).joined(separator: " | "))"
        }

        if normalized.contains("json") {
            return "Use Analyze Image to produce semantic JSON, then export from the right panel."
        }

        if normalized.contains("save") && normalized.contains("project") {
            return "Use Save Project to write a full project package (artboards, memory, scope, and blueprint) to JSON."
        }

        if normalized.contains("new project") {
            return "Use New Project to create a clean project context with isolated memory."
        }

        if normalized.contains("clear memory") || normalized.contains("reset memory") {
            return "Use Clear Project Memory to wipe snapshots and memory notes for the active project."
        }

        if normalized.contains("idea") || normalized.contains("wireframe") || normalized.contains("mockup") {
            return "Type your app idea in the builder chat and I will start strategy interview, finalize spec, then generate wireframe mockups."
        }

        if normalized.contains("figma") || normalized.contains("illustrator") || normalized.contains("adobe") {
            return "Drop design files directly (PNG/JPG/PDF/AI/SVG/FIG/JSON). Realtime build can auto-run analysis and scaffold updates."
        }

        if normalized.contains("full app") || normalized.contains("full stack") {
            return "Run 'build full app' to generate web + iOS + macOS full-app outputs with a deterministic full-stack summary."
        }

        if normalized.contains("enterprise") {
            return "Enterprise gate status: \(context.enterpriseReadinessStatusLine). Use 'build full app' to refresh enterprise-readiness-report.json."
        }

        return "I can classify the UI, map semantic components, and keep product memory as we iterate from design to code."
    }

    private func runBuilderBuildCommand(
        context: BuilderCommandContext,
        onRunBuild: @escaping () -> Void
    ) {
        if context.isAnalyzing {
            builderMessages.append(ChatMessage(role: .assistant, text: "Build already running. Waiting for current pass to finish."))
            return
        }

        if context.pipelineMode == .guided, context.selectedImage == nil, context.acceptedStrategySpec == nil {
            builderMessages.append(ChatMessage(role: .assistant, text: "Guided mode requires approved strategy spec before build. Complete the strategist flow first."))
            return
        }

        if context.selectedImage == nil {
            let hasIdeaWireframes = context.renderableElements.count > 1 && context.latestScope != nil
            if hasIdeaWireframes {
                builderMessages.append(ChatMessage(role: .assistant, text: "No uploaded design found, using idea-generated wireframes for build setup."))
                onRunBuild()
                return
            }
            if let strategySession = context.strategySession, !strategySession.isComplete {
                if let question = context.strategyActiveQuestion {
                    builderMessages.append(ChatMessage(role: .assistant, text: "Strategy in progress. Next question: \(question.prompt)"))
                } else {
                    builderMessages.append(ChatMessage(role: .assistant, text: "Strategy stage ready. Use Approve/Continue, then finalize spec."))
                }
            } else {
                builderMessages.append(ChatMessage(role: .assistant, text: "No input yet. Upload a design or describe your app idea, then type 'build'."))
            }
            return
        }

        builderMessages.append(ChatMessage(role: .assistant, text: "Starting build pipeline: OCR -> semantic mapping -> scope -> JSON."))
        onRunBuild()
    }

    private func runBuilderAnalyzeCommand(
        context: BuilderCommandContext,
        onRunAnalyze: @escaping () -> Void
    ) {
        guard context.selectedImage != nil else {
            let hasIdeaWireframes = context.renderableElements.count > 1 && context.latestScope != nil
            if hasIdeaWireframes {
                builderMessages.append(ChatMessage(role: .assistant, text: "Idea wireframes already generated. Refine your prompt or run build."))
            } else if let strategySession = context.strategySession, !strategySession.isComplete {
                builderMessages.append(ChatMessage(role: .assistant, text: "Strategy interview is in progress. Finish strategy or switch to Auto-run first."))
            } else {
                builderMessages.append(ChatMessage(role: .assistant, text: "Upload a design or type your idea to start analysis/build."))
            }
            return
        }
        if context.isAnalyzing {
            builderMessages.append(ChatMessage(role: .assistant, text: "Analysis already in progress."))
            return
        }
        builderMessages.append(ChatMessage(role: .assistant, text: "Running analysis now."))
        onRunAnalyze()
    }



    static func initialMessages(for projectName: String) -> [ChatMessage] {
        [
            ChatMessage(role: .system, text: "Describe an idea to start strategist interview, then approve spec and generate mockups/build artifacts."),
            ChatMessage(role: .assistant, text: "Project '\(projectName)' is active. Flow: idea -> strategy -> mockups -> build setup."),
        ]
    }

    static func initialBuilderMessages(for projectName: String) -> [ChatMessage] {
        [
            ChatMessage(
                role: .assistant,
                text: "Builder ready for '\(projectName)'. Type your idea to start strategy (example: idea: build a food delivery app)."
            ),
        ]
    }

    private func extractIdeaPrompt(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("idea:") {
            return String(trimmed.dropFirst("idea:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed.lowercased().hasPrefix("app idea:") {
            return String(trimmed.dropFirst("app idea:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }
}
