import SwiftUI

struct BuildQualityPanelView: View {
    @ObservedObject var viewModel: StudioViewModel

    var body: some View {
        GroupBox("Build Quality") {
            VStack(alignment: .leading, spacing: 8) {
                let qualitySummary = viewModel.currentQualityGateSummary
                Text(viewModel.qualityGateScoreLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(qualityGateColor(for: qualitySummary.status))

                if let report = viewModel.latestBuildQualityReport {
                    Text("Pass Rate: \(Int((report.passRate * 100).rounded()))%")
                        .font(.caption.weight(.semibold))
                    Text("Hash: \(report.deterministicHash.prefix(12))...")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    if let benchmark = viewModel.latestBenchmarkReport {
                        Text("Benchmark: \(benchmark.passed ? "pass" : "fail")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(viewModel.reviewGateStatusLine)
                        .font(.caption2)
                        .foregroundStyle(viewModel.canExportBuildArtifacts ? .green : .orange)
                } else {
                    Text("Run build setup to generate deterministic quality metrics.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let fullStack = viewModel.latestFullStackBuildSummary {
                    Text("Full Stack: \(Int(fullStack.aggregateScore.rounded())) \u{00B7} \(fullStack.allTargetsPassed ? "pass" : "fail")")
                        .font(.caption.weight(.semibold))
                    ForEach(viewModel.fullStackTargetStatusLines, id: \.self) { line in
                        Text(line)
                            .font(.caption2.monospaced())
                            .foregroundStyle(line.hasPrefix("PASS") ? Color.secondary : Color.orange)
                    }
                }

                if let enterprise = viewModel.latestEnterpriseReadinessReport {
                    Text("Enterprise: \(enterprise.status.rawValue.capitalized) \u{00B7} \(Int(enterprise.score.rounded()))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            enterprise.status == .pass ? .green : (enterprise.status == .warning ? .orange : .red)
                        )
                    ForEach(viewModel.enterpriseReadinessCheckLines, id: \.self) { line in
                        Text(line)
                            .font(.caption2.monospaced())
                            .foregroundStyle(line.hasPrefix("PASS") ? Color.secondary : Color.orange)
                    }
                }

                ForEach(viewModel.qualityGateBreakdownLines, id: \.self) { line in
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !viewModel.qualityGateIssuePreview.isEmpty {
                    Divider()
                    ForEach(viewModel.qualityGateIssuePreview, id: \.self) { issue in
                        Text("\u{2022} \(issue)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func qualityGateColor(for status: QualityGateStatus) -> Color {
        switch status {
        case .pass:
            return .green
        case .warning:
            return .orange
        case .fail:
            return .red
        }
    }
}
