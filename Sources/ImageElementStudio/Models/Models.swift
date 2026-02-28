import Foundation

enum ElementKind: String, Codable, CaseIterable, Hashable {
    case imageRoot
    case text
    case shape
}

enum SemanticElementRole: String, Codable, CaseIterable, Hashable {
    case unknown
    case appBrand
    case navigationItem
    case navigationSection
    case heading
    case sectionTitle
    case metricValue
    case metricLabel
    case metricDelta
    case chart
    case chartAxis
    case tableHeader
    case tableCell
    case buttonPrimary
    case buttonSecondary
    case dateFilter
    case avatar
    case tag
    case panel
    case listItem
}

struct ElementFrame: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

enum ConstraintPin: String, Codable, CaseIterable, Hashable, Identifiable {
    case left
    case right
    case top
    case bottom
    case centerX
    case centerY
    case fixedWidth
    case fixedHeight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left:
            return "Left"
        case .right:
            return "Right"
        case .top:
            return "Top"
        case .bottom:
            return "Bottom"
        case .centerX:
            return "Center X"
        case .centerY:
            return "Center Y"
        case .fixedWidth:
            return "Fixed Width"
        case .fixedHeight:
            return "Fixed Height"
        }
    }
}

struct ElementTypographyStyle: Codable, Hashable {
    var family: String?
    var weight: String?
    var size: Double?
    var lineHeight: Double?
    var letterSpacing: Double?
}

struct ElementStrokeStyle: Codable, Hashable {
    var color: String?
    var width: Double?
}

struct ElementFillStyle: Codable, Hashable {
    var color: String?
    var gradient: String?
}

struct ElementVisualStyle: Codable, Hashable {
    var fill: ElementFillStyle?
    var stroke: ElementStrokeStyle?
    var cornerRadius: Double?
    var opacity: Double?
    var typography: ElementTypographyStyle?
}

struct CanvasElement: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var kind: ElementKind
    var frame: ElementFrame
    var confidence: Double
    var content: String?
    var tags: [String]
    var semanticRole: SemanticElementRole?
    var semanticReason: String?
    var rotationDegrees: Double
    var constraints: [ConstraintPin]
    var parentElementID: UUID?
    var componentReferenceID: UUID?
    var instanceOverrides: [String: String]
    var style: ElementVisualStyle?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case frame
        case confidence
        case content
        case tags
        case semanticRole
        case semanticReason
        case rotationDegrees
        case constraints
        case parentElementID
        case componentReferenceID
        case instanceOverrides
        case style
    }

    init(
        id: UUID,
        name: String,
        kind: ElementKind,
        frame: ElementFrame,
        confidence: Double,
        content: String?,
        tags: [String],
        semanticRole: SemanticElementRole?,
        semanticReason: String?,
        rotationDegrees: Double = 0,
        constraints: [ConstraintPin] = [],
        parentElementID: UUID? = nil,
        componentReferenceID: UUID? = nil,
        instanceOverrides: [String: String] = [:],
        style: ElementVisualStyle? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.frame = frame
        self.confidence = confidence
        self.content = content
        self.tags = tags
        self.semanticRole = semanticRole
        self.semanticReason = semanticReason
        self.rotationDegrees = rotationDegrees
        self.constraints = constraints
        self.parentElementID = parentElementID
        self.componentReferenceID = componentReferenceID
        self.instanceOverrides = instanceOverrides
        self.style = style
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(ElementKind.self, forKey: .kind)
        frame = try container.decode(ElementFrame.self, forKey: .frame)
        confidence = try container.decode(Double.self, forKey: .confidence)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        semanticRole = try container.decodeIfPresent(SemanticElementRole.self, forKey: .semanticRole)
        semanticReason = try container.decodeIfPresent(String.self, forKey: .semanticReason)
        rotationDegrees = try container.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0
        constraints = try container.decodeIfPresent([ConstraintPin].self, forKey: .constraints) ?? []
        parentElementID = try container.decodeIfPresent(UUID.self, forKey: .parentElementID)
        componentReferenceID = try container.decodeIfPresent(UUID.self, forKey: .componentReferenceID)
        instanceOverrides = try container.decodeIfPresent([String: String].self, forKey: .instanceOverrides) ?? [:]
        style = try container.decodeIfPresent(ElementVisualStyle.self, forKey: .style)
    }
}

