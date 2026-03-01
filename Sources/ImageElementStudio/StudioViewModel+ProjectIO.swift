import AppKit
import Foundation
import SwiftUI

extension StudioViewModel {

    // MARK: - Project Management

    func switchProject(to rawName: String) {
        let sanitized = InputValidator.sanitizeProjectName(rawName)
        let resolved = sanitized.isEmpty ? "Default Project" : sanitized
        if !InputValidator.isProjectNameValid(resolved) {
            messages.append(ChatMessage(role: .assistant, text: "Project name contains invalid characters and was sanitized."))
        }
        imageLoadingService.cancelRealtimeAnalysisTask()
        memory = memoryStore.switchProject(to: resolved)
        projectName = memory.projectName ?? resolved
        resetWorkspaceForProjectContext()
        UserDefaults.standard.set(projectName, forKey: "ImageElementStudio.ActiveProjectName")
        messages.append(ChatMessage(role: .assistant, text: "Switched to project '\(projectName)'."))
    }

    func createNewProject(named requestedName: String?) {
        let sanitizedName = requestedName.map { InputValidator.sanitizeProjectName($0) }
        imageLoadingService.cancelRealtimeAnalysisTask()
        memory = memoryStore.createFreshProject(named: sanitizedName)
        projectName = memory.projectName ?? "Project"
        resetWorkspaceForProjectContext()
        UserDefaults.standard.set(projectName, forKey: "ImageElementStudio.ActiveProjectName")
        messages.append(ChatMessage(role: .assistant, text: "Created new project '\(projectName)' with clean memory."))
    }

    func saveProjectPackage() {
        projectService.saveProjectPackage(
            projectName: projectName, projectID: memory.projectID ?? buildExportService.slugified(projectName),
            memory: memory, artboards: artboards, selectedArtboardID: selectedArtboardID,
            latestScope: latestScope, latestBlueprint: latestBlueprint, latestDesignTokens: latestDesignTokens,
            tokenRevisions: tokenRevisions, latestComponentSpecs: latestComponentSpecs, componentInstances: componentInstances,
            importLossReport: importLossReport, latestInteropPackage: latestInteropPackage,
            latestBuildQualityReport: latestBuildQualityReport, designCodeDiffs: designCodeDiffs,
            latestFullStackBuildSummary: latestFullStackBuildSummary,
            latestEnterpriseReadinessReport: latestEnterpriseReadinessReport,
            reviewComments: reviewComments, reviewApprovalState: reviewApprovalState,
            latestBenchmarkReport: latestBenchmarkReport, benchmarkHistory: benchmarkHistory,
            benchmarkTrendScore: benchmarkTrendScore, currentDocument: currentDocument(),
            slugified: { [weak self] s in self?.buildExportService.slugified(s) ?? s },
            onSetErrorMessage: { [weak self] msg in self?.errorMessage = msg },
            onAppendMessage: { [weak self] msg in self?.messages.append(msg) }
        )
    }

    // MARK: - Build Setup

    func buildConfirmationLines(for target: BuildTarget) -> [String] {
        var lines = buildExportService.buildConfirmationLines(for: target, context: makeBuildContext())
        lines.append(fullStackStatusLine); lines.append(enterpriseReadinessStatusLine)
        return lines
    }

    func checkReviewGateForBuildExport(target: BuildTarget) -> Bool {
        guard let reason = reviewGateBlockReason else { return true }
        let message = "Build export for \(target.title) blocked. \(reason)"
        errorMessage = message; messages.append(ChatMessage(role: .assistant, text: message)); builderMessages.append(ChatMessage(role: .assistant, text: message))
        return false
    }

    func setupProjectBuild(for target: BuildTarget) {
        guard !isSettingUpBuild else { return }
        guard checkReviewGateForBuildExport(target: target) else { return }
        if pipelineMode == .guided, selectedImage == nil, acceptedStrategySpec == nil {
            builderMessages.append(ChatMessage(role: .assistant, text: "Guided mode requires an approved strategy spec before build setup."))
            return
        }
        isSettingUpBuild = true
        do {
            let result = try buildExportService.setupBuild(for: target, context: makeBuildContext())
            latestBuildQualityReport = result.qualityReport; designCodeDiffs = result.designCodeDiffs
            recordActiveArtboardSnapshot(reason: "setup-\(target.rawValue)")
            messages.append(ChatMessage(role: .assistant, text: "Build setup ready for \(target.title). Output: \(result.outputDirectory.path)"))
            builderMessages.append(ChatMessage(role: .assistant, text: "Build setup complete for \(target.title). Opened output folder with manifest + scaffold notes."))
            NSWorkspace.shared.activateFileViewerSelecting([result.outputDirectory])
        } catch {
            errorMessage = "Build setup failed: \(error.localizedDescription)"
            builderMessages.append(ChatMessage(role: .assistant, text: "Build setup failed: \(error.localizedDescription)"))
        }
        isSettingUpBuild = false
    }

