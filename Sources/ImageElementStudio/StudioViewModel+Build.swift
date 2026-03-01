import AppKit
import Foundation
import SwiftUI

extension StudioViewModel {

    // MARK: - Strategy-Driven Build

    func finalizeAndGenerateMockups() {
        strategyService.finalizeAndGenerateMockups(mockupGenerator: mockupGenerator, ideaPlanner: ideaPlanner, pipelineMode: pipelineMode, projectName: projectName, memoryStore: memoryStore, acceptedStrategySpec: acceptedStrategySpec, mockupStylePreset: mockupStylePreset,
            onApplyIdeaPlannerResult: { [weak self] generated, spec, preset in self?.applyIdeaPlannerResult(generated, sourceLabel: "strategy-spec", strategySpec: spec, stylePreset: preset) })
    }

    func generateWireframesFromIdea(_ rawIdea: String) {
        strategyService.generateWireframesFromIdea(rawIdea, ideaPlanner: ideaPlanner, projectName: projectName, mockupStylePreset: mockupStylePreset,
            onApplyIdeaPlannerResult: { [weak self] generated, spec, preset in self?.applyIdeaPlannerResult(generated, sourceLabel: "idea", strategySpec: spec, stylePreset: preset) })
    }

    func promptIdeaAndGenerate() { promptStrategyFromIdea() }

    func promptStrategyFromIdea() { strategyService.promptStrategyFromIdea { [weak self] idea in self?.startStrategyFromIdea(idea) } }

    func applyIdeaPlannerResult(_ generated: IdeaPlannerResult, sourceLabel: String, strategySpec: StrategySpec?, stylePreset: MockupStylePreset) {
        errorMessage = nil; selectedImage = nil; selectedImageURL = nil; clearElementSelection()
        resetAnalysisAndReviewState()
        let r = StrategyService.computeAppliedResult(from: generated, sourceLabel: sourceLabel, strategySpec: strategySpec, stylePreset: stylePreset, mockupGenerator: mockupGenerator, designSystemStatusLine: designSystemStatusLine)
        artboards = r.mockupResult.artboards; selectedArtboardID = r.mockupResult.artboards.first?.id
        latestScope = r.scope; latestBlueprint = r.blueprint; latestDesignTokens = r.mockupResult.tokens
        tokenRevisions = [r.tokenRevision]; latestComponentSpecs = r.mockupResult.components; componentInstances = []
        latestImageDescriptor = r.imageDescriptor; latestMetadata = r.metadata
        memory = memoryStore.recordAnalysis(scope: r.scope, imageName: sourceLabel, artboard: r.mockupResult.artboards.first)
        r.chatMessages.forEach { messages.append($0) }; builderMessages.append(r.builderMessage)

        runRealtimeBuildSetupIfNeeded(); regenerateJSONPreview()
    }

    func restyleCurrentMockupsForSelectedPreset() {
        guard let scope = latestScope ?? designTokenService.fallbackScopeForTokenization(acceptedStrategySpec: acceptedStrategySpec) else { return }
        guard let result = strategyService.restyleResult(mockupGenerator: mockupGenerator, artboards: artboards, preset: mockupStylePreset, scope: scope, acceptedStrategySpec: acceptedStrategySpec) else { return }
        artboards = result.artboards; selectedArtboardID = selectedArtboardID ?? artboards.first?.id
        latestDesignTokens = result.tokens; latestComponentSpecs = result.components
        tokenRevisions.append(TokenRevision(id: UUID(), createdAt: Date(), reason: "Restyle \(mockupStylePreset.title)", tokens: result.tokens))
        regenerateJSONPreview()
    }

    // MARK: - Full-Stack Build

