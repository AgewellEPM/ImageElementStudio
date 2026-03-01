import Foundation
import Testing

@testable import ImageElementStudio

@Suite("BuildPipelineCoordinator Tests")
struct BuildPipelineCoordinatorTests {

    // MARK: - PipelineStep Tests

    @Test("PipelineStep has all expected cases")
    func pipelineStepCases() {
        let allSteps = BuildPipelineCoordinator.PipelineStep.allCases
        #expect(allSteps.count == 7)

        let names = allSteps.map(\.rawValue)
        #expect(names.contains("Verify Toolchain"))
        #expect(names.contains("Generate Xcode Project"))
        #expect(names.contains("Select Simulator"))
        #expect(names.contains("Build Project"))
        #expect(names.contains("Fix Build Errors"))
        #expect(names.contains("Install App"))
        #expect(names.contains("Launch App"))
    }

    @Test("PipelineStep identifiable by raw value")
    func pipelineStepIdentifiable() {
        let step = BuildPipelineCoordinator.PipelineStep.buildProject
        #expect(step.id == "Build Project")
    }

    // MARK: - PipelineStepStatus Tests

    @Test("PipelineStepStatus initial state is pending")
    func stepStatusInitialState() {
        let status = BuildPipelineCoordinator.PipelineStepStatus(
            step: .verifyToolchain,
            state: .pending,
            detail: nil
        )
        #expect(status.id == "Verify Toolchain")
        #expect(status.detail == nil)
    }

    @Test("StepState covers all expected cases")
    func stepStateCases() {
        let states: [BuildPipelineCoordinator.PipelineStepStatus.StepState] = [
            .pending, .active, .succeeded, .failed, .skipped,
        ]
        #expect(states.count == 5)
    }

    // MARK: - Initial State Tests

    @MainActor
    @Test("Coordinator initial state is not running")
    func coordinatorInitialState() {
        let coordinator = BuildPipelineCoordinator()
        #expect(!coordinator.isRunning)
        #expect(coordinator.steps.isEmpty)
        #expect(coordinator.currentStep == nil)
        #expect(coordinator.pipelineError == nil)
    }

    // MARK: - Cancel Pipeline Tests

    @MainActor
    @Test("Cancel pipeline sets error and stops running")
    func cancelPipeline() {
        let coordinator = BuildPipelineCoordinator()

        // Simulate some steps being active/pending
        coordinator.steps = BuildPipelineCoordinator.PipelineStep.allCases.map {
            BuildPipelineCoordinator.PipelineStepStatus(step: $0, state: .pending)
        }
        coordinator.steps[0].state = .succeeded
        coordinator.steps[1].state = .active

        coordinator.cancelPipeline()

        #expect(!coordinator.isRunning)
        #expect(coordinator.pipelineError == "Pipeline cancelled")

        // Active step should be failed
        #expect(coordinator.steps[1].state == .failed)
        #expect(coordinator.steps[1].detail == "Cancelled")

        // Pending steps should be skipped
        for step in coordinator.steps.dropFirst(2) {
            #expect(step.state == .skipped)
        }
    }

    @MainActor
    @Test("Cancel on already-not-running coordinator sets error")
    func cancelNotRunning() {
        let coordinator = BuildPipelineCoordinator()
        coordinator.cancelPipeline()

        #expect(!coordinator.isRunning)
        #expect(coordinator.pipelineError == "Pipeline cancelled")
    }

    // MARK: - Step Status Detail Tests

    @Test("PipelineStepStatus detail can be updated")
    func stepStatusDetail() {
        var status = BuildPipelineCoordinator.PipelineStepStatus(
            step: .buildProject,
            state: .active,
            detail: "Building..."
        )
        #expect(status.detail == "Building...")

        status.state = .succeeded
        status.detail = "12.5s"
        #expect(status.detail == "12.5s")
    }
}