    func openRealtimeBuildOutputFolder() { guard let path = lastRealtimeBuildPath else { return }; NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
    func triggerRealtimeBuildNow() { scheduleRealtimeAnalysis(reason: "manual realtime trigger") }

    // MARK: - Artboard Management

    func addArtboard() {
        canvasService.addArtboard(to: &artboards, selectedArtboardID: &selectedArtboardID, activeCanvasSize: activeCanvasSize, latestImageDescriptor: latestImageDescriptor,
            recordSnapshot: { [weak self] artboard, reason in guard let self else { return }; self.memory = self.memoryStore.recordArtboardSnapshot(artboard: artboard, reason: reason, imageName: self.latestImageDescriptor?.filename ?? self.selectedImageURL?.lastPathComponent, scope: self.latestScope) },
            regenerateJSON: { [weak self] in self?.regenerateJSONPreview() })
    }

    func duplicateActiveArtboard() {
        canvasService.duplicateActiveArtboard(artboards: &artboards, selectedArtboardID: &selectedArtboardID, activeArtboard: activeArtboard,
            recordSnapshot: { [weak self] artboard, reason in guard let self else { return }; self.memory = self.memoryStore.recordArtboardSnapshot(artboard: artboard, reason: reason, imageName: self.latestImageDescriptor?.filename ?? self.selectedImageURL?.lastPathComponent, scope: self.latestScope) })
    }

    func removeActiveArtboard() {
        canvasService.removeActiveArtboard(artboards: &artboards, selectedArtboardID: &selectedArtboardID, activeArtboardIndex: activeArtboardIndex, latestImageDescriptor: latestImageDescriptor,
            clearSelection: { [weak self] in self?.clearElementSelection() },
            reconcileIntegrity: { [weak self] in self?.reconcileComponentModelIntegrity() },
            regenerateJSON: { [weak self] in self?.regenerateJSONPreview() },
            recordSnapshot: { [weak self] artboard, reason in guard let self else { return }; self.memory = self.memoryStore.recordArtboardSnapshot(artboard: artboard, reason: reason, imageName: self.latestImageDescriptor?.filename ?? self.selectedImageURL?.lastPathComponent, scope: self.latestScope) })
    }

    func generateStateArtboardsFromLatestBlueprint() {
        memory = canvasService.generateStateArtboardsFromLatestBlueprint(blueprint: latestBlueprint, artboards: &artboards, selectedArtboardID: selectedArtboardID, memoryStore: memoryStore, latestImageDescriptor: latestImageDescriptor, selectedImageURL: selectedImageURL, latestScope: latestScope)
    }

    // MARK: - Element Operations

    func renameSelectedElement(_ value: String) {
        canvasService.renameSelectedElement(value, selectedElementID: selectedElementID, artboards: &artboards, activeArtboardIndex: activeArtboardIndex, reconcileIntegrity: { [weak self] in self?.reconcileComponentModelIntegrity() }, regenerateJSON: { [weak self] in self?.regenerateJSONPreview() })
    }

    func deleteSelectedElement() {
        canvasService.deleteSelectedElement(selectedElementID: selectedElementID, selectedElementIDs: selectedElementIDs, artboards: &artboards, activeArtboardIndex: activeArtboardIndex, clearSelection: { [weak self] in self?.clearElementSelection() }, reconcileIntegrity: { [weak self] in self?.reconcileComponentModelIntegrity() }, regenerateJSON: { [weak self] in self?.regenerateJSONPreview() })
    }

    func nudgeSelectedElement(deltaX: Double, deltaY: Double) {
        canvasService.nudgeSelectedElement(deltaX: deltaX, deltaY: deltaY, selectedElementIDs: selectedElementIDs, artboards: &artboards, activeArtboardIndex: activeArtboardIndex, snapToGrid: snapToGrid, gridSize: gridSize, reconcileIntegrity: { [weak self] in self?.reconcileComponentModelIntegrity() }, regenerateJSON: { [weak self] in self?.regenerateJSONPreview() })
    }

    // MARK: - Export

    func copyJSONToClipboard() { exportService.copyJSONToClipboard(jsonPreview: jsonPreview) }

    func exportJSON() {
        exportService.exportJSON(document: currentDocument(), projectName: projectName, onSetErrorMessage: { [weak self] msg in self?.errorMessage = msg })
    }

    func exportInteropPackage() {
        let result = exportService.exportInteropPackage(
            projectName: projectName, artboards: artboards, latestDesignTokens: latestDesignTokens,
            tokenRevisions: tokenRevisions, latestComponentSpecs: latestComponentSpecs, componentInstances: componentInstances,
            importLossReport: importLossReport, latestBuildQualityReport: latestBuildQualityReport,
            latestEnterpriseReadinessReport: latestEnterpriseReadinessReport, latestBenchmarkReport: latestBenchmarkReport,
            benchmarkHistory: benchmarkHistory, benchmarkTrendScore: benchmarkTrendScore,
            reviewComments: reviewComments, reviewApprovalState: reviewApprovalState,
            canExportBuildArtifacts: canExportBuildArtifacts, reviewGateBlockReason: reviewGateBlockReason,
            slugified: { [weak self] s in self?.buildExportService.slugified(s) ?? s },
            onSetErrorMessage: { [weak self] msg in self?.errorMessage = msg },
            onAppendMessage: { [weak self] msg in self?.messages.append(msg) },
            onAppendBuilderMessage: { [weak self] msg in self?.builderMessages.append(msg) }
        )
        if let pkg = result { latestInteropPackage = pkg }
    }
}
