import Foundation

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
