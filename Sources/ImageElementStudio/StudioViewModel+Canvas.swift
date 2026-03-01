import AppKit
import Foundation
import SwiftUI

extension StudioViewModel {

    // MARK: - Image Loading

    func chooseImage() {
        imageLoadingService.chooseImage { [weak self] url in
            guard let self else { return false }; return await self.loadDesignAsset(from: url, source: "Loaded")
        }
    }

    func clearImage() {
        imageLoadingService.cancelRealtimeAnalysisTask()
        selectedImage = nil; selectedImageURL = nil; clearElementSelection(); errorMessage = nil
        resetAnalysisAndReviewState()
        withActiveArtboard { board in board = Artboard.empty(named: board.name) }
    }

    func analyzeCurrentImage() {
        guard let image = selectedImage, let cgImage = image.resolvedCGImage else { errorMessage = "Upload a valid image before running analysis."; return }
        isAnalyzing = true; errorMessage = nil
        let filename = selectedImageURL?.lastPathComponent ?? "uploaded-image"
        Task {
            do {
                let document = try await analyzer.analyze(cgImage: cgImage, filename: filename)
                applySemantic(result: await semanticPipeline.enrich(document: document, imageData: image.jpegData()))
            } catch { isAnalyzing = false; errorMessage = error.localizedDescription }
        }
    }

    func handleDroppedProviders(_ providers: [NSItemProvider]) {
        Task {
            if let fileURL = await imageLoadingService.firstDroppedFileURL(from: providers) { _ = await loadDesignAsset(from: fileURL, source: "Dropped"); return }
            if let imageData = await imageLoadingService.firstDroppedImageData(from: providers) {
                _ = imageLoadingService.loadImage(fromData: imageData, fallbackName: "Dropped Image", source: "Dropped",
                    onSetErrorMessage: { [weak self] msg in self?.errorMessage = msg },
                    onApplyImage: { [weak self] image, filename, source in self?.applyLoadedImage(image, filename: filename, source: source) },
                    onClearSelectedImageURL: { [weak self] in self?.selectedImageURL = nil }); return
            }
            errorMessage = "Drop a design file (PNG/JPG/PDF/AI/SVG/FIG/JSON)."
        }
    }

    @discardableResult
    func loadDesignAsset(from url: URL, source: String) async -> Bool {
        await imageLoadingService.loadDesignAsset(from: url, source: source, designAssetImporter: designAssetImporter, semanticPipeline: semanticPipeline,
            onApplySemantic: { [weak self] result in self?.applySemantic(result: result) },
            onApplyImage: { [weak self] image, filename, source in self?.applyLoadedImage(image, filename: filename, source: source) },
            onSetImportLossReport: { [weak self] report in self?.importLossReport = report },
            onSetSelectedImageURL: { [weak self] url in self?.selectedImageURL = url },
            onSetErrorMessage: { [weak self] msg in self?.errorMessage = msg },
            onAppendMessage: { [weak self] msg in self?.messages.append(msg) },
            onAppendBuilderMessage: { [weak self] msg in self?.builderMessages.append(msg) })
    }

    func applyLoadedImage(_ image: NSImage, filename: String, source: String) {
        selectedImage = image; errorMessage = nil
        imageLoadingService.applyLoadedImage(image, filename: filename, source: source,
            onSync: { [weak self] img, name in
                guard let self else { return }
                imageLoadingService.syncCanvasToImage(image: img, filename: name, artboards: &artboards, activeArtboardIndex: activeArtboardIndex,
                    onSetLatestImageDescriptor: { [weak self] d in self?.latestImageDescriptor = d },
                    onSetLatestMetadata: { [weak self] m in self?.latestMetadata = m },
                    onResetState: { [weak self] in self?.resetImageAnalysisState() })
            },
            onAppendMessage: { [weak self] msg in self?.messages.append(msg) },
            onAppendBuilderMessage: { [weak self] msg in self?.builderMessages.append(msg) },
            onScheduleAnalysis: { [weak self] reason in self?.scheduleRealtimeAnalysis(reason: reason) })
    }

    func applySemantic(result: SemanticPipelineResult) {
        imageLoadingService.applySemantic(result: result, artboards: &artboards, selectedArtboardID: &selectedArtboardID,
            activeArtboardIndex: activeArtboardIndex, autoGenerateStateArtboards: autoGenerateStateArtboards,
            selectedImageURL: selectedImageURL, canvasService: canvasService, memoryStore: memoryStore,
            onSetLatestImageDescriptor: { [weak self] d in self?.latestImageDescriptor = d },
            onSetLatestMetadata: { [weak self] m in self?.latestMetadata = m },
            onSetLatestScope: { [weak self] s in self?.latestScope = s },
            onSetLatestBlueprint: { [weak self] b in self?.latestBlueprint = b },
            onSetIsAnalyzing: { [weak self] v in self?.isAnalyzing = v },
            onSetMemory: { [weak self] m in self?.memory = m },
            onClearElementSelection: { [weak self] in self?.clearElementSelection() },
            onResetAnalysisState: { [weak self] in self?.resetImageAnalysisState() },
            onAppendMessage: { [weak self] msg in self?.messages.append(msg) },
            onAppendBuilderMessage: { [weak self] msg in self?.builderMessages.append(msg) },
            onRunRealtimeBuildSetup: { [weak self] in self?.runRealtimeBuildSetupIfNeeded() },
            onRegenerateJSONPreview: { [weak self] in self?.regenerateJSONPreview() })
    }

