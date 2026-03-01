import Foundation

// MARK: - Generated Project Writer

/// Writes AI-generated files to disk with proper directory structure,
/// project configuration (XcodeGen project.yml or SPM Package.swift),
/// and app-spec.json metadata.
struct GeneratedProjectWriter: Sendable {

    // MARK: - Type Alias

    private typealias BuildTarget = StudioViewModel.BuildTarget

    // MARK: - Errors

    enum WriterError: Error, LocalizedError {
        case failedToCreateDirectory(path: String, underlying: Error)
        case failedToWriteFile(path: String, underlying: Error)
        case emptyFileList

        var errorDescription: String? {
            switch self {
            case .failedToCreateDirectory(let path, let underlying):
                return "Failed to create directory '\(path)': \(underlying.localizedDescription)"
            case .failedToWriteFile(let path, let underlying):
                return "Failed to write file '\(path)': \(underlying.localizedDescription)"
            case .emptyFileList:
                return "No files provided to write"
            }
        }
    }

    // MARK: - Write Generated Project

    /// Writes all generated files to the given project directory.
    /// Creates subdirectories as needed. Returns the list of paths written.
    @discardableResult
    static func writeProject(
        files: [GeneratedFileEntry],
        to projectDirectory: URL,
        appName: String,
        target: StudioViewModel.BuildTarget
    ) throws -> [URL] {
        guard !files.isEmpty else {
            throw WriterError.emptyFileList
        }

        let fileManager = FileManager.default
        var writtenURLs: [URL] = []

        // Create the root project directory if it doesn't exist
        try createDirectoryIfNeeded(at: projectDirectory, using: fileManager)

        // Write each generated file
        for file in files {
            let fileURL = projectDirectory.appendingPathComponent(file.relativePath)
            let parentDirectory = fileURL.deletingLastPathComponent()

            try createDirectoryIfNeeded(at: parentDirectory, using: fileManager)
            try writeFileAtomically(content: file.content, to: fileURL)
            writtenURLs.append(fileURL)
        }

        // Generate and write project configuration based on target
        switch target {
        case .ios:
            let projectYml = generateProjectYml(
                appName: appName,
                bundleID: sanitizeBundleID(appName),
                sourceFiles: files
            )
            let ymlURL = projectDirectory.appendingPathComponent("project.yml")
            try writeFileAtomically(content: projectYml, to: ymlURL)
            writtenURLs.append(ymlURL)

        case .macos:
            let packageSwift = generatePackageSwift(
                appName: appName,
                sourceFiles: files
            )
            let packageURL = projectDirectory.appendingPathComponent("Package.swift")
            try writeFileAtomically(content: packageSwift, to: packageURL)
            writtenURLs.append(packageURL)

        case .web:
            // Web projects don't need a build system config file;
            // the HTML/CSS/JS files are sufficient.
            break
        }

        // Generate and write app-spec.json
        let appSpec = generateAppSpec(
            appName: appName,
            target: target,
            files: files
        )
        let specURL = projectDirectory.appendingPathComponent("app-spec.json")
        try writeFileAtomically(content: appSpec, to: specURL)
        writtenURLs.append(specURL)

        return writtenURLs
    }

    // MARK: - Generate XcodeGen project.yml (iOS)

    /// Creates a project.yml for XcodeGen with proper iOS build settings.
    static func generateProjectYml(
        appName: String,
        bundleID: String,
        deploymentTarget: String = "17.0",
        sourceFiles: [GeneratedFileEntry]
    ) -> String {
        let safeBundleID = sanitizeBundleID(bundleID)

        return """
        name: \(appName)
        settings:
          base:
            INFOPLIST_KEY_UILaunchScreen_Generation: YES
            ENABLE_USER_SCRIPT_SANDBOXING: false
            SWIFT_VERSION: "5.9"
        targets:
          \(appName):
            type: application
            platform: iOS
            deploymentTarget: "\(deploymentTarget)"
            sources:
              - path: Sources/App
            settings:
              base:
                PRODUCT_BUNDLE_IDENTIFIER: com.imageelementstudio.generated.\(safeBundleID)
                TARGETED_DEVICE_FAMILY: "1,2"
                INFOPLIST_KEY_UIApplicationSceneManifest_Generation: YES
        """
    }

