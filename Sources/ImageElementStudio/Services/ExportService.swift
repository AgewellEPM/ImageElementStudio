import AppKit
import Foundation
import os
import UniformTypeIdentifiers

// MARK: - ExportService

/// Handles all export and clipboard operations: copying JSON to the clipboard,
/// exporting a JSON document, and building + writing an interop export package.
@MainActor
final class ExportService {

    private static let logger = Logger(
        subsystem: "com.imageelementstudio",
        category: "ExportService"
    )

    // MARK: - copyJSONToClipboard

    /// Copies `jsonPreview` to the system pasteboard.
    func copyJSONToClipboard(jsonPreview: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(jsonPreview, forType: .string)
    }

    // MARK: - exportJSON

    /// Encodes `document` to pretty-printed JSON and presents an NSSavePanel.
    ///
    /// - Parameters:
    ///   - document: Any `Encodable` value to export (typically `AnalysisDocument`).
    ///   - projectName: Used only for a default filename suggestion.
    ///   - onSetErrorMessage: Setter for the view-model's errorMessage.
    func exportJSON(
        document: some Encodable,
        projectName: String,
        onSetErrorMessage: (String?) -> Void
    ) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data: Data
        do {
            data = try encoder.encode(document)
        } catch {
            onSetErrorMessage("JSON export failed: \(error.localizedDescription)")
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "image-elements.json"
        panel.prompt = "Export JSON"

        guard panel.runModal() == .OK, let destination = panel.url else { return }

        // Validate the chosen export path
        if !InputValidator.isPathSafe(destination.path) {
            Self.logger.warning("Blocked JSON export to unsafe path: \(destination.path, privacy: .public)")
            onSetErrorMessage("The chosen export path contains unsafe characters or patterns.")
            return
        }

        do {
            try data.write(to: destination, options: .atomic)
            onSetErrorMessage(nil)
        } catch {
            onSetErrorMessage("Could not write JSON: \(error.localizedDescription)")
        }
    }

    // MARK: - exportInteropPackage

