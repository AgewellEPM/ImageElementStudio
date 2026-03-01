import Foundation

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

struct GeneratedAppScreen: Codable, Hashable {
    var id: UUID
    var name: String
    var state: String
    var summary: String
    var capabilityHints: [String]
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

struct MockupGenerationResult: Codable, Hashable {
    var artboards: [Artboard]
    var tokens: DesignTokenSet
    var components: [ComponentSpec]
    var notes: [String]
}
