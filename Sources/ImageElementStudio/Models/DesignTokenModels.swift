import Foundation

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