    /// Builds an `InteropExportPackage`, presents an NSSavePanel, writes the
    /// package JSON to disk, and returns the constructed package so the
    /// view-model can store it in `latestInteropPackage`.
    ///
    /// This is the ~95-line method extracted from StudioViewModel.
    ///
    /// - Parameters:
    ///   - projectName: The human-readable project name.
    ///   - artboards: All artboards to include in the export.
    ///   - latestDesignTokens: The current design token set, if any.
    ///   - tokenRevisions: All token revision history entries.
    ///   - latestComponentSpecs: All component specs.
    ///   - componentInstances: All component instances.
    ///   - importLossReport: The import-loss report, if any.
    ///   - latestBuildQualityReport: The latest build quality report, if any.
    ///   - latestEnterpriseReadinessReport: The latest enterprise readiness report, if any.
    ///   - latestBenchmarkReport: The latest benchmark run report, if any.
    ///   - benchmarkHistory: All benchmark run reports.
    ///   - benchmarkTrendScore: The benchmark trend score, if any.
    ///   - reviewComments: All review comments.
    ///   - reviewApprovalState: The current review approval state.
    ///   - canExportBuildArtifacts: Whether the review gate is passing.
    ///   - reviewGateBlockReason: The reason the review gate is blocked, if any.
    ///   - slugified: Helper closure that slugifies a string (delegate to BuildExportService).
    ///   - onSetErrorMessage: Setter for the view-model's errorMessage.
    ///   - onAppendMessage: Appends a ChatMessage to the main chat.
    ///   - onAppendBuilderMessage: Appends a ChatMessage to the builder chat.
    /// - Returns: The constructed `InteropExportPackage` on success, or `nil` if
    ///   the user cancelled, a guard failed, or an error was thrown.
    @discardableResult
    func exportInteropPackage(
        projectName: String,
        artboards: [Artboard],
        latestDesignTokens: DesignTokenSet?,
        tokenRevisions: [TokenRevision],
        latestComponentSpecs: [ComponentSpec],
        componentInstances: [ComponentInstance],
        importLossReport: ImportLossReport?,
        latestBuildQualityReport: BuildQualityReport?,
        latestEnterpriseReadinessReport: EnterpriseReadinessReport?,
        latestBenchmarkReport: BenchmarkRunReport?,
        benchmarkHistory: [BenchmarkRunReport],
        benchmarkTrendScore: BenchmarkTrendScore?,
        reviewComments: [DesignReviewComment],
        reviewApprovalState: ReviewApprovalState,
        canExportBuildArtifacts: Bool,
        reviewGateBlockReason: String?,
        slugified: (String) -> String,
        onSetErrorMessage: (String?) -> Void,
        onAppendMessage: (ChatMessage) -> Void,
        onAppendBuilderMessage: (ChatMessage) -> Void
    ) -> InteropExportPackage? {
        // Review gate guard
        guard canExportBuildArtifacts else {
            let reason = reviewGateBlockReason ?? "Review gate is blocking export."
            let message = "Interop export blocked. \(reason)"
            onSetErrorMessage(message)
            onAppendBuilderMessage(ChatMessage(role: .assistant, text: message))
            onAppendMessage(ChatMessage(role: .assistant, text: message))
            return nil
        }

        let package = InteropExportPackage(
            packageID: UUID(),
            createdAt: Date(),
            projectName: projectName,
            artboardCount: artboards.count,
            elementCount: artboards.flatMap(\.elements).count,
            includesComponentLibrary: !latestComponentSpecs.isEmpty,
            includesTokenHistory: !tokenRevisions.isEmpty,
            includesImportLossReport: importLossReport != nil
        )

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "\(slugified(projectName))-interop-package.json"
        panel.prompt = "Export Interop Package"

        guard panel.runModal() == .OK, let destination = panel.url else { return nil }

        // Validate the chosen export path
        if !InputValidator.isPathSafe(destination.path) {
            Self.logger.warning("Blocked interop export to unsafe path: \(destination.path, privacy: .public)")
            onSetErrorMessage("The chosen export path contains unsafe characters or patterns.")
            return nil
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            struct AnyInteropPayload: Codable {
                var package: InteropExportPackage
                var designTokens: DesignTokenSet?
                var tokenRevisions: [TokenRevision]
                var components: [ComponentSpec]
                var componentInstances: [ComponentInstance]
                var importLossReport: ImportLossReport?
                var latestBuildQualityReport: BuildQualityReport?
                var latestEnterpriseReadinessReport: EnterpriseReadinessReport?
                var latestBenchmarkReport: BenchmarkRunReport?
                var benchmarkHistory: [BenchmarkRunReport]
                var benchmarkTrendScore: BenchmarkTrendScore?
                var reviewComments: [DesignReviewComment]
                var reviewApprovalState: ReviewApprovalState
                var artboards: [Artboard]
            }

            let typedPayload = AnyInteropPayload(
                package: package,
                designTokens: latestDesignTokens,
                tokenRevisions: tokenRevisions,
                components: latestComponentSpecs,
                componentInstances: componentInstances,
                importLossReport: importLossReport,
                latestBuildQualityReport: latestBuildQualityReport,
                latestEnterpriseReadinessReport: latestEnterpriseReadinessReport,
                latestBenchmarkReport: latestBenchmarkReport,
                benchmarkHistory: benchmarkHistory,
                benchmarkTrendScore: benchmarkTrendScore,
                reviewComments: reviewComments,
                reviewApprovalState: reviewApprovalState,
                artboards: artboards
            )

            let data = try encoder.encode(typedPayload)
            try data.write(to: destination, options: .atomic)
            onAppendMessage(ChatMessage(role: .assistant, text: "Interop package exported: \(destination.path)"))
            onSetErrorMessage(nil)
            return package
        } catch {
            onSetErrorMessage("Could not export interop package: \(error.localizedDescription)")
            return nil
        }
    }
}
