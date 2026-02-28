import SwiftUI

struct BuildOutputView: View {
    @ObservedObject var coordinator: BuildPipelineCoordinator

    var body: some View {
        VStack(spacing: 0) {
            pipelineStepsTracker
            Divider()
            buildLogSection
            Divider()
            controlsBar
        }
        .background(Color(nsColor: .textBackgroundColor))
        .animation(.default, value: coordinator.steps.map(\.state))
    }

    // MARK: - Section 1: Pipeline Steps Tracker

    private var pipelineStepsTracker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(coordinator.steps) { stepStatus in
                    stepPill(for: stepStatus)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }

    private func stepPill(for stepStatus: BuildPipelineCoordinator.PipelineStepStatus) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                stepIcon(for: stepStatus.state)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(stepColor(for: stepStatus.state))

                Text(stepStatus.step.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(stepStatus.state == .skipped ? .secondary : .primary)
                    .strikethrough(stepStatus.state == .skipped)
                    .lineLimit(1)
            }

            if let detail = stepStatus.detail {
                Text(detail)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(stepBackgroundColor(for: stepStatus.state))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(stepColor(for: stepStatus.state).opacity(0.3), lineWidth: 1)
        )
        .opacity(stepStatus.state == .skipped ? 0.6 : 1.0)
        .scaleEffect(stepStatus.state == .active ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                    value: stepStatus.state == .active)
    }

    private func stepIcon(for state: BuildPipelineCoordinator.PipelineStepStatus.StepState) -> Image {
        switch state {
        case .pending:
            return Image(systemName: "clock")
        case .active:
            return Image(systemName: "arrow.clockwise")
        case .succeeded:
            return Image(systemName: "checkmark.circle.fill")
        case .failed:
            return Image(systemName: "xmark.circle.fill")
        case .skipped:
            return Image(systemName: "minus.circle")
        }
    }

    private func stepColor(for state: BuildPipelineCoordinator.PipelineStepStatus.StepState) -> Color {
        switch state {
        case .pending:
            return .gray
        case .active:
            return .blue
        case .succeeded:
            return .green
        case .failed:
            return .red
        case .skipped:
            return .gray
        }
    }

    private func stepBackgroundColor(for state: BuildPipelineCoordinator.PipelineStepStatus.StepState) -> Color {
        switch state {
        case .pending:
            return Color.gray.opacity(0.08)
        case .active:
            return Color.blue.opacity(0.1)
        case .succeeded:
            return Color.green.opacity(0.08)
        case .failed:
            return Color.red.opacity(0.1)
        case .skipped:
            return Color.gray.opacity(0.05)
        }
    }

    // MARK: - Section 2: Build Log

    private var buildLogSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(coordinator.toolchainService.buildOutput) { line in
                        buildOutputLineView(line)
                            .id(line.id)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .onChange(of: coordinator.toolchainService.buildOutput.count) { _, _ in
                if let lastLine = coordinator.toolchainService.buildOutput.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(lastLine.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .center) {
            if coordinator.toolchainService.buildOutput.isEmpty && !coordinator.isRunning {
                emptyLogPlaceholder
            }
        }
    }

    private func buildOutputLineView(_ line: XcodeToolchainService.BuildOutputLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(lineTimestamp(line.timestamp))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.quaternary)
                .frame(width: 58, alignment: .trailing)

            Text(line.text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(lineColor(for: line.kind))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }

    private func lineColor(for kind: XcodeToolchainService.BuildOutputLine.Kind) -> Color {
        switch kind {
        case .error:
            return .red
        case .warning:
            return .orange
        case .note:
            return .blue
        case .progress:
            return .secondary
        case .success:
            return .green
        case .stdout:
            return .primary
        case .stderr:
            return .secondary
        }
    }

    private func lineTimestamp(_ date: Date) -> String {
        let formatter = Self.timestampFormatter
        return formatter.string(from: date)
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var emptyLogPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "hammer")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.quaternary)
            Text("No build output yet")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Text("Start a build to see live output here.")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
    }

    // MARK: - Section 3: Controls

    private var controlsBar: some View {
        VStack(spacing: 0) {
            if let error = coordinator.pipelineError {
                errorBanner(error)
            }

            HStack(spacing: 12) {
                if coordinator.isRunning {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)

                    Text(currentStepLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Button(role: .destructive) {
                        coordinator.cancelPipeline()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
                } else {
                    buildSummaryLabel

                    Spacer()

                    Button {
                        // Rebuild action is handled by the parent view
                        // by observing coordinator state and calling runFullPipeline/buildOnly
                    } label: {
                        Label("Rebuild", systemImage: "hammer.fill")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(coordinator.isRunning)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)

            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
                .truncationMode(.tail)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.08))
    }

    private var currentStepLabel: String {
        if let step = coordinator.currentStep {
            return step.rawValue + "..."
        }
        return "Running..."
    }

    private var buildSummaryLabel: some View {
        Group {
            if let result = coordinator.toolchainService.lastBuildResult {
                HStack(spacing: 4) {
                    Image(systemName: result.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.succeeded ? .green : .red)
                        .font(.caption)

                    Text(result.succeeded ? "Build Succeeded" : "Build Failed")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(result.succeeded ? .green : .red)

                    if !result.errors.isEmpty {
                        Text("(\(result.errors.count) error\(result.errors.count == 1 ? "" : "s"))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !result.warnings.isEmpty {
                        Text("\(result.warnings.count) warning\(result.warnings.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            } else if coordinator.steps.isEmpty {
                Text("Ready to build")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Pipeline complete")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