struct ImageDescriptor: Codable, Hashable {
    var filename: String
    var width: Int
    var height: Int
}

struct AnalysisMetadata: Codable, Hashable {
    var generatedAt: Date
    var engine: String
    var notes: [String]
}

struct ProductScopeSnapshot: Codable, Hashable {
    var appType: String
    var confidence: Double
    var productIntent: String
    var targetUsers: [String]
    var keyCapabilities: [String]
    var openQuestions: [String]
    var implementationRoadmap: [String]
    var summary: String
}

enum StrategyStage: String, Codable, CaseIterable, Hashable, Identifiable {
    case vision
    case users
    case jobs
    case feature_scope
    case constraints
    case success_metrics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vision:
            return "Vision"
        case .users:
            return "Users"
        case .jobs:
            return "Jobs-To-Be-Done"
        case .feature_scope:
            return "Feature Scope"
        case .constraints:
            return "Constraints"
        case .success_metrics:
            return "Success Metrics"
        }
    }

    var shortInstruction: String {
        switch self {
        case .vision:
            return "Define the product outcome for v1."
        case .users:
            return "Lock primary user segments."
        case .jobs:
            return "Capture top user jobs."
        case .feature_scope:
            return "Separate must-haves from later scope."
        case .constraints:
            return "Record technical and delivery constraints."
        case .success_metrics:
            return "Set launch metrics and targets."
        }
    }

    var next: StrategyStage? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
        return all[index + 1]
    }
}

struct StrategyQuestion: Identifiable, Codable, Hashable {
    var id: String
    var stage: StrategyStage
    var prompt: String
    var whyAsked: String
    var required: Bool
    var options: [String]?
}

struct StrategyAnswer: Codable, Hashable {
    var questionID: String
    var answerText: String
    var confidence: Double
    var createdAt: Date
}

enum PipelineMode: String, Codable, CaseIterable, Hashable, Identifiable {
    case auto
    case guided
    case hybrid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:
            return "Auto"
        case .guided:
            return "Guided"
        case .hybrid:
            return "Hybrid"
        }
    }
}

enum MockupStylePreset: String, Codable, CaseIterable, Hashable, Identifiable {
    case apple_hig
    case adobe_expressive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple_hig:
            return "Apple HIG"
        case .adobe_expressive:
            return "Adobe Expressive"
        }
    }
}

struct StrategySession: Identifiable, Codable, Hashable {
    var id: UUID
    var projectID: String
    var stage: StrategyStage
    var ideaSeed: String
    var questions: [StrategyQuestion]
    var answers: [StrategyAnswer]
    var confidence: Double
    var isComplete: Bool
    var pipelineMode: PipelineMode
    var createdAt: Date
}

struct StrategySpec: Identifiable, Codable, Hashable {
    var id: UUID
    var sessionID: UUID
    var projectID: String
    var createdAt: Date
    var confidence: Double
    var vision: String
    var targetUsers: [String]
    var jobsToBeDone: [String]
    var mustHaveFeatures: [String]
    var laterFeatures: [String]
    var constraints: [String]
    var successMetrics: [String]
    var summary: String
    var planningNotes: [String]

    var ideaPrompt: String {
        let mustHave = mustHaveFeatures.isEmpty ? "core launch features" : mustHaveFeatures.joined(separator: ", ")
        let users = targetUsers.isEmpty ? "general users" : targetUsers.joined(separator: ", ")
        return "\(vision). Primary users: \(users). Must-have features: \(mustHave)."
    }
}

struct StrategyDecisionLogEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var message: String
    var stage: StrategyStage?
    var confidence: Double?
}

struct DesignTokenSet: Codable, Hashable {
    var colors: [String: String]
    var typography: [String: String]
    var spacing: [String: Double]
    var radius: [String: Double]
    var shadow: [String: Double]
    var motion: [String: Double]
}

