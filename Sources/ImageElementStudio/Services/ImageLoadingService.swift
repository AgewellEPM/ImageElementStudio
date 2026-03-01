import AppKit
import Foundation
import os
import UniformTypeIdentifiers

// MARK: - ImageLoadingService

@MainActor
final class ImageLoadingService: ObservableObject {

    private static let logger = Logger(
        subsystem: "com.imageelementstudio",
        category: "ImageLoadingService"
    )

    // MARK: - Supported import types (mirrors StudioViewModel.supportedImportTypes)

    static var supportedImportTypes: [UTType] {
        var types: [UTType] = [.image, .pdf, .json]
        let extensions = ["ai", "svg", "fig", "xd", "sketch", "eps"]
        for ext in extensions {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }

    // MARK: - Task management

    /// Retained so the caller can cancel the scheduled task when needed.
    private(set) var realtimeAnalysisTask: Task<Void, Never>?

    // MARK: - chooseImage

    /// Opens an NSOpenPanel for the user to pick a design file, then invokes
    /// `onLoad` with the chosen URL.  Returns without calling `onLoad` if the
    /// user cancels.
    func chooseImage(
        supportedTypes: [UTType] = ImageLoadingService.supportedImportTypes,
        onLoad: @escaping (URL) async -> Bool
    ) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = supportedTypes
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open Design File"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            _ = await onLoad(url)
        }
    }

    // MARK: - loadDesignAsset

    /// Imports a design asset from `url` using the provided pipeline objects.
    ///
    /// - Parameters:
    ///   - url: The file URL to import.
    ///   - source: A human-readable label such as "Loaded" or "Dropped".
    ///   - designAssetImporter: The shared importer instance.
    ///   - semanticPipeline: The pipeline that enriches raw documents.
    ///   - onApplySemantic: Called when a full structured document was produced.
    ///   - onApplyImage: Called when only an image (no structured document) was produced.
    ///   - onSetImportLossReport: Called with the import-loss report (may be nil).
    ///   - onSetSelectedImageURL: Called with the resolved URL.
    ///   - onSetErrorMessage: Called when an error occurs.
    ///   - onAppendMessage: Appends a ChatMessage to the main chat.
    ///   - onAppendBuilderMessage: Appends a ChatMessage to the builder chat.
    /// - Returns: `true` if the asset was successfully loaded.
    @discardableResult
    func loadDesignAsset(
        from url: URL,
        source: String,
        designAssetImporter: DesignAssetImporter,
        semanticPipeline: SemanticPipeline,
        onApplySemantic: (SemanticPipelineResult) -> Void,
        onApplyImage: (NSImage, String, String) -> Void,
        onSetImportLossReport: (ImportLossReport?) -> Void,
        onSetSelectedImageURL: (URL?) -> Void,
        onSetErrorMessage: (String?) -> Void,
        onAppendMessage: (ChatMessage) -> Void,
        onAppendBuilderMessage: (ChatMessage) -> Void
    ) async -> Bool {
        // Validate the file path before loading
        if !InputValidator.isPathSafe(url.path) {
            Self.logger.warning("Blocked design asset load from unsafe path: \(url.path, privacy: .public)")
            onSetErrorMessage("The file path contains unsafe characters or patterns and was rejected.")
            return false
        }

        do {
            AppLogger.info("Importing design asset: \(url.lastPathComponent) (source: \(source))", category: .pipeline)
            let imported = try await designAssetImporter.importAsset(from: url)
            onSetSelectedImageURL(url)
            onSetErrorMessage(nil)
            onSetImportLossReport(imported.importLossReport)

            if let document = imported.document {
                // Full structured import – hand off to semantic pipeline
                let semanticResult = await semanticPipeline.enrich(
                    document: document,
                    imageData: imported.image?.jpegData()
                )
                onApplySemantic(semanticResult)

                let cleanupLine: String
                if let report = imported.importLossReport {
                    cleanupLine = "Estimated manual cleanup: \(Int(report.estimatedManualCleanupPercent.rounded()))%."
                } else {
                    cleanupLine = ""
                }
                let noteLine = ([imported.notes.joined(separator: " "), cleanupLine]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty })
                    .joined(separator: " ")
                onAppendMessage(ChatMessage(
                    role: .assistant,
                    text: "\(source) \(imported.filename) via structured import. \(noteLine)"
                ))
                onAppendBuilderMessage(ChatMessage(
                    role: .assistant,
                    text: "Structured build pipeline complete for \(imported.filename)."
                ))
                AppLogger.info("Structured import succeeded: \(imported.filename)", category: .pipeline)
                return true
            }

            guard let image = imported.image else {
                AppLogger.warning("No preview image derived from \(url.lastPathComponent)", category: .pipeline)
                onSetErrorMessage("Could not derive a preview image from the imported design file.")
                return false
            }

            // Image-only import (PNG/JPG/etc.)
            AppLogger.info("Image-only import succeeded: \(imported.filename)", category: .pipeline)
            onApplyImage(image, imported.filename, source)

            if !imported.notes.isEmpty {
                onAppendMessage(ChatMessage(role: .assistant, text: imported.notes.joined(separator: " ")))
            }
            return true
        } catch {
            AppLogger.error("Design asset import failed for \(url.lastPathComponent): \(error.localizedDescription)", category: .pipeline)
            onSetErrorMessage(error.localizedDescription)
            return false
        }
    }

    // MARK: - loadImage(fromData:)

    /// Decodes `data` into an NSImage and calls `onApplyImage` on success.
    /// - Returns: `true` if decoding succeeded.
    @discardableResult
    func loadImage(
        fromData data: Data,
        fallbackName: String,
        source: String,
        onSetErrorMessage: (String?) -> Void,
        onApplyImage: (NSImage, String, String) -> Void,
        onClearSelectedImageURL: () -> Void
    ) -> Bool {
        guard let image = NSImage(data: data) else {
            onSetErrorMessage("Could not decode dropped image data.")
            return false
        }
        onApplyImage(image, fallbackName, source)
        onClearSelectedImageURL()
        return true
    }

    // MARK: - applyLoadedImage

    /// Updates state when a plain image (no structured document) is loaded.
    ///
    /// - Parameters:
    ///   - image: The decoded NSImage.
    ///   - filename: The original filename used for display and analysis.
    ///   - source: Human-readable load source label ("Loaded", "Dropped", …).
    ///   - onSync: Called to sync the canvas to the new image.
    ///   - onAppendMessage: Appends a message to the main chat.
    ///   - onAppendBuilderMessage: Appends a message to the builder chat.
    ///   - onScheduleAnalysis: Called to schedule a realtime analysis pass.
    func applyLoadedImage(
        _ image: NSImage,
        filename: String,
        source: String,
        onSync: (NSImage, String?) -> Void,
        onAppendMessage: (ChatMessage) -> Void,
        onAppendBuilderMessage: (ChatMessage) -> Void,
        onScheduleAnalysis: (String) -> Void
    ) {
        onSync(image, filename)
        onAppendMessage(ChatMessage(
            role: .assistant,
            text: "\(source) \(filename). Click Analyze Image to infer UI semantics, scope, and JSON elements."
        ))
        onAppendBuilderMessage(ChatMessage(
            role: .assistant,
            text: "\(source) \(filename). Type 'build' to run the pipeline."
        ))
        onScheduleAnalysis("image loaded")
    }

    // MARK: - applySemantic

    /// Applies a `SemanticPipelineResult` to all caller-owned state.
    ///
    /// This is the large (~90-line) method extracted from StudioViewModel.
    /// All mutable state is passed by reference or via callbacks so the service
    /// remains stateless with respect to the document.
    ///
    /// - Parameters:
    ///   - result: The enriched semantic pipeline result.
    ///   - artboards: Inout reference to the artboards array.
    ///   - selectedArtboardID: Inout reference to the currently-selected artboard ID.
    ///   - activeArtboardIndex: The index of the active artboard (nil if none).
    ///   - autoGenerateStateArtboards: Whether state artboards should be auto-generated.
    ///   - selectedImageURL: The URL of the currently-selected image (used for memory).
    ///   - canvasService: The canvas service used to generate state artboards.
    ///   - memoryStore: The project-memory store.
    ///   - onSetLatestImageDescriptor: Setter for latestImageDescriptor.
    ///   - onSetLatestMetadata: Setter for latestMetadata.
    ///   - onSetLatestScope: Setter for latestScope.
    ///   - onSetLatestBlueprint: Setter for latestBlueprint.
    ///   - onSetIsAnalyzing: Setter for isAnalyzing.
    ///   - onSetMemory: Setter for memory.
    ///   - onClearElementSelection: Clears the current element selection.
    ///   - onResetAnalysisState: Resets design-code diffs, quality report, etc.
    ///   - onAppendMessage: Appends a message to the main chat.
    ///   - onAppendBuilderMessage: Appends a message to the builder chat.
    ///   - onRunRealtimeBuildSetup: Called at the end to trigger a realtime build setup.
    ///   - onRegenerateJSONPreview: Called at the end to refresh the JSON preview.
    func applySemantic(
        result: SemanticPipelineResult,
        artboards: inout [Artboard],
        selectedArtboardID: inout UUID?,
        activeArtboardIndex: Int?,
        autoGenerateStateArtboards: Bool,
        selectedImageURL: URL?,
        canvasService: CanvasService,
        memoryStore: ProjectMemoryStore,
        onSetLatestImageDescriptor: (ImageDescriptor?) -> Void,
        onSetLatestMetadata: (AnalysisMetadata?) -> Void,
        onSetLatestScope: (ProductScopeSnapshot?) -> Void,
        onSetLatestBlueprint: (BuildBlueprint?) -> Void,
        onSetIsAnalyzing: (Bool) -> Void,
        onSetMemory: (ProjectMemory) -> Void,
        onClearElementSelection: () -> Void,
        onResetAnalysisState: () -> Void,
        onAppendMessage: (ChatMessage) -> Void,
        onAppendBuilderMessage: (ChatMessage) -> Void,
        onRunRealtimeBuildSetup: () -> Void,
        onRegenerateJSONPreview: () -> Void
    ) {
        let document = result.document
        let analyzedBoardID = selectedArtboardID

        // Slot the newly-analyzed artboard into the correct position
        if let index = activeArtboardIndex {
            var replacement = document.artboard
            replacement.id = artboards[index].id
            artboards[index] = replacement
            selectedArtboardID = replacement.id
        } else {
            artboards = [document.artboard]
            selectedArtboardID = document.artboard.id
        }

        onSetLatestImageDescriptor(document.image)
        onSetLatestMetadata(document.metadata)
        onSetLatestScope(document.scope)
        onSetLatestBlueprint(document.blueprint)

        // Reset state that is invalidated by a fresh analysis
        onClearElementSelection()
        onResetAnalysisState()
        onSetIsAnalyzing(false)

        let textCount = document.artboard.elements.filter { $0.kind == .text }.count
        let shapeCount = document.artboard.elements.filter { $0.kind == .shape }.count
        let inferredControls = document.blueprint?.controls.count ?? 0
        let inferredStates = document.blueprint?.states.count ?? 0

        // Optionally generate state artboards from the blueprint
        if autoGenerateStateArtboards, let blueprint = document.blueprint {
            let updatedMemory = canvasService.generateSuggestedStateArtboards(
                from: blueprint,
                sourceArtboardID: analyzedBoardID ?? selectedArtboardID,
                artboards: &artboards,
                selectedArtboardID: selectedArtboardID,
                memoryStore: memoryStore,
                latestImageDescriptor: document.image,
                selectedImageURL: selectedImageURL,
                latestScope: document.scope
            )
            onSetMemory(updatedMemory)
        }

        if let scope = document.scope {
            let updatedMemory = memoryStore.recordAnalysis(
                scope: scope,
                imageName: document.image.filename,
                artboard: document.artboard
            )
            onSetMemory(updatedMemory)
            onAppendMessage(ChatMessage(
                role: .assistant,
                text: "Analysis complete with \(result.source): \(scope.summary)"
            ))
            onAppendMessage(ChatMessage(
                role: .assistant,
                text: "Detected \(textCount) text and \(shapeCount) shape elements. Memory now tracks \(updatedMemory.entries.count) design snapshots."
            ))
            if let blueprint = document.blueprint {
                onAppendMessage(ChatMessage(role: .assistant, text: blueprint.detectionSummary))
                onAppendMessage(ChatMessage(
                    role: .assistant,
                    text: "Pipeline inferred \(inferredControls) controls and \(inferredStates) states for auto-build scaffolding."
                ))
            }
            onAppendMessage(ChatMessage(role: .assistant, text: result.narrative))
            onAppendBuilderMessage(ChatMessage(
                role: .assistant,
                text: "Build complete: \(scope.appType) with \(textCount) text and \(shapeCount) shape elements, \(inferredControls) controls, \(inferredStates) states. Type 'status' or 'export json'."
            ))
        } else {
            onAppendMessage(ChatMessage(
                role: .assistant,
                text: "Analysis complete: \(textCount) text elements and \(shapeCount) shape elements were mapped into JSON."
            ))
            onAppendBuilderMessage(ChatMessage(
                role: .assistant,
                text: "Build complete. Mapped \(textCount) text, \(shapeCount) shape elements, \(inferredControls) controls, and \(inferredStates) states."
            ))
        }

        onRunRealtimeBuildSetup()
        onRegenerateJSONPreview()
    }

    // MARK: - syncCanvasToImage

    /// Syncs the active canvas artboard to an image's pixel dimensions and
    /// resets all analysis-derived state.
    ///
    /// - Parameters:
    ///   - image: The NSImage to sync with.
    ///   - filename: The filename used for the ImageDescriptor.
    ///   - artboards: Inout artboards array so the active board can be mutated.
    ///   - activeArtboardIndex: Index of the active artboard (nil means nothing to sync).
    ///   - onSetLatestImageDescriptor: Setter for latestImageDescriptor.
    ///   - onSetLatestMetadata: Setter for latestMetadata.
    ///   - onResetState: Resets scope, blueprint, tokens, components, reviews, etc.
    func syncCanvasToImage(
        image: NSImage,
        filename: String?,
        artboards: inout [Artboard],
        activeArtboardIndex: Int?,
        onSetLatestImageDescriptor: (ImageDescriptor?) -> Void,
        onSetLatestMetadata: (AnalysisMetadata?) -> Void,
        onResetState: () -> Void
    ) {
        guard let cgImage = image.resolvedCGImage else { return }
        let width = cgImage.width
        let height = cgImage.height

        onResetState()

        if let index = activeArtboardIndex {
            artboards[index].width = width
            artboards[index].height = height
            artboards[index].elements = [CanvasElement.root(width: width, height: height, filename: filename)]
        }

        onSetLatestImageDescriptor(ImageDescriptor(
            filename: filename ?? "uploaded-image",
            width: width,
            height: height
        ))
        onSetLatestMetadata(AnalysisMetadata(
            generatedAt: Date(),
            engine: "ImageElementStudio",
            notes: ["Image loaded. Run analysis to infer semantic sections and product scope."]
        ))
    }

    // MARK: - Drop helpers

    /// Returns the first file URL found among the provided NSItemProviders.
    func firstDroppedFileURL(from providers: [NSItemProvider]) async -> URL? {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let url = await loadFileURL(from: provider) {
                return url
            }
        }
        return nil
    }

    /// Returns the first image data found among the provided NSItemProviders.
    func firstDroppedImageData(from providers: [NSItemProvider]) async -> Data? {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let data = await loadImageData(from: provider) {
                return data
            }
        }
        return nil
    }

    /// Loads a file URL from a single NSItemProvider.
    func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data {
                    continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                    return
                }
                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }
                if let string = item as? String, let url = URL(string: string) {
                    continuation.resume(returning: url)
                    return
                }
                continuation.resume(returning: nil)
            }
        }
    }

    /// Loads raw image data from a single NSItemProvider.
    func loadImageData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    // MARK: - Realtime analysis scheduling

    /// Schedules a realtime analysis pass (debounced 240 ms) if realtime builds
    /// are enabled and an image is currently loaded.
    ///
    /// - Parameters:
    ///   - reason: Human-readable description used in the builder message.
    ///   - realTimeBuildEnabled: Guard flag; analysis is skipped if false.
    ///   - hasImage: Whether an image is currently loaded.
    ///   - onRun: Closure that performs the actual analysis when the timer fires.
    func scheduleRealtimeAnalysis(
        reason: String,
        realTimeBuildEnabled: Bool,
        hasImage: Bool,
        onRun: @escaping @MainActor () -> Void
    ) {
        guard realTimeBuildEnabled else { return }
        guard hasImage else { return }

        realtimeAnalysisTask?.cancel()
        realtimeAnalysisTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 240_000_000)
            } catch {
                // Task was cancelled; exit silently.
                return
            }
            guard self != nil else { return }
            await MainActor.run {
                onRun()
            }
        }
    }

    /// Cancels the currently-scheduled realtime analysis task if one is pending.
    func cancelRealtimeAnalysisTask() {
        realtimeAnalysisTask?.cancel()
        realtimeAnalysisTask = nil
    }

    /// Performs a realtime analysis pass if all guards are satisfied.
    ///
    /// - Parameters:
    ///   - reason: Human-readable trigger description used in the builder message.
    ///   - realTimeBuildEnabled: Guard flag.
    ///   - hasImage: Whether an image is currently loaded.
    ///   - isAnalyzing: Whether an analysis is already in progress (skip if true).
    ///   - onAppendBuilderMessage: Appends a status message to the builder chat.
    ///   - onRunAnalysis: The actual analysis closure to invoke.
    func runRealtimeAnalysisIfNeeded(
        reason: String,
        realTimeBuildEnabled: Bool,
        hasImage: Bool,
        isAnalyzing: Bool,
        onAppendBuilderMessage: (ChatMessage) -> Void,
        onRunAnalysis: () -> Void
    ) {
        guard realTimeBuildEnabled else { return }
        guard hasImage else { return }
        guard !isAnalyzing else { return }

        onAppendBuilderMessage(ChatMessage(
            role: .assistant,
            text: "Realtime build triggered (\(reason)): running analysis."
        ))
        onRunAnalysis()
    }
}
