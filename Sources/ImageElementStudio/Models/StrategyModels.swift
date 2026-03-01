import Foundation

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
