import Foundation

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
