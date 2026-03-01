import Foundation
import Testing

@testable import ImageElementStudio

@Suite("XcodeToolchainService Tests")
struct XcodeToolchainServiceTests {

    // MARK: - SDK Enum Tests

    @Test("SDK enum has correct raw values")
    func sdkRawValues() {
        #expect(XcodeToolchainService.SDK.iphonesimulator.rawValue == "iphonesimulator")
        #expect(XcodeToolchainService.SDK.macosx.rawValue == "macosx")
    }

    // MARK: - ToolchainStatus Tests

    @Test("Unknown toolchain status is not ready")
    func unknownStatusNotReady() {
        let status = XcodeToolchainService.ToolchainStatus.unknown
        #expect(!status.isReady)
        #expect(!status.isReadyForiOS)
        #expect(!status.xcodeInstalled)
        #expect(!status.commandLineToolsInstalled)
        #expect(!status.xcodgenInstalled)
    }

    @Test("Ready status requires Xcode and CLI tools")
    func readyStatusRequirements() {
        let status = XcodeToolchainService.ToolchainStatus(
            xcodeInstalled: true,
            xcodePath: "/Applications/Xcode.app/Contents/Developer",
            xcodeVersion: "Xcode 16.2",
            commandLineToolsInstalled: true,
            xcodgenInstalled: false,
            xcodgenPath: nil,
            availableSDKs: []
        )
        #expect(status.isReady)
        #expect(!status.isReadyForiOS)
    }

    @Test("iOS ready requires XcodeGen and simulator SDK")
    func iosReadyRequirements() {
        let status = XcodeToolchainService.ToolchainStatus(
            xcodeInstalled: true,
            xcodePath: "/Applications/Xcode.app/Contents/Developer",
            xcodeVersion: "Xcode 16.2",
            commandLineToolsInstalled: true,
            xcodgenInstalled: true,
            xcodgenPath: "/usr/local/bin/xcodegen",
            availableSDKs: ["iphonesimulator18.2", "macosx15.2"]
        )
        #expect(status.isReady)
        #expect(status.isReadyForiOS)
    }

    // MARK: - BuildOutputLine Classification Tests

    @Test("BuildOutputLine.Kind covers all expected cases")
    func buildOutputLineKinds() {
        // Just verify the enum values exist and are usable
        let kinds: [XcodeToolchainService.BuildOutputLine.Kind] = [
            .stdout, .stderr, .error, .warning, .note, .progress, .success,
        ]
        #expect(kinds.count == 7)
    }

    // MARK: - BuildDiagnostic Tests

    @Test("BuildDiagnostic kind raw values match expected patterns")
    func diagnosticKindRawValues() {
        #expect(XcodeToolchainService.BuildDiagnostic.Kind.error.rawValue == "error")
        #expect(XcodeToolchainService.BuildDiagnostic.Kind.warning.rawValue == "warning")
        #expect(XcodeToolchainService.BuildDiagnostic.Kind.note.rawValue == "note")
    }

    // MARK: - XcodeBuildResult Tests

    @Test("Build result with exit code 0 indicates success")
    func buildResultSuccess() {
        let result = XcodeToolchainService.XcodeBuildResult(
            exitCode: 0,
            errors: [],
            warnings: [],
            productPath: "/path/to/build/MyApp.app",
            duration: 12.5
        )
        #expect(result.succeeded)
        #expect(result.productPath != nil)
    }

    @Test("Build result with non-zero exit code indicates failure")
    func buildResultFailure() {
        let diagnostic = XcodeToolchainService.BuildDiagnostic(
            file: "ViewController.swift",
            line: 42,
            column: 10,
            message: "Cannot find 'foo' in scope",
            kind: .error
        )
        let result = XcodeToolchainService.XcodeBuildResult(
            exitCode: 65,
            errors: [diagnostic],
            warnings: [],
            productPath: nil,
            duration: 5.2
        )
        #expect(!result.succeeded)
        #expect(result.errors.count == 1)
        #expect(result.errors[0].message == "Cannot find 'foo' in scope")
        #expect(result.errors[0].file == "ViewController.swift")
        #expect(result.errors[0].line == 42)
    }
}