    // MARK: - Generate Package.swift (macOS)

    /// Creates a Package.swift for macOS SPM projects.
    static func generatePackageSwift(
        appName: String,
        sourceFiles: [GeneratedFileEntry]
    ) -> String {
        let safeName = sanitizeProductName(appName)

        return """
        // swift-tools-version: 5.9

        import PackageDescription

        let package = Package(
            name: "\(safeName)",
            platforms: [
                .macOS(.v14),
            ],
            products: [
                .executable(
                    name: "\(safeName)",
                    targets: ["\(safeName)"]
                ),
            ],
            targets: [
                .executableTarget(
                    name: "\(safeName)",
                    path: "Sources/App"
                ),
            ]
        )
        """
    }

    // MARK: - Generate app-spec.json

    /// Creates the app-spec.json metadata file describing the generated project.
    static func generateAppSpec(
        appName: String,
        target: StudioViewModel.BuildTarget,
        files: [GeneratedFileEntry]
    ) -> String {
        let fileEntries = files.map { file in
            """
                {
                    "name": "\(escapeJSON(file.name))",
                    "relativePath": "\(escapeJSON(file.relativePath))",
                    "role": "\(file.role.rawValue)"
                }
            """
        }

        let filesJSON = fileEntries.joined(separator: ",\n")

        return """
        {
            "appName": "\(escapeJSON(appName))",
            "target": "\(target.rawValue)",
            "generatedAt": "\(ISO8601DateFormatter().string(from: Date()))",
            "fileCount": \(files.count),
            "files": [
        \(filesJSON)
            ]
        }
        """
    }

    // MARK: - Timestamped Project Directory

    /// Creates a timestamped project directory under ~/Documents/ImageElementStudioBuilds and writes all files into it.
    /// Returns the root project directory URL.
    static func writeProjectToDisk(files: [GeneratedFileEntry], appName: String, target: StudioViewModel.BuildTarget) throws -> URL {
        let baseDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let formatter = DateFormatter(); formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let slug = appName.lowercased().replacingOccurrences(of: " ", with: "-").filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let projectDirectory = baseDirectory.appendingPathComponent("ImageElementStudioBuilds", isDirectory: true).appendingPathComponent(slug, isDirectory: true).appendingPathComponent("\(timestamp)-ai-\(target.rawValue)", isDirectory: true)
        try writeProject(files: files, to: projectDirectory, appName: appName, target: target)
        return projectDirectory
    }

    // MARK: - Private Helpers

    /// Creates a directory (and any intermediate directories) if it does not already exist.
    private static func createDirectoryIfNeeded(
        at url: URL,
        using fileManager: FileManager
    ) throws {
        if !fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.createDirectory(
                    at: url,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                throw WriterError.failedToCreateDirectory(
                    path: url.path,
                    underlying: error
                )
            }
        }
    }

    /// Writes a string to a file atomically with UTF-8 encoding.
    private static func writeFileAtomically(content: String, to url: URL) throws {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw WriterError.failedToWriteFile(
                path: url.path,
                underlying: error
            )
        }
    }

    /// Sanitizes an app name into a valid bundle ID component.
    /// Removes non-alphanumeric characters (except hyphens) and lowercases.
    private static func sanitizeBundleID(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let sanitized = name.unicodeScalars
            .filter { allowed.contains($0) }
            .map { Character($0) }
        let result = String(sanitized).lowercased()
        return result.isEmpty ? "app" : result
    }

    /// Sanitizes an app name into a valid Swift product/target name.
    /// Removes characters that are not alphanumeric or underscores.
    private static func sanitizeProductName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        let sanitized = name.unicodeScalars
            .filter { allowed.contains($0) }
            .map { Character($0) }
        let result = String(sanitized)
        return result.isEmpty ? "App" : result
    }

    /// Escapes a string for safe inclusion in a JSON value.
    private static func escapeJSON(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}