    func generateFullStackBuild() {
        if acceptedStrategySpec == nil || (latestScope == nil && renderableElements.count <= 1) { finalizeAndGenerateMockups() }
        guard !isSettingUpBuild else { return }
        guard canExportBuildArtifacts else {
            let reason = reviewGateBlockReason ?? "Review gate is blocking export."
            let message = "Full-stack export blocked. \(reason)"
            errorMessage = message; builderMessages.append(ChatMessage(role: .assistant, text: message)); messages.append(ChatMessage(role: .assistant, text: message))
            return
        }
        isSettingUpBuild = true; latestFullStackBuildSummary = nil; latestEnterpriseReadinessReport = nil
        do {
            let result = try buildExportService.generateFullStackBuild(context: makeBuildContext())
            latestFullStackBuildSummary = result.summary; latestEnterpriseReadinessReport = result.enterpriseReport
            let outcome = result.summary.allTargetsPassed ? "passed" : "requires fixes"
            builderMessages.append(ChatMessage(role: .assistant, text: "Full-stack run \(outcome). Score \(Int(result.summary.aggregateScore.rounded())) across \(result.summary.targetResults.count) targets. \(enterpriseReadinessStatusLine). Output: \(result.rootOutputDirectory.path)"))
            messages.append(ChatMessage(role: .assistant, text: "Full-stack build complete at \(result.rootOutputDirectory.path). Artifacts: full-stack-summary.json, enterprise-readiness-report.json"))
            memory = memoryStore.recordDecisionLog(message: "Generated full-stack run (\(outcome)) with score \(Int(result.summary.aggregateScore.rounded())) at \(result.rootOutputDirectory.lastPathComponent).", stage: strategySession?.stage, confidence: acceptedStrategySpec?.confidence)
            NSWorkspace.shared.activateFileViewerSelecting([result.rootOutputDirectory])
        } catch {
            errorMessage = "Full-stack generation failed: \(error.localizedDescription)"
            builderMessages.append(ChatMessage(role: .assistant, text: "Full-stack generation failed: \(error.localizedDescription)"))
        }
        isSettingUpBuild = false
    }

    // MARK: - AI Code Generation

    func generateAndBuildFromCurrentImage() {
        guard !isGeneratingApp else { return }
        guard renderableElements.count > 1 || acceptedStrategySpec != nil || selectedImage != nil else {
            errorMessage = "Upload and analyze a design, or generate from an idea first."; return
        }
        guard KeychainService.resolveAPIKey(for: .anthropicAPIKey) != nil else {
            errorMessage = "No Anthropic API key configured. Open Settings to add one."; showSettingsSheet = true; return
        }
        isGeneratingApp = true; showBuildOutput = true; errorMessage = nil
        let appName = projectName.isEmpty ? "GeneratedApp" : projectName
        let qualityRaw = UserDefaults.standard.string(forKey: "generationQuality") ?? AIGenerationQuality.fast.rawValue
        let quality = AIGenerationQuality(rawValue: qualityRaw) ?? .fast
        let target = realTimeBuildTarget; let screenshotData: Data? = selectedImage?.jpegData()
        builderMessages.append(ChatMessage(role: .assistant, text: "Starting AI code generation for \(target.title) app: \(appName)..."))
        Task {
            let generatedFiles = await codeGenerationPipeline.generateApp(elements: renderableElements, artboards: artboards, tokens: latestDesignTokens, components: latestComponentSpecs, blueprint: latestBlueprint, target: target, appName: appName, quality: quality, screenshotData: screenshotData)
            guard !generatedFiles.isEmpty else {
                isGeneratingApp = false
                let failMessage = codeGenerationPipeline.errorMessage ?? "Code generation produced no files."
                errorMessage = failMessage; builderMessages.append(ChatMessage(role: .assistant, text: "Code generation failed: \(failMessage)")); return
            }
            builderMessages.append(ChatMessage(role: .assistant, text: "Generated \(generatedFiles.count) files. Writing to disk and starting build..."))
            let projectDirectory: URL
            do { projectDirectory = try GeneratedProjectWriter.writeProjectToDisk(files: generatedFiles, appName: appName, target: target) } catch {
                isGeneratingApp = false; errorMessage = "Failed to write project: \(error.localizedDescription)"
                builderMessages.append(ChatMessage(role: .assistant, text: "Failed to write project to disk: \(error.localizedDescription)")); return
            }
            let scheme = appName
            let bundleID = "com.imageelementstudio.\(appName.lowercased().replacingOccurrences(of: " ", with: ""))"
            let sdk: XcodeToolchainService.SDK = (target == .macos) ? .macosx : .iphonesimulator
            let success = await buildPipelineCoordinator.runFullPipeline(projectDirectory: projectDirectory, scheme: scheme, bundleID: bundleID, sdk: sdk, onBuildError: { [weak self] _ in
                await MainActor.run { self?.builderMessages.append(ChatMessage(role: .assistant, text: "Build failed. Attempting AI-powered fix...")) }
                return nil
            })
            isGeneratingApp = false
            if success {
                builderMessages.append(ChatMessage(role: .assistant, text: "Build succeeded! App is running in the simulator."))
                messages.append(ChatMessage(role: .assistant, text: "AI-generated \(target.title) app built and launched. Project at: \(projectDirectory.path)"))
            } else {
                let pipelineError = buildPipelineCoordinator.pipelineError ?? "Unknown build failure"
                builderMessages.append(ChatMessage(role: .assistant, text: "Build pipeline failed: \(pipelineError)")); errorMessage = "Build pipeline failed: \(pipelineError)"
            }
        }
    }
}
