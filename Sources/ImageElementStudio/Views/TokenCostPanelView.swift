import SwiftUI

struct TokenCostPanelView: View {
    @ObservedObject var viewModel: StudioViewModel

    private var costService: TokenCostService { viewModel.tokenCostService }

    var body: some View {
        GroupBox("Token Usage & Costs") {
            VStack(alignment: .leading, spacing: 8) {
                sessionSummarySection
                if !costService.usageRecords.isEmpty {
                    Divider()
                    operationBreakdownSection
                    Divider()
                    modelBreakdownSection
                }
                if let estimate = costService.lastEstimate {
                    Divider()
                    estimateSection(estimate)
                }
                Divider()
                actionButtons
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Session Summary

    @ViewBuilder
    private var sessionSummarySection: some View {
        let summary = costService.sessionSummary
        if summary.totalCalls > 0 {
            HStack {
                Text("Session Total")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(displayCost(summary.totalCost))
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(costColor(summary.totalCost))
            }
            Text("\(summary.totalCalls) API calls \u{00B7} \(costService.formatTokenCount(summary.totalInputTokens)) in / \(costService.formatTokenCount(summary.totalOutputTokens)) out")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Text("No API calls yet this session.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Operation Breakdown

    @ViewBuilder
    private var operationBreakdownSection: some View {
        Text("By Operation")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

        ForEach(costService.operationBreakdownLines, id: \.operation) { item in
            HStack {
                Text(item.operation.displayName)
                    .font(.caption2)
                Spacer()
                Text(item.line.components(separatedBy: ": ").dropFirst().joined(separator: ": "))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Model Breakdown

    @ViewBuilder
    private var modelBreakdownSection: some View {
        Text("By Model")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

        ForEach(costService.modelBreakdownLines, id: \.model) { item in
            HStack {
                Text(costService.shortModelName(item.model))
                    .font(.caption2)
                if isLocalModel(item.model) {
                    Text("LOCAL")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(.green, in: Capsule())
                }
                Spacer()
                Text(displayCost(item.cost))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(item.cost == 0 ? .green : .secondary)
            }
        }
    }

    // MARK: - Estimate Section

    @ViewBuilder
    private func estimateSection(_ estimate: CostEstimate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Estimate: \(estimate.operation.displayName)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                if estimate.quality.isFree {
                    Text("FREE")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.green, in: Capsule())
                }
            }

            HStack {
                Text("~\(estimate.estimatedCalls) calls")
                    .font(.caption2)
                Text("\u{00B7}")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("~\(costService.formatTokenCount(estimate.estimatedTotalTokens)) tokens")
                    .font(.caption2)
                Spacer()
                if estimate.quality.isFree {
                    Text("$0.00 (Free)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.green)
                } else {
                    Text("~\(costService.formatCost(estimate.estimatedCost))")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(costColor(estimate.estimatedCost))
                }
            }

            ForEach(Array(estimate.breakdown.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 4) {
                    Text("\u{251C}")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                    Text(item.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(estimate.quality.isFree ? "Free" : costService.formatCost(item.cost))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(estimate.quality.isFree ? .green : .secondary)
                }
            }

            HStack(spacing: 4) {
                Text("Using \(costService.shortModelName(estimate.model))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if estimate.quality.isFree {
                    Text("(local, free)")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button("Estimate Generation") {
                estimateCurrentGeneration()
            }
            .controlSize(.small)

            if !costService.usageRecords.isEmpty {
                Button("Clear Session") {
                    costService.clearSession()
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: - Helpers

    private func costColor(_ cost: Double) -> Color {
        if cost == 0 { return .green }
        if cost < 0.05 { return .green }
        if cost < 0.50 { return .orange }
        return .red
    }

    /// Displays cost, showing "FREE" for $0.00.
    private func displayCost(_ cost: Double) -> String {
        if cost == 0 { return "FREE" }
        return costService.formatCost(cost)
    }

    /// Checks if a model ID is a local Ollama model.
    private func isLocalModel(_ modelID: String) -> Bool {
        let localPrefixes = ["deepseek", "qwen", "gemma", "codellama", "llama", "mistral"]
        return localPrefixes.contains { modelID.lowercased().contains($0) }
    }

    private func estimateCurrentGeneration() {
        let artboard = viewModel.activeArtboard ?? viewModel.artboards.first
        let elementCount = artboard?.elements.count ?? 0
        // Rough estimate: 1 architecture file + 1 file per 3-5 elements, minimum 3 files
        let estimatedFiles = max(3, min(12, 2 + elementCount / 4))

        let qualityRaw = UserDefaults.standard.string(forKey: "generationQuality") ?? "fast"
        let quality = AIGenerationQuality(rawValue: qualityRaw) ?? .fast

        _ = costService.estimateAppGeneration(
            fileCount: estimatedFiles,
            quality: quality,
            hasScreenshot: viewModel.selectedImage != nil
        )
    }
}

// MARK: - Recent Records Subview

struct TokenCostRecentRecordsView: View {
    let records: [TokenUsageRecord]
    let costService: TokenCostService

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Recent Calls")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(records.suffix(8).reversed()) { record in
                HStack {
                    Text(record.operationDetail)
                        .font(.caption2)
                        .lineLimit(1)
                    if record.totalCost == 0 {
                        Text("FREE")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.green)
                    }
                    Spacer()
                    Text("\(costService.formatTokenCount(record.totalTokens))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(record.totalCost == 0 ? "$0.00" : costService.formatCost(record.totalCost))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(record.totalCost == 0 ? .green : .secondary)
                }
            }
        }
    }
}