struct TokenRevision: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var reason: String
    var tokens: DesignTokenSet
}

enum ComponentKind: String, Codable, CaseIterable, Hashable {
    case nav
    case card
    case table
    case form
    case cta
    case chart
    case list
    case panel
}

struct ComponentSpec: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var kind: ComponentKind
    var role: SemanticElementRole?
    var elementIDs: [UUID]
    var notes: String
    var variantAxes: [String: [String]]? = nil
    var stateMappings: [String: String]? = nil
    var tokenBindings: [String: String]? = nil
    var instanceElementIDs: [UUID]? = nil
    var version: Int? = nil
}

struct ComponentInstance: Identifiable, Codable, Hashable {
    var id: UUID
    var componentID: UUID
    var name: String
    var artboardID: UUID
    var elementIDs: [UUID]
    var variantSelection: [String: String]
    var state: String
    var overrides: [String: String]
}

enum ImportLossSeverity: String, Codable, CaseIterable, Hashable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }
}

struct ImportLossItem: Identifiable, Codable, Hashable {
    var id: UUID
    var category: String
    var detail: String
    var severity: ImportLossSeverity
    var affectedElementCount: Int
}

struct ImportLossReport: Codable, Hashable {
    var sourceFilename: String
    var importedAt: Date
    var totalNodeCount: Int
    var successfullyMappedCount: Int
    var lossItems: [ImportLossItem]
    var estimatedManualCleanupPercent: Double
}

struct InteropExportPackage: Codable, Hashable {
    var packageID: UUID
    var createdAt: Date
    var projectName: String
    var artboardCount: Int
    var elementCount: Int
    var includesComponentLibrary: Bool
    var includesTokenHistory: Bool
    var includesImportLossReport: Bool
}

enum ReviewApprovalState: String, Codable, CaseIterable, Hashable, Identifiable {
    case pending
    case approved
    case changesRequested

    var id: String { rawValue }
}

struct DesignReviewComment: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var author: String
    var assignee: String? = nil
    var dueDate: Date? = nil
    var message: String
    var artboardID: UUID?
    var elementID: UUID?
    var resolved: Bool
}

struct DesignCodeDiffEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var category: String
    var title: String
    var detail: String
    var impactScore: Double
}

struct SmokeCheckResult: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String? = nil
    var target: String
    var command: String
    var passed: Bool
    var output: String
}

struct BuildQualityReport: Codable, Hashable {
    var generatedAt: Date
    var deterministicHash: String
    var smokeChecks: [SmokeCheckResult]
    var passRate: Double
    var diffs: [DesignCodeDiffEntry]
    var qualityGateSummary: QualityGateSummary? = nil
}

enum QualityGateStatus: String, Codable, CaseIterable, Hashable {
    case pass
    case warning
    case fail
}

struct QualityGateSummary: Codable, Hashable {
    var generatedAt: Date
    var overallScore: Double
    var status: QualityGateStatus
    var smokePassRate: Double
    var fullAppPassRate: Double
    var diffHealthScore: Double
    var benchmarkPassRate: Double
    var reviewGatePassed: Bool
    var overdueCommentCount: Int
    var blockingIssues: [String]
}

struct BenchmarkTrendArtifact: Codable, Hashable {
    var generatedAt: Date
    var projectName: String
    var projectID: String
    var target: String
    var deterministicHash: String
    var latestBenchmarkReport: BenchmarkRunReport?
    var trendScore: BenchmarkTrendScore?
    var history: [BenchmarkRunReport]
}

struct FullStackTargetResult: Codable, Hashable, Identifiable {
    var target: String
    var outputPath: String
    var deterministicHash: String
    var smokePassCount: Int
    var smokeTotalCount: Int
    var smokePassRate: Double
    var fullAppPassRate: Double
    var qualityScore: Double
    var passed: Bool
    var blockingIssues: [String]

    var id: String { target }
}

struct FullStackBuildSummary: Codable, Hashable {
    var runID: UUID
    var generatedAt: Date
    var projectName: String
    var projectID: String
    var reviewGatePassed: Bool
    var aggregateScore: Double
    var allTargetsPassed: Bool
    var targetResults: [FullStackTargetResult]
    var blockingIssues: [String]
}

