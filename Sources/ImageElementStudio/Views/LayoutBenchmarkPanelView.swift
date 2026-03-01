import SwiftUI

struct LayoutBenchmarkPanelView: View {
    @ObservedObject var viewModel: StudioViewModel

    var body: some View {
        GroupBox("Layout Tools") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Show Grid", isOn: $viewModel.showLayoutGrid)
                    .font(.caption2)
                Toggle("Snap To Grid", isOn: $viewModel.snapToGrid)
                    .font(.caption2)
                Toggle("Show Alignment Guides", isOn: $viewModel.showAlignmentGuides)
                    .font(.caption2)

                Stepper("Grid Size \(Int(viewModel.gridSize))", value: $viewModel.gridSize, in: 4...48, step: 2)
                    .font(.caption2)
                Stepper("Distribution Gap \(Int(viewModel.distributionGap))", value: $viewModel.distributionGap, in: 0...72, step: 2)
                    .font(.caption2)

                HStack(spacing: 6) {
                    Button("Distribute H") { viewModel.distributeSelectedElementsHorizontally() }
                        .disabled(!viewModel.canDistributeSelection)
                    Button("Distribute V") { viewModel.distributeSelectedElementsVertically() }
                        .disabled(!viewModel.canDistributeSelection)
                }
                .controlSize(.small)

                Divider()
                Text("Benchmark")
                    .font(.caption.weight(.semibold))
                Text(viewModel.benchmarkStatusLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(viewModel.benchmarkTrendStatusLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(viewModel.benchmarkTrendDirectionLine)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Run Pro Editing Benchmark") {
                        viewModel.runProEditingBenchmark()
                    }
                    Button("Auto-Fix & Re-run") {
                        viewModel.autoFixFailingBenchmarkStep()
                    }
                    .disabled(viewModel.latestBenchmarkReport == nil || (viewModel.latestBenchmarkReport?.passed ?? false))
                }
                .controlSize(.small)

                if !viewModel.benchmarkTrendPoints.isEmpty {
                    BenchmarkPassRateChart(points: viewModel.benchmarkTrendPoints)
                        .frame(height: 48)
                }

                if !viewModel.benchmarkHistoryPreview.isEmpty {
                    ForEach(Array(viewModel.benchmarkHistoryPreview.prefix(3).enumerated()), id: \.offset) { item in
                        let median = item.element.medianStepLatencyMilliseconds.map { "\(Int($0.rounded()))ms" } ?? "n/a"
                        Text(
                            "\(item.element.generatedAt.formatted(date: .omitted, time: .shortened)) \u{00B7} " +
                                "\(item.element.passed ? "pass" : "fail") \u{00B7} " +
                                "\(Int((item.element.stepPassRate * 100).rounded()))% \u{00B7} \(median)"
                        )
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