    // MARK: - Element Selection

    func clearElementSelection() { selectionService.clearElementSelection() }
    func setSelectedElement(_ id: UUID?, additive: Bool = false) { selectionService.setSelectedElement(id, additive: additive, validIDs: Set(renderableElements.map(\.id))) }
    func setSelectedElements(_ ids: Set<UUID>, preferredPrimary: UUID? = nil) { selectionService.setSelectedElements(ids, preferredPrimary: preferredPrimary, validIDs: Set(renderableElements.map(\.id))) }
    func selectElementsByMarquee(_ elementIDs: [UUID], additive: Bool = false) { selectionService.selectElementsByMarquee(elementIDs, additive: additive, validIDs: Set(renderableElements.map(\.id))) }

    // MARK: - Element Manipulation

    func distributeSelectedElementsHorizontally() { withCanvasEdit { canvasService.distributeSelectedElementsHorizontally(artboards: &artboards, activeArtboardIndex: activeArtboardIndex, selectedElementIDs: selectedElementIDs, canDistribute: canDistributeSelection) } }
    func distributeSelectedElementsVertically() { withCanvasEdit { canvasService.distributeSelectedElementsVertically(artboards: &artboards, activeArtboardIndex: activeArtboardIndex, selectedElementIDs: selectedElementIDs, canDistribute: canDistributeSelection) } }
    func spaceSelectedElementsHorizontally(gap: Double) { withCanvasEdit { canvasService.spaceSelectedElementsHorizontally(gap: gap, artboards: &artboards, activeArtboardIndex: activeArtboardIndex, selectedElementIDs: selectedElementIDs) } }
    func spaceSelectedElementsVertically(gap: Double) { withCanvasEdit { canvasService.spaceSelectedElementsVertically(gap: gap, artboards: &artboards, activeArtboardIndex: activeArtboardIndex, selectedElementIDs: selectedElementIDs) } }
    func toggleConstraint(_ pin: ConstraintPin, enabled: Bool) { withCanvasEdit { canvasService.toggleConstraint(pin, enabled: enabled, artboards: &artboards, activeArtboardIndex: activeArtboardIndex, selectedElementIDs: selectedElementIDs) } }
    func hasConstraint(_ pin: ConstraintPin) -> Bool { canvasService.hasConstraint(pin, selectedElements: selectedElements) }
    func resizeSelectedElements(handle: ResizeHandle, deltaX: Double, deltaY: Double) { guard let svcHandle = CanvasService.ResizeHandle(rawValue: handle.rawValue) else { return }; withCanvasEdit { canvasService.resizeSelectedElements(handle: svcHandle, deltaX: deltaX, deltaY: deltaY, artboards: &artboards, activeArtboardIndex: activeArtboardIndex, selectedElementIDs: selectedElementIDs) } }
    func rotateSelectedElements(by deltaDegrees: Double) { withCanvasEdit { canvasService.rotateSelectedElements(by: deltaDegrees, artboards: &artboards, activeArtboardIndex: activeArtboardIndex, selectedElementIDs: selectedElementIDs) } }
    func nudgeSelection(deltaX: Double, deltaY: Double) { withCanvasEdit { canvasService.nudgeSelection(deltaX: deltaX, deltaY: deltaY, snapToGrid: snapToGrid, gridSize: gridSize, artboards: &artboards, activeArtboardIndex: activeArtboardIndex, selectedElementIDs: selectedElementIDs) } }

    func keyboardNudgeLeft(fast: Bool = false) { let a = fast ? keyboardNudgeAmount * Constants.Canvas.fastNudgeMultiplier : keyboardNudgeAmount; nudgeSelection(deltaX: -a, deltaY: 0) }
    func keyboardNudgeRight(fast: Bool = false) { let a = fast ? keyboardNudgeAmount * Constants.Canvas.fastNudgeMultiplier : keyboardNudgeAmount; nudgeSelection(deltaX: a, deltaY: 0) }
    func keyboardNudgeUp(fast: Bool = false) { let a = fast ? keyboardNudgeAmount * Constants.Canvas.fastNudgeMultiplier : keyboardNudgeAmount; nudgeSelection(deltaX: 0, deltaY: -a) }
    func keyboardNudgeDown(fast: Bool = false) { let a = fast ? keyboardNudgeAmount * Constants.Canvas.fastNudgeMultiplier : keyboardNudgeAmount; nudgeSelection(deltaX: 0, deltaY: a) }
    func keyboardRotateClockwise() { rotateSelectedElements(by: Constants.Canvas.keyboardRotationStep) }
    func keyboardRotateCounterclockwise() { rotateSelectedElements(by: -Constants.Canvas.keyboardRotationStep) }
}
