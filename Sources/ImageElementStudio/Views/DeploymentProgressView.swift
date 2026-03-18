import SwiftUI

// MARK: - DeploymentProgressView

/// Compact build progress view used within the deployment wizard's Build & Archive step.
/// Shows a progress bar, status text, scrolling build log, and error display.
struct DeploymentProgressView: View {
    @ObservedObject var deploymentService: DeploymentService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Progress bar
            ProgressView(value: deploymentService.deploymentProgress)
                .tint(progressTint)

            // Status line
            HStack(spacing: 6) {
                if deploymentService.isDeploying {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(deploymentService.deploymentStatusLine)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(percentageText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            // Build output log
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(deploymentService.buildOutput.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(lineColor(for: line))
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(
                    Color(hex: "#0D0F12", fallback: .black).opacity(0.8),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .frame(maxHeight: 200)
                .onChange(of: deploymentService.buildOutput.count) { _, _ in
                    if let last = deploymentService.buildOutput.indices.last {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last, anchor: .bottom)
                        }
                    }
                }
            }

            // Error display
            if let error = deploymentService.deploymentError {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.red.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                )
            }

            // Success display
            if let result = deploymentService.deploymentResult, result.succeeded {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Build completed successfully")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.green.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
    }

    // MARK: - Computed Properties

    /// Progress tint: green if complete, red if error, blue while in progress.
    private var progressTint: Color {
        if deploymentService.deploymentError != nil {
            return .red
        } else if deploymentService.deploymentResult?.succeeded == true {
            return .green
        }
        return .blue
    }

    /// Percentage text from deploymentProgress.
    private var percentageText: String {
        let pct = Int(deploymentService.deploymentProgress * 100)
        return "\(pct)%"
    }

    /// Color for a build output line: red for errors, yellow for warnings, default otherwise.
    private func lineColor(for line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("error:") {
            return .red
        } else if lower.contains("warning:") {
            return .yellow
        }
        return .white.opacity(0.85)
    }
}
