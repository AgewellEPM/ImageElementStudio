import AppKit
import Foundation
import os
import UniformTypeIdentifiers

// MARK: - ProjectService

/// Handles project-level operations such as saving project packages.
///
/// All methods accept the mutable state they need as parameters or inout
/// arguments, keeping the service stateless with respect to the document.
@MainActor
final class ProjectService {

    private static let logger = Logger(
        subsystem: "com.imageelementstudio",
        category: "ProjectService"
    )

    // MARK: - saveProjectPackage

    /// Serialises the current project state into a JSON package and presents an
    /// NSSavePanel so the user can choose a destination.
    ///
    /// - Parameters:
    ///   - projectName: The human-readable project name.
    ///   - projectID: The slugified project identifier.
    ///   - memory: The current ProjectMemory.
    ///   - artboards: All artboards to include.
    ///   - selectedArtboardID: The currently-selected artboard ID.
    ///   - latestScope: The latest ProductScopeSnapshot, if any.
    ///   - latestBlueprint: The latest BuildBlueprint, if any.
    ///   - latestDesignTokens: The latest DesignTokenSet, if any.
    ///   - tokenRevisions: All token revisions.
    ///   - latestComponentSpecs: All component specs.
    ///   - componentInstances: All component instances.
    ///   - importLossReport: The import-loss report, if any.
    ///   - latestInteropPackage: The latest interop export package, if any.
    ///   - latestBuildQualityReport: The latest build quality report, if any.
    ///   - designCodeDiffs: Design-code diff entries.
    ///   - latestFullStackBuildSummary: The latest full-stack build summary, if any.
    ///   - latestEnterpriseReadinessReport: The latest enterprise readiness report, if any.
    ///   - reviewComments: All review comments.
    ///   - reviewApprovalState: The current review approval state.
    ///   - latestBenchmarkReport: The latest benchmark run report, if any.
    ///   - benchmarkHistory: All benchmark run reports.
    ///   - benchmarkTrendScore: The benchmark trend score, if any.
    ///   - currentDocument: The current AnalysisDocument snapshot.
    ///   - slugified: Helper closure that slugifies a string (delegate to BuildExportService).
    ///   - onSetErrorMessage: Setter for the view-model's errorMessage.
    ///   - onAppendMessage: Appends a ChatMessage to the main chat.
    func saveProjectPackage(
        projectName: String,
        projectID: String,
        memory: ProjectMemory,
        artboards: [Artboard],
        selectedArtboardID: UUID?,
        latestScope: ProductScopeSnapshot?,
        latestBlueprint: BuildBlueprint?,
        latestDesignTokens: DesignTokenSet?,
        tokenRevisions: [TokenRevision],
        latestComponentSpecs: [ComponentSpec],
        componentInstances: [ComponentInstance],
        importLossReport: ImportLossReport?,
        latestInteropPackage: InteropExportPackage?,
        latestBuildQualityReport: BuildQualityReport?,
        designCodeDiffs: [DesignCodeDiffEntry],
        latestFullStackBuildSummary: FullStackBuildSummary?,
        latestEnterpriseReadinessReport: EnterpriseReadinessReport?,
        reviewComments: [DesignReviewComment],
        reviewApprovalState: ReviewApprovalState,
        latestBenchmarkReport: BenchmarkRunReport?,
        benchmarkHistory: [BenchmarkRunReport],
        benchmarkTrendScore: BenchmarkTrendScore?,
        currentDocument: AnalysisDocument,
        slugified: (String) -> String,
        onSetErrorMessage: (String?) -> Void,
        onAppendMessage: (ChatMessage) -> Void
    ) {
        let package = ProjectPackage(
            projectName: projectName,
            projectID: projectID,
            savedAt: Date(),
            artboards: artboards,
            selectedArtboardID: selectedArtboardID,
            latestScope: latestScope,
            latestBlueprint: latestBlueprint,
            latestDesignTokens: latestDesignTokens,
            tokenRevisions: tokenRevisions,
            latestComponentSpecs: latestComponentSpecs,
            componentInstances: componentInstances,
            importLossReport: importLossReport,
            latestInteropPackage: latestInteropPackage,
            latestBuildQualityReport: latestBuildQualityReport,
            designCodeDiffs: designCodeDiffs,
            latestFullStackBuildSummary: latestFullStackBuildSummary,
            latestEnterpriseReadinessReport: latestEnterpriseReadinessReport,
            reviewComments: reviewComments,
            reviewApprovalState: reviewApprovalState,
            latestBenchmarkReport: latestBenchmarkReport,
            benchmarkHistory: benchmarkHistory,
            benchmarkTrendScore: benchmarkTrendScore,
            memory: memory,
            currentDocument: currentDocument
        )

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "\(slugified(projectName))-project.json"
        panel.prompt = "Save Project"

        guard panel.runModal() == .OK, let destination = panel.url else { return }

        // Validate the chosen save path
        if !InputValidator.isPathSafe(destination.path) {
            Self.logger.warning("Blocked project save to unsafe path: \(destination.path, privacy: .public)")
            onSetErrorMessage("The chosen save path contains unsafe characters or patterns.")
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(package)
            try data.write(to: destination, options: .atomic)
            onAppendMessage(ChatMessage(role: .assistant, text: "Project saved: \(destination.path)"))
            onSetErrorMessage(nil)
        } catch {
            onSetErrorMessage("Could not save project package: \(error.localizedDescription)")
        }
    }

    // MARK: - Private: ProjectPackage

    private struct ProjectPackage: Codable {
        var projectName: String
        var projectID: String
        var savedAt: Date
        var artboards: [Artboard]
        var selectedArtboardID: UUID?
        var latestScope: ProductScopeSnapshot?
        var latestBlueprint: BuildBlueprint?
        var latestDesignTokens: DesignTokenSet?
        var tokenRevisions: [TokenRevision]
        var latestComponentSpecs: [ComponentSpec]
        var componentInstances: [ComponentInstance]
        var importLossReport: ImportLossReport?
        var latestInteropPackage: InteropExportPackage?
        var latestBuildQualityReport: BuildQualityReport?
        var designCodeDiffs: [DesignCodeDiffEntry]
        var latestFullStackBuildSummary: FullStackBuildSummary?
        var latestEnterpriseReadinessReport: EnterpriseReadinessReport?
        var reviewComments: [DesignReviewComment]
        var reviewApprovalState: ReviewApprovalState
        var latestBenchmarkReport: BenchmarkRunReport?
        var benchmarkHistory: [BenchmarkRunReport]
        var benchmarkTrendScore: BenchmarkTrendScore?
        var memory: ProjectMemory
        var currentDocument: AnalysisDocument
    }
}