struct GeneratedAppScreen: Codable, Hashable {
    var id: UUID
    var name: String
    var state: String
    var summary: String
    var capabilityHints: [String]
}

enum EnterpriseReadinessStatus: String, Codable, CaseIterable, Hashable {
    case pass
    case warning
    case fail
}

struct EnterpriseReadinessCheck: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var weight: Double
    var passed: Bool
    var detail: String
}

struct EnterpriseReadinessReport: Codable, Hashable {
    var runID: UUID
    var generatedAt: Date
    var projectName: String
    var projectID: String
    var status: EnterpriseReadinessStatus
    var score: Double
    var checks: [EnterpriseReadinessCheck]
    var blockers: [String]
    var recommendedActions: [String]
}

struct GeneratedFlowTransition: Codable, Hashable {
    var id: UUID
    var controlLabel: String
    var fromState: String
    var toState: String
    var rationale: String
}

struct GeneratedAppSpec: Codable, Hashable {
    var generatedAt: Date
    var projectName: String
    var projectID: String
    var target: String
    var deterministicHash: String
    var appType: String?
    var productIntent: String?
    var initialState: String
    var states: [String]
    var controls: [String]
    var capabilities: [String]
    var screens: [GeneratedAppScreen]
    var transitions: [GeneratedFlowTransition]
}

struct BenchmarkStepResult: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var passed: Bool
    var detail: String
    var latencyMilliseconds: Double? = nil
}

struct BenchmarkRunReport: Codable, Hashable {
    var generatedAt: Date
    var scenario: String
    var passed: Bool
    var steps: [BenchmarkStepResult]

    var stepPassRate: Double {
        guard !steps.isEmpty else { return 0 }
        let passCount = steps.filter(\.passed).count
        return Double(passCount) / Double(steps.count)
    }

    var medianStepLatencyMilliseconds: Double? {
        let latencies = steps.compactMap(\.latencyMilliseconds)
        guard !latencies.isEmpty else { return nil }
        let sorted = latencies.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

struct BenchmarkTrendPoint: Codable, Hashable, Identifiable {
    var runID: String
    var generatedAt: Date
    var passRate: Double
    var medianStepLatencyMilliseconds: Double?
    var runPassed: Bool

    var id: String { runID }
}

struct BenchmarkTrendScore: Codable, Hashable {
    var generatedAt: Date
    var windowSize: Int
    var runCount: Int
    var passRate: Double
    var medianStepLatencyMilliseconds: Double?
    var points: [BenchmarkTrendPoint]
}

struct MockupGenerationResult: Codable, Hashable {
    var artboards: [Artboard]
    var tokens: DesignTokenSet
    var components: [ComponentSpec]
    var notes: [String]
}

enum InferredControlKind: String, Codable, CaseIterable, Hashable {
    case button
    case navigation
    case filter
    case input
    case tab
    case menu
    case chart
    case table
    case unknown
}

struct InferredControl: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var label: String
    var kind: InferredControlKind
    var role: SemanticElementRole
    var sourceElementID: UUID?
    var frame: ElementFrame?
    var confidence: Double
    var rationale: String
}

struct InferredState: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var triggerControlID: UUID?
    var triggerLabel: String
    var description: String
    var confidence: Double
}

struct SuggestedArtboard: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var sourceStateID: UUID?
    var reason: String
    var confidence: Double
}

struct BuildBlueprint: Codable, Hashable {
    var mirrorScore: Double
    var detectionSummary: String
    var controls: [InferredControl]
    var states: [InferredState]
    var suggestedArtboards: [SuggestedArtboard]
    var buildNotes: [String]
}

struct Artboard: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var width: Int
    var height: Int
    var elements: [CanvasElement]
}

struct AnalysisDocument: Codable, Hashable {
    var image: ImageDescriptor
    var artboard: Artboard
    var metadata: AnalysisMetadata
    var scope: ProductScopeSnapshot?
    var blueprint: BuildBlueprint?
}

