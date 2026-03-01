import Foundation

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
