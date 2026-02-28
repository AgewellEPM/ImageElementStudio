import Foundation

// MARK: - File Role

enum FileRole: String, Codable, Hashable, Sendable {
    case appEntry
    case rootView
    case screenView
    case componentView
    case dataModel
    case viewModel
    case theme
    case projectConfig
    case readme
    case webMarkup
    case webStyle
    case webScript
    case appSpec
    case unknown
}

// MARK: - Generated File Entry

struct GeneratedFileEntry: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var relativePath: String
    var content: String
    var role: FileRole
}

// MARK: - File Plan Entry (from architecture plan)

struct FilePlanEntry: Sendable {
    var name: String
    var relativePath: String
    var role: FileRole
    var description: String
    var keyTypes: [String]
    var dependencies: [String]
}

// MARK: - Generation Quality

enum AIGenerationQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case fast
    case quality

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fast: return "Fast (Sonnet)"
        case .quality: return "Quality (Opus)"
        }
    }

    var modelID: String {
        switch self {
        case .fast: return "claude-sonnet-4-5-20250929"
        case .quality: return "claude-opus-4-6"
        }
    }
}

// MARK: - Generation State

enum AIGenerationState: Sendable {
    case idle
    case analyzingDesign
    case planningArchitecture(progress: String)
    case generatingFile(name: String, index: Int, total: Int, streamedText: String)
    case validating(name: String)
    case fixing(name: String, attempt: Int)
    case writingToDisk
    case complete(outputPath: String)
    case failed(String)

    var isActive: Bool {
        switch self {
        case .idle, .complete, .failed: return false
        default: return true
        }
    }

    var statusText: String {
        switch self {
        case .idle: return "Ready"
        case .analyzingDesign: return "Analyzing design..."
        case .planningArchitecture: return "Planning architecture..."
        case .generatingFile(let name, let index, let total, _):
            return "Generating \(name) (\(index + 1)/\(total))..."
        case .validating(let name): return "Validating \(name)..."
        case .fixing(let name, let attempt): return "Fixing \(name) (attempt \(attempt))..."
        case .writingToDisk: return "Writing files..."
        case .complete(let path): return "Complete: \(path)"
        case .failed(let error): return "Failed: \(error)"
        }
    }
}

// MARK: - Architecture Plan Response

struct ArchitecturePlanResponse: Codable, Sendable {
    var appName: String
    var summary: String
    var files: [ArchitectureFileSpec]
    var dataModels: [ArchitectureDataModel]?
    var navigationFlow: String?
    var designNotes: String?
}

struct ArchitectureFileSpec: Codable, Sendable {
    var name: String
    var relativePath: String
    var role: String
    var description: String
    var keyTypes: [String]?
    var dependencies: [String]?
}

struct ArchitectureDataModel: Codable, Sendable {
    var name: String
    var fields: [String]?
}