struct ProjectMemoryEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var imageName: String
    var appType: String
    var summary: String
    var capabilities: [String]
    var openQuestions: [String]
    var artboardName: String?
    var elementCount: Int?
    var snapshotReason: String?
}

struct ProjectMemory: Codable, Hashable {
    var createdAt: Date
    var updatedAt: Date
    var projectID: String?
    var projectName: String?
    var workingHypothesis: String
    var latestSummary: String
    var productScope: [String]
    var entries: [ProjectMemoryEntry]
    var strategySessions: [StrategySession]
    var acceptedStrategySpecs: [StrategySpec]
    var decisionLog: [StrategyDecisionLogEntry]

    enum CodingKeys: String, CodingKey {
        case createdAt
        case updatedAt
        case projectID
        case projectName
        case workingHypothesis
        case latestSummary
        case productScope
        case entries
        case strategySessions
        case acceptedStrategySpecs
        case decisionLog
    }

    init(
        createdAt: Date,
        updatedAt: Date,
        projectID: String?,
        projectName: String?,
        workingHypothesis: String,
        latestSummary: String,
        productScope: [String],
        entries: [ProjectMemoryEntry],
        strategySessions: [StrategySession] = [],
        acceptedStrategySpecs: [StrategySpec] = [],
        decisionLog: [StrategyDecisionLogEntry] = []
    ) {
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.projectID = projectID
        self.projectName = projectName
        self.workingHypothesis = workingHypothesis
        self.latestSummary = latestSummary
        self.productScope = productScope
        self.entries = entries
        self.strategySessions = strategySessions
        self.acceptedStrategySpecs = acceptedStrategySpecs
        self.decisionLog = decisionLog
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        projectID = try container.decodeIfPresent(String.self, forKey: .projectID)
        projectName = try container.decodeIfPresent(String.self, forKey: .projectName)
        workingHypothesis = try container.decodeIfPresent(String.self, forKey: .workingHypothesis) ?? ""
        latestSummary = try container.decodeIfPresent(String.self, forKey: .latestSummary) ?? ""
        productScope = try container.decodeIfPresent([String].self, forKey: .productScope) ?? []
        entries = try container.decodeIfPresent([ProjectMemoryEntry].self, forKey: .entries) ?? []
        strategySessions = try container.decodeIfPresent([StrategySession].self, forKey: .strategySessions) ?? []
        acceptedStrategySpecs = try container.decodeIfPresent([StrategySpec].self, forKey: .acceptedStrategySpecs) ?? []
        decisionLog = try container.decodeIfPresent([StrategyDecisionLogEntry].self, forKey: .decisionLog) ?? []
    }
}

struct ChatMessage: Identifiable, Hashable {
    enum Role: String, Hashable {
        case system
        case user
        case assistant
    }

    var id: UUID = UUID()
    var role: Role
    var text: String
    var createdAt: Date = Date()
}

extension CanvasElement {
    static func root(width: Int, height: Int, filename: String?) -> CanvasElement {
        CanvasElement(
            id: UUID(),
            name: "Canvas Root",
            kind: .imageRoot,
            frame: ElementFrame(x: 0, y: 0, width: Double(width), height: Double(height)),
            confidence: 1.0,
            content: filename,
            tags: ["root", "canvas"],
            semanticRole: .unknown,
            semanticReason: "Canvas bounds"
        )
    }
}

extension Artboard {
    static func empty(named name: String = "Main Artboard", width: Int = 1280, height: Int = 720, filename: String? = nil) -> Artboard {
        Artboard(
            id: UUID(),
            name: name,
            width: width,
            height: height,
            elements: [CanvasElement.root(width: width, height: height, filename: filename)]
        )
    }
}

extension ElementFrame {
    var minX: Double { x }
    var maxX: Double { x + width }
    var minY: Double { y }
    var maxY: Double { y + height }
    var midX: Double { x + width / 2 }
    var midY: Double { y + height / 2 }

    func intersects(_ other: ElementFrame) -> Bool {
        !(other.maxX < minX || other.minX > maxX || other.maxY < minY || other.minY > maxY)
    }
}
