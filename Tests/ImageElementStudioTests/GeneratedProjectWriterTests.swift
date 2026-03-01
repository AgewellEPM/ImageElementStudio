import XCTest
@testable import ImageElementStudio

final class GeneratedProjectWriterTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GeneratedProjectWriterTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        super.tearDown()
    }

    // MARK: - writeProject: Directory Structure

    func testWriteProjectCreatesDirectoryStructure() throws {
        let files = [
            GeneratedFileEntry(
                name: "App.swift",
                relativePath: "Sources/App/App.swift",
                content: "import SwiftUI\n@main struct MyApp: App { var body: some Scene { WindowGroup { ContentView() } } }",
                role: .appEntry
            ),
            GeneratedFileEntry(
                name: "ContentView.swift",
                relativePath: "Sources/App/ContentView.swift",
                content: "import SwiftUI\nstruct ContentView: View { var body: some View { Text(\"Hello\") } }",
                role: .rootView
            ),
        ]

        let writtenURLs = try GeneratedProjectWriter.writeProject(
            files: files,
            to: tempDirectory,
            appName: "TestApp",
            target: .macos
        )

        // Verify the root directory was created
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)

        // Verify Sources/App subdirectory was created
        let sourcesApp = tempDirectory.appendingPathComponent("Sources/App")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourcesApp.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)

        // Verify files were written (2 source + Package.swift + app-spec.json)
        XCTAssertTrue(writtenURLs.count >= 4, "Expected at least 4 URLs (2 source files + Package.swift + app-spec.json), got \(writtenURLs.count)")
    }

    // MARK: - writeProject: File Contents

    func testWriteProjectWritesCorrectFileContents() throws {
        let swiftContent = "import SwiftUI\nstruct ContentView: View { var body: some View { Text(\"Works!\") } }"
        let files = [
            GeneratedFileEntry(
                name: "ContentView.swift",
                relativePath: "Sources/App/ContentView.swift",
                content: swiftContent,
                role: .rootView
            ),
        ]

        try GeneratedProjectWriter.writeProject(
            files: files,
            to: tempDirectory,
            appName: "FileContentTest",
            target: .macos
        )

        let fileURL = tempDirectory.appendingPathComponent("Sources/App/ContentView.swift")
        let readContent = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(readContent, swiftContent)
    }

    // MARK: - writeProject: Empty File List Throws

    func testWriteProjectThrowsForEmptyFileList() {
        XCTAssertThrowsError(try GeneratedProjectWriter.writeProject(
            files: [],
            to: tempDirectory,
            appName: "EmptyApp",
            target: .ios
        )) { error in
            XCTAssertTrue(error is GeneratedProjectWriter.WriterError)
            if let writerError = error as? GeneratedProjectWriter.WriterError {
                switch writerError {
                case .emptyFileList:
                    break // expected
                default:
                    XCTFail("Expected emptyFileList error, got \(writerError)")
                }
            }
        }
    }

    // MARK: - writeProject: iOS generates project.yml

    func testWriteProjectForIOSGeneratesProjectYml() throws {
        let files = [
            GeneratedFileEntry(
                name: "App.swift",
                relativePath: "Sources/App/App.swift",
                content: "import SwiftUI\n@main struct MyApp: App { var body: some Scene { WindowGroup { Text(\"Hi\") } } }",
                role: .appEntry
            ),
        ]

        try GeneratedProjectWriter.writeProject(
            files: files,
            to: tempDirectory,
            appName: "iOSApp",
            target: .ios
        )

        let ymlURL = tempDirectory.appendingPathComponent("project.yml")
        XCTAssertTrue(FileManager.default.fileExists(atPath: ymlURL.path), "iOS target should produce project.yml")

        let ymlContent = try String(contentsOf: ymlURL, encoding: .utf8)
        XCTAssertTrue(ymlContent.contains("iOSApp"), "project.yml should contain app name")
        XCTAssertTrue(ymlContent.contains("platform: iOS"), "project.yml should specify iOS platform")
    }

    // MARK: - writeProject: macOS generates Package.swift

    func testWriteProjectForMacOSGeneratesPackageSwift() throws {
        let files = [
            GeneratedFileEntry(
                name: "App.swift",
                relativePath: "Sources/App/App.swift",
                content: "import SwiftUI\n@main struct MyApp: App { var body: some Scene { WindowGroup { Text(\"Hi\") } } }",
                role: .appEntry
            ),
        ]

        try GeneratedProjectWriter.writeProject(
            files: files,
            to: tempDirectory,
            appName: "MacApp",
            target: .macos
        )

        let packageURL = tempDirectory.appendingPathComponent("Package.swift")
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.path), "macOS target should produce Package.swift")

        let packageContent = try String(contentsOf: packageURL, encoding: .utf8)
        XCTAssertTrue(packageContent.contains("swift-tools-version"), "Package.swift should have tools version")
        XCTAssertTrue(packageContent.contains("MacApp"), "Package.swift should contain app name")
        XCTAssertTrue(packageContent.contains(".macOS(.v14)"), "Package.swift should target macOS 14")
    }

    // MARK: - writeProject: Web has no build config

    func testWriteProjectForWebDoesNotGenerateBuildConfig() throws {
        let files = [
            GeneratedFileEntry(
                name: "index.html",
                relativePath: "src/index.html",
                content: "<!DOCTYPE html><html><head><title>Test</title></head><body></body></html>",
                role: .webMarkup
            ),
        ]

        let writtenURLs = try GeneratedProjectWriter.writeProject(
            files: files,
            to: tempDirectory,
            appName: "WebApp",
            target: .web
        )

        // Web should not produce project.yml or Package.swift
        let ymlURL = tempDirectory.appendingPathComponent("project.yml")
        let packageURL = tempDirectory.appendingPathComponent("Package.swift")
        XCTAssertFalse(FileManager.default.fileExists(atPath: ymlURL.path), "Web target should not produce project.yml")
        XCTAssertFalse(FileManager.default.fileExists(atPath: packageURL.path), "Web target should not produce Package.swift")

        // But should produce app-spec.json
        let specURL = tempDirectory.appendingPathComponent("app-spec.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: specURL.path), "Web target should produce app-spec.json")

        // writtenURLs: 1 source + app-spec.json = 2
        XCTAssertEqual(writtenURLs.count, 2)
    }

    // MARK: - writeProject: app-spec.json content

    func testWriteProjectGeneratesAppSpecJSON() throws {
        let files = [
            GeneratedFileEntry(
                name: "ContentView.swift",
                relativePath: "Sources/App/ContentView.swift",
                content: "import SwiftUI\nstruct ContentView: View { var body: some View { EmptyView() } }",
                role: .rootView
            ),
            GeneratedFileEntry(
                name: "Theme.swift",
                relativePath: "Sources/App/Theme.swift",
                content: "import SwiftUI\nenum Theme { static let primaryColor = Color.blue }",
                role: .theme
            ),
        ]

        try GeneratedProjectWriter.writeProject(
            files: files,
            to: tempDirectory,
            appName: "SpecTest",
            target: .macos
        )

        let specURL = tempDirectory.appendingPathComponent("app-spec.json")
        let specContent = try String(contentsOf: specURL, encoding: .utf8)
        XCTAssertTrue(specContent.contains("\"appName\": \"SpecTest\""))
        XCTAssertTrue(specContent.contains("\"fileCount\": 2"))
        XCTAssertTrue(specContent.contains("\"target\": \"macos\""))
        XCTAssertTrue(specContent.contains("ContentView.swift"))
        XCTAssertTrue(specContent.contains("Theme.swift"))
    }

    // MARK: - generateProjectYml

    func testGenerateProjectYmlContainsBundleID() {
        let yml = GeneratedProjectWriter.generateProjectYml(
            appName: "My App",
            bundleID: "My App",
            sourceFiles: []
        )
        // Bundle ID should be sanitized to lowercase with no spaces
        XCTAssertTrue(yml.contains("com.imageelementstudio.generated.myapp"))
    }

    // MARK: - generatePackageSwift

    func testGeneratePackageSwiftSanitizesName() {
        let pkg = GeneratedProjectWriter.generatePackageSwift(
            appName: "My Cool App!",
            sourceFiles: []
        )
        // Product name should have special characters removed
        XCTAssertTrue(pkg.contains("MyCoolApp"), "Package name should strip non-alphanumeric chars")
        XCTAssertFalse(pkg.contains("!"), "Package name should not contain special chars")
    }

    // MARK: - generateAppSpec

    func testGenerateAppSpecContainsExpectedFields() {
        let files = [
            GeneratedFileEntry(name: "index.html", relativePath: "src/index.html", content: "<html></html>", role: .webMarkup),
        ]
        let spec = GeneratedProjectWriter.generateAppSpec(
            appName: "WebSpecApp",
            target: .web,
            files: files
        )
        XCTAssertTrue(spec.contains("\"appName\": \"WebSpecApp\""))
        XCTAssertTrue(spec.contains("\"target\": \"web\""))
        XCTAssertTrue(spec.contains("\"fileCount\": 1"))
        XCTAssertTrue(spec.contains("generatedAt"))
        XCTAssertTrue(spec.contains("index.html"))
    }

    // MARK: - writeProjectToDisk

    func testWriteProjectToDiskReturnsValidURL() throws {
        let files = [
            GeneratedFileEntry(
                name: "ContentView.swift",
                relativePath: "Sources/App/ContentView.swift",
                content: "import SwiftUI\nstruct ContentView: View { var body: some View { Text(\"Disk test\") } }",
                role: .rootView
            ),
        ]

        let projectURL = try GeneratedProjectWriter.writeProjectToDisk(
            files: files,
            appName: "DiskWriteTest",
            target: .macos
        )

        // Verify it returned a valid directory URL
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: projectURL.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)

        // Verify path contains expected components
        XCTAssertTrue(projectURL.path.contains("ImageElementStudioBuilds"))
        XCTAssertTrue(projectURL.path.contains("diskwritetest"))
        XCTAssertTrue(projectURL.path.contains("ai-macos"))

        // Verify the content file exists
        let contentViewURL = projectURL.appendingPathComponent("Sources/App/ContentView.swift")
        XCTAssertTrue(FileManager.default.fileExists(atPath: contentViewURL.path))

        // Clean up
        let buildsDir = projectURL.deletingLastPathComponent().deletingLastPathComponent()
        try? FileManager.default.removeItem(at: buildsDir)
    }
}
