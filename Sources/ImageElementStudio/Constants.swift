import Foundation

/// Centralized constants extracted from magic numbers throughout the codebase.
/// Organized by domain using caseless enums to prevent accidental instantiation.
enum Constants {

    // MARK: - Benchmark

    enum Benchmark {
        /// Maximum number of benchmark reports retained in history.
        static let maxHistoryEntries = 40
        /// Number of recent benchmark reports shown in the history preview.
        static let historyPreviewCount = 6
        /// Default window size for computing benchmark trend scores.
        static let defaultTrendWindowSize = 12
        /// Number of benchmark history entries written to the trend artifact.
        static let trendArtifactHistoryCount = 24
        /// Pass-rate delta threshold that signals an improving trend.
        static let improvingPassRateDelta = 0.08
        /// Pass-rate delta threshold that signals a regressing trend.
        static let regressingPassRateDelta = -0.08
        /// Latency delta (ms) threshold for trend direction judgements.
        static let latencyDeltaThreshold = 10.0
        /// Number of candidate elements selected for the benchmark multi-select step.
        static let multiSelectCandidateCount = 3
        /// Resize delta used by the benchmark resize-handles step.
        static let benchmarkResizeDelta = 8.0
        /// Rotation delta (degrees) used by the benchmark rotate step.
        static let benchmarkRotateDegrees = 5.0
    }

    // MARK: - Canvas

    enum Canvas {
        /// Minimum element size (width or height) enforced during resize operations.
        static let minimumElementSize = 16.0
        /// Default grid size in points.
        static let defaultGridSize = 8.0
        /// Default distribution gap between elements.
        static let defaultDistributionGap = 12.0
        /// Default keyboard nudge amount in points.
        static let defaultKeyboardNudgeAmount = 4.0
        /// Keyboard nudge fast multiplier (shift-arrow).
        static let fastNudgeMultiplier = 3.0
        /// Rotation step for keyboard rotation (degrees).
        static let keyboardRotationStep = 5.0
        /// Minimum grid unit floor (used in snap calculations).
        static let minimumGridUnit = 2.0
        /// Default canvas width when no artboard is available.
        static let defaultCanvasWidth = 1280.0
        /// Default canvas height when no artboard is available.
        static let defaultCanvasHeight = 720.0
    }

    // MARK: - Quality Gate

    enum QualityGate {
        /// Score threshold at or above which the quality gate status is `.pass`.
        static let passScoreThreshold = 85.0
        /// Score threshold at or above which the quality gate status is `.warning` (below pass).
        static let warningScoreThreshold = 65.0
        /// Default rate used when no smoke checks have been captured.
        static let defaultNoDataRate = 0.5
        /// Smoke-check pass-rate threshold below which a blocking issue is raised.
        static let smokePassRateThreshold = 0.9
        /// Full-app smoke-check pass-rate threshold below which a blocking issue is raised.
        static let fullAppPassRateThreshold = 0.9
        /// Design/code diff impact score at or above which drift is considered high-impact.
        static let highImpactDiffThreshold = 0.7
        /// Benchmark trend pass-rate below which a quality warning is raised.
        static let benchmarkPassRateWarningThreshold = 0.8
        /// Maximum points awarded for smoke-check pass rate (weight = 30).
        static let smokeCheckMaxPoints = 30.0
        /// Maximum points awarded for full-app checks (weight = 15).
        static let fullAppMaxPoints = 15.0
        /// Maximum points awarded for diff health (weight = 20).
        static let diffHealthMaxPoints = 20.0
        /// Maximum points awarded for benchmark pass rate (weight = 20).
        static let benchmarkMaxPoints = 20.0
        /// Points awarded when the review gate passes (weight = 15).
        static let reviewGatePoints = 15.0
        /// Per-overdue-comment penalty applied to the quality gate score.
        static let overdueCommentPenalty = 2.0
        /// Maximum total overdue-comment penalty.
        static let maxOverduePenalty = 10.0
    }

    // MARK: - Enterprise Readiness

    enum Enterprise {
        /// Enterprise readiness pass score threshold.
        static let passScoreThreshold = 85.0
        /// Enterprise readiness warning score threshold.
        static let warningScoreThreshold = 65.0
        /// Benchmark trend pass-rate threshold for enterprise readiness.
        static let benchmarkPassRateThreshold = 0.85
        /// Maximum acceptable import cleanup percentage.
        static let maxImportCleanupPercent = 20.0
    }

    // MARK: - Memory / Persistence

    enum Memory {
        /// Maximum number of memory entries retained per project.
        static let maxEntries = 80
        /// Maximum number of strategy sessions retained per project.
        static let maxStrategySessions = 24
        /// Maximum number of accepted strategy specs retained per project.
        static let maxAcceptedStrategySpecs = 18
        /// Maximum number of decision log entries retained per project.
        static let maxDecisionLogEntries = 80
        /// Maximum number of token revisions retained.
        static let maxTokenRevisions = 80
        /// Maximum number of project-creation naming attempts before falling back to a timestamp.
        static let maxProjectNameAttempts = 40
        /// Maximum length for a project ID slug.
        static let maxProjectIDLength = 48
        /// Time interval (seconds) within which duplicate memory entries are coalesced.
        static let coalesceInterval = 3.5
        /// Maximum number of merged product scope capabilities retained.
        static let maxMergedScopeCapabilities = 14
    }

    // MARK: - Preview Limits

