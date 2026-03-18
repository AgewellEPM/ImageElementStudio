import Foundation

enum DeploymentTarget: String, Codable, CaseIterable, Hashable, Identifiable {
    case appStore
    case testFlight
    case adHoc
    case directNotarized

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appStore: return "App Store"
        case .testFlight: return "TestFlight"
        case .adHoc: return "Ad Hoc"
        case .directNotarized: return "Direct (Notarized)"
        }
    }

    var description: String {
        switch self {
        case .appStore: return "Submit to the App Store for public distribution"
        case .testFlight: return "Distribute to testers via TestFlight"
        case .adHoc: return "Export for ad-hoc installation on registered devices"
        case .directNotarized: return "Export a notarized .app or .dmg for direct distribution"
        }
    }

    var symbolName: String {
        switch self {
        case .appStore: return "app.badge.checkmark"
        case .testFlight: return "airplane"
        case .adHoc: return "square.and.arrow.up"
        case .directNotarized: return "signature"
        }
    }

    var requiresAppStoreConnect: Bool {
        self == .appStore || self == .testFlight
    }

    var outputFormat: String {
        switch self {
        case .appStore, .testFlight: return ".ipa"
        case .adHoc: return ".ipa"
        case .directNotarized: return ".dmg"
        }
    }

    var exportMethod: String {
        switch self {
        case .appStore: return "app-store-connect"
        case .testFlight: return "app-store-connect"
        case .adHoc: return "ad-hoc"
        case .directNotarized: return "developer-id"
        }
    }
}

struct SigningConfiguration: Codable, Hashable {
    var teamID: String = ""
    var signingIdentity: String = ""
    var provisioningProfileUUID: String?
    var codeSignStyle: String = "Automatic"

    var isValid: Bool {
        !teamID.isEmpty && !signingIdentity.isEmpty
    }
}

struct AppDeploymentMetadata: Codable, Hashable {
    var displayName: String = ""
    var bundleID: String = ""
    var version: String = "1.0.0"
    var buildNumber: String = "1"
    var minimumDeploymentTarget: String = "17.0"
    var appCategory: String = "public.app-category.utilities"

    var isValid: Bool {
        !displayName.isEmpty && !bundleID.isEmpty && !version.isEmpty && !buildNumber.isEmpty
    }
}

enum DeploymentStep: Int, CaseIterable, Identifiable, Hashable {
    case chooseTarget = 0
    case configureSigning = 1
    case appMetadata = 2
    case buildArchive = 3
    case submitExport = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .chooseTarget: return "Target"
        case .configureSigning: return "Signing"
        case .appMetadata: return "Metadata"
        case .buildArchive: return "Build"
        case .submitExport: return "Deploy"
        }
    }

    var fullTitle: String {
        switch self {
        case .chooseTarget: return "Choose Deployment Target"
        case .configureSigning: return "Configure Code Signing"
        case .appMetadata: return "App Metadata"
        case .buildArchive: return "Build & Archive"
        case .submitExport: return "Submit or Export"
        }
    }

    var symbolName: String {
        switch self {
        case .chooseTarget: return "target"
        case .configureSigning: return "signature"
        case .appMetadata: return "doc.text"
        case .buildArchive: return "hammer"
        case .submitExport: return "paperplane"
        }
    }
}

struct DeploymentResult: Codable, Hashable {
    var target: String
    var outputPath: String
    var archivePath: String?
    var succeeded: Bool
    var errorMessage: String?
    var submissionID: String?
    var generatedAt: Date = Date()
}
