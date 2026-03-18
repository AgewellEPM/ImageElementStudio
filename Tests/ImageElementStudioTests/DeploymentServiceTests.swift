import XCTest
@testable import ImageElementStudio

@MainActor
final class DeploymentServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeService() -> DeploymentService {
        let toolchain = XcodeToolchainService()
        let signing = SigningService()
        return DeploymentService(toolchainService: toolchain, signingService: signing)
    }

    // MARK: - Initial State

    func testInitialStepIsChooseTarget() {
        let service = makeService()
        XCTAssertEqual(service.currentStep, .chooseTarget)
    }

    func testInitialIsDeployingIsFalse() {
        let service = makeService()
        XCTAssertFalse(service.isDeploying)
    }

    func testInitialDeploymentResultIsNil() {
        let service = makeService()
        XCTAssertNil(service.deploymentResult)
    }

    func testInitialBuildOutputIsEmpty() {
        let service = makeService()
        XCTAssertTrue(service.buildOutput.isEmpty)
    }

    // MARK: - Step Navigation

    func testCanAdvanceFromChooseTarget() {
        let service = makeService()
        XCTAssertTrue(service.canAdvance)
    }

    func testCannotGoBackFromFirstStep() {
        let service = makeService()
        XCTAssertFalse(service.canGoBack)
    }

    func testAdvanceStepMovesToConfigureSigning() {
        let service = makeService()
        service.advanceStep()
        XCTAssertEqual(service.currentStep, .configureSigning)
    }

    func testGoBackFromConfigureSigningReturnsToChooseTarget() {
        let service = makeService()
        service.advanceStep()
        XCTAssertEqual(service.currentStep, .configureSigning)
        service.goBack()
        XCTAssertEqual(service.currentStep, .chooseTarget)
    }

    func testCannotAdvanceFromConfigureSigningWithoutValidConfig() {
        let service = makeService()
        service.advanceStep() // -> configureSigning
        // Force empty signing config regardless of any Keychain state
        service.signingConfig = SigningConfiguration()
        XCTAssertFalse(service.canAdvance)
    }

    func testCanAdvanceFromConfigureSigningWithValidConfig() {
        let service = makeService()
        service.advanceStep() // -> configureSigning
        service.signingConfig = SigningConfiguration(
            teamID: "ABCDE12345",
            signingIdentity: "Apple Development: Test",
            codeSignStyle: "Manual"
        )
        XCTAssertTrue(service.canAdvance)
    }

    func testCannotAdvanceFromAppMetadataWithoutValidMetadata() {
        let service = makeService()
        service.advanceStep() // -> configureSigning
        service.signingConfig = SigningConfiguration(
            teamID: "ABCDE12345",
            signingIdentity: "Apple Development: Test",
            codeSignStyle: "Manual"
        )
        service.advanceStep() // -> appMetadata
        // Default metadata has empty display name → invalid
        XCTAssertFalse(service.canAdvance)
    }

    func testCanAdvanceFromAppMetadataWithValidMetadata() {
        let service = makeService()
        service.advanceStep() // -> configureSigning
        service.signingConfig = SigningConfiguration(
            teamID: "ABCDE12345",
            signingIdentity: "Apple Development: Test",
            codeSignStyle: "Manual"
        )
        service.advanceStep() // -> appMetadata
        service.appMetadata = AppDeploymentMetadata(
            displayName: "TestApp",
            bundleID: "com.test.app",
            version: "1.0.0",
            buildNumber: "1"
        )
        XCTAssertTrue(service.canAdvance)
    }

    func testFullStepNavigationForward() {
        let service = makeService()

        // Step 1: chooseTarget → configureSigning
        service.advanceStep()
        XCTAssertEqual(service.currentStep, .configureSigning)

        // Step 2: configureSigning → appMetadata
        service.signingConfig = SigningConfiguration(
            teamID: "ABCDE12345",
            signingIdentity: "Apple Development: Test",
            codeSignStyle: "Manual"
        )
        service.advanceStep()
        XCTAssertEqual(service.currentStep, .appMetadata)

        // Step 3: appMetadata → buildArchive
        service.appMetadata = AppDeploymentMetadata(
            displayName: "TestApp",
            bundleID: "com.test.app",
            version: "1.0.0",
            buildNumber: "1"
        )
        service.advanceStep()
        XCTAssertEqual(service.currentStep, .buildArchive)
    }

    // MARK: - Reset

    func testResetReturnsToInitialState() {
        let service = makeService()
        service.advanceStep()
        service.isDeploying = true
        service.deploymentProgress = 0.5
        service.deploymentStatusLine = "Testing..."
        service.buildOutput = ["line1"]

        service.reset()

        XCTAssertEqual(service.currentStep, .chooseTarget)
        XCTAssertFalse(service.isDeploying)
        XCTAssertEqual(service.deploymentProgress, 0)
        XCTAssertTrue(service.deploymentStatusLine.isEmpty)
        XCTAssertNil(service.deploymentResult)
        XCTAssertTrue(service.buildOutput.isEmpty)
    }

    // MARK: - Populate from Project

    func testPopulateFromProjectSetsMetadata() {
        let service = makeService()
        service.populateFromProject(name: "My App", bundleIDBase: "com.example.myapp", target: "ios")
        XCTAssertEqual(service.appMetadata.displayName, "My App")
        XCTAssertEqual(service.appMetadata.bundleID, "com.example.myapp")
    }

    func testPopulateFromProjectGeneratesBundleIDWhenEmpty() {
        let service = makeService()
        service.populateFromProject(name: "Cool App", bundleIDBase: "", target: "ios")
        XCTAssertEqual(service.appMetadata.displayName, "Cool App")
        XCTAssertTrue(service.appMetadata.bundleID.contains("cool-app"))
    }

    // MARK: - Target Selection

    func testSelectedTargetDefaultsToDirectNotarized() {
        let service = makeService()
        XCTAssertEqual(service.selectedTarget, .directNotarized)
    }

    func testAllDeploymentTargetsHaveNonEmptyDisplayName() {
        for target in DeploymentTarget.allCases {
            XCTAssertFalse(target.displayName.isEmpty, "Target \(target.rawValue) has empty displayName")
        }
    }

    func testAllDeploymentTargetsHaveNonEmptyExportMethod() {
        for target in DeploymentTarget.allCases {
            XCTAssertFalse(target.exportMethod.isEmpty, "Target \(target.rawValue) has empty exportMethod")
        }
    }

    // MARK: - Deployment Step Ordering

    func testDeploymentStepsAreInExpectedOrder() {
        let expected: [DeploymentStep] = [
            .chooseTarget,
            .configureSigning,
            .appMetadata,
            .buildArchive,
            .submitExport
        ]
        XCTAssertEqual(DeploymentStep.allCases, expected)
    }

    func testIsTerminalStepOnlyForSubmitExport() {
        let service = makeService()
        XCTAssertFalse(service.isTerminalStep)
        // Navigate to last step
        service.currentStep = .submitExport
        XCTAssertTrue(service.isTerminalStep)
    }
}
