import Foundation

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

struct AnalysisDocument: Codable, Hashable {
    var image: ImageDescriptor
    var artboard: Artboard
    var metadata: AnalysisMetadata
    var scope: ProductScopeSnapshot?
    var blueprint: BuildBlueprint?
}