    /// Limits used for preview arrays displayed in the UI.
    enum Preview {
        /// Number of memory entries shown in the sidebar preview.
        static let memoryEntriesCount = 4
        /// Number of component specs shown in preview.
        static let componentSpecsCount = 5
        /// Number of blocking issues shown in preview lists.
        static let issuePreviewCount = 4
        /// Number of token revisions shown in the design token panel.
        static let tokenRevisionsCount = 4
        /// Number of benchmark trend points shown in the chart.
        static let trendPointsCount = 16
        /// Number of benchmark history items shown in the panel.
        static let benchmarkHistoryPanelCount = 3
        /// Number of review comments shown in the panel preview.
        static let reviewCommentsCount = 5
        /// Number of variant matrix rows shown.
        static let variantMatrixRowCount = 5
    }

    // MARK: - Image Analysis

    enum Analysis {
        /// Minimum text height for VNRecognizeTextRequest (fraction of image height).
        static let minimumTextHeight: Float = 0.008
        /// Maximum rectangle observations for VNDetectRectanglesRequest.
        static let maximumRectangleObservations = 80
        /// Minimum aspect ratio for rectangle detection.
        static let minimumRectangleAspectRatio: Float = 0.12
        /// Minimum rectangle size (fraction of image size).
        static let minimumRectangleSize: Float = 0.02
        /// Minimum confidence for rectangle detection.
        static let minimumRectangleConfidence: Float = 0.35
        /// Minimum text fragment width in pixels.
        static let minimumTextFragmentWidth = 12.0
        /// Minimum text fragment height in pixels.
        static let minimumTextFragmentHeight = 8.0
        /// Minimum shape element width in pixels.
        static let minimumShapeSize = 24.0
        /// Overlap ratio threshold for filtering shapes that overlap text.
        static let shapeTextOverlapThreshold = 0.72
        /// Vertical overlap ratio threshold for merging text lines.
        static let textMergeVerticalOverlapThreshold = 0.45
        /// Minimum merge threshold in points for horizontal text merging.
        static let textMergeMinThreshold = 10.0
        /// Merge threshold multiplier relative to average line height.
        static let textMergeHeightMultiplier = 1.15
        /// Minimum space gap to include a space character when merging text.
        static let textMergeSpaceGap = 2.0
        /// Overlap ratio threshold for deduplicating text fragments.
        static let textDeduplicationOverlapThreshold = 0.82
        /// Maximum text element name length before truncation.
        static let maxTextElementNameLength = 30
        /// Truncated text element name prefix length.
        static let truncatedTextNamePrefixLength = 27
        /// Minimum line center tolerance in points for same-line detection.
        static let sameLineMinTolerance = 7.0
        /// Height multiplier for same-line tolerance.
        static let sameLineHeightMultiplier = 0.7
        /// Vertical overlap threshold for same-line detection.
        static let sameLineOverlapThreshold = 0.35
    }

    // MARK: - Token Radius

    enum TokenRadius {
        /// Maximum clamped token radius value.
        static let maxValue = 28.0
        /// Minimum clamped token radius value.
        static let minValue = 2.0
    }

    // MARK: - Blueprint Inference

    enum Blueprint {
        /// Maximum number of controls processed for state inference.
        static let maxControlsForStateInference = 18
        /// Maximum number of inferred states retained.
        static let maxInferredStates = 20
        /// Maximum number of suggested artboards generated from states.
        static let maxSuggestedArtboards = 10
        /// Maximum label length before truncation.
        static let maxLabelLength = 50
        /// Truncated label prefix length.
        static let truncatedLabelPrefixLength = 47
    }

    // MARK: - Idea Planner

    enum IdeaPlanner {
        /// Maximum number of screens generated from an idea.
        static let maxScreens = 6
        /// Maximum number of inferred capabilities.
        static let maxCapabilities = 7
        /// Maximum number of build notes retained.
        static let maxBuildNotes = 8
    }

    // MARK: - Build Manifest

    enum BuildManifest {
        /// Current schema version for build manifests.
        static let schemaVersion = 4
    }

    // MARK: - Heuristic Semantic Engine

    enum SemanticEngine {
        /// Left zone boundary as a fraction of board width.
        static let leftZoneFraction = 0.24
        /// Top zone boundary as a fraction of board height.
        static let topZoneFraction = 0.2
        /// Large shape width threshold as a fraction of board width.
        static let largeShapeWidthFraction = 0.36
        /// Large shape height threshold as a fraction of board height.
        static let largeShapeHeightFraction = 0.18
        /// Mid-content vertical boundary as a fraction of board height.
        static let midContentBoundaryFraction = 0.72
        /// Table header vertical boundary as a fraction of board height.
        static let tableHeaderBoundaryFraction = 0.45
        /// Base confidence for app type classification.
        static let baseAppTypeConfidence = 0.42
        /// Per-keyword confidence increment for app type classification.
        static let perKeywordConfidenceIncrement = 0.09
        /// Maximum confidence cap for app type classification.
        static let maxAppTypeConfidence = 0.97
        /// Maximum open questions shown.
        static let maxOpenQuestions = 4
        /// Maximum capabilities shown in narrative prefix.
        static let narrativeCapabilityCount = 3
    }

    // MARK: - Scaffold Generator

    enum Scaffold {
        /// Maximum number of suggested artboard states written to scaffold.
        static let maxSuggestedStates = 16
        /// Maximum number of inferred states/controls written to scaffold diffs.
        static let maxStatesInDiff = 10
        /// Number of capability hints in scaffold.
        static let capabilityHintCount = 3
    }
}
