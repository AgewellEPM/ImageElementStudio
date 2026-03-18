import Foundation

/// Tracks actual API token usage, calculates costs, and provides pre-operation estimates.
@MainActor
final class TokenCostService: ObservableObject {

    // MARK: - Published State

    @Published var usageRecords: [TokenUsageRecord] = []
    @Published var lastEstimate: CostEstimate?

    // MARK: - Record Usage

    /// Records a completed API call with its token counts.
    func recordUsage(
        provider: String,
        model: String,
        operation: TokenOperationType,
        detail: String,
        inputTokens: Int,
        outputTokens: Int
    ) {
        let pricing = ProviderPricing.pricing(for: model)
        let costs = pricing.cost(inputTokens: inputTokens, outputTokens: outputTokens)

        let record = TokenUsageRecord(
            id: UUID(),
            timestamp: Date(),
            provider: provider,
            model: model,
            operation: operation,
            operationDetail: detail,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            inputCost: costs.input,
            outputCost: costs.output
        )

        usageRecords.append(record)

        // Cap records to prevent unbounded growth
        if usageRecords.count > Constants.TokenCost.maxSessionRecords {
            usageRecords.removeFirst(usageRecords.count - Constants.TokenCost.maxSessionRecords)
        }
    }

    // MARK: - Pre-Operation Estimates

    /// Estimates cost for generating an app (architecture + N files + validation fixes).
    func estimateAppGeneration(
        fileCount: Int,
        quality: AIGenerationQuality,
        hasScreenshot: Bool
    ) -> CostEstimate {
        let pricing = ProviderPricing.pricing(for: quality.modelID)
        var items: [CostEstimateItem] = []
        var totalInput = 0
        var totalOutput = 0
        var totalCalls = 0

        // 1. Architecture planning (1 call)
        let archInput = Constants.TokenCost.estimateArchitectureInputTokens
            + (hasScreenshot ? Constants.TokenCost.estimateScreenshotTokenOverhead : 0)
        let archOutput = Constants.TokenCost.estimateArchitectureOutputTokens
        let archCost = pricing.totalCost(inputTokens: archInput, outputTokens: archOutput)
        items.append(CostEstimateItem(
            label: "Architecture Plan",
            calls: 1,
            inputTokens: archInput,
            outputTokens: archOutput,
            cost: archCost
        ))
        totalInput += archInput
        totalOutput += archOutput
        totalCalls += 1

        // 2. File generation (fileCount calls)
        let effectiveFileCount = max(fileCount, 1)
        let perFileInput = Constants.TokenCost.estimateFileInputTokens
        let perFileOutput = Constants.TokenCost.estimateFileOutputTokens
        let fileInput = perFileInput * effectiveFileCount
        let fileOutput = perFileOutput * effectiveFileCount
        let fileCost = pricing.totalCost(inputTokens: fileInput, outputTokens: fileOutput)
        items.append(CostEstimateItem(
            label: "\(effectiveFileCount) source file\(effectiveFileCount == 1 ? "" : "s")",
            calls: effectiveFileCount,
            inputTokens: fileInput,
            outputTokens: fileOutput,
            cost: fileCost
        ))
        totalInput += fileInput
        totalOutput += fileOutput
        totalCalls += effectiveFileCount

        // 3. Validation fixes (estimated)
        let estimatedFixes = max(1, Int(Double(effectiveFileCount) * Constants.TokenCost.estimateFixProbability + 0.5))
        let fixInput = Constants.TokenCost.estimateFixInputTokens * estimatedFixes
        let fixOutput = Constants.TokenCost.estimateFixOutputTokens * estimatedFixes
        let fixCost = pricing.totalCost(inputTokens: fixInput, outputTokens: fixOutput)
        items.append(CostEstimateItem(
            label: "Validation fixes (~\(estimatedFixes))",
            calls: estimatedFixes,
            inputTokens: fixInput,
            outputTokens: fixOutput,
            cost: fixCost
        ))
        totalInput += fixInput
        totalOutput += fixOutput
        totalCalls += estimatedFixes

        let estimate = CostEstimate(
            operation: .architecturePlanning,
            estimatedCalls: totalCalls,
            estimatedInputTokens: totalInput,
            estimatedOutputTokens: totalOutput,
            estimatedCost: archCost + fileCost + fixCost,
            breakdown: items,
            model: quality.modelID,
            quality: quality
        )

        lastEstimate = estimate
        return estimate
    }

    /// Estimates cost for generating a wireframe.
    func estimateWireframe(quality: AIGenerationQuality) -> CostEstimate {
        let pricing = ProviderPricing.pricing(for: quality.modelID)
        let input = Constants.TokenCost.estimateWireframeInputTokens
        let output = Constants.TokenCost.estimateWireframeOutputTokens
        let cost = pricing.totalCost(inputTokens: input, outputTokens: output)

        let estimate = CostEstimate(
            operation: .wireframeGeneration,
            estimatedCalls: 1,
            estimatedInputTokens: input,
            estimatedOutputTokens: output,
            estimatedCost: cost,
            breakdown: [
                CostEstimateItem(
                    label: "Wireframe generation",
                    calls: 1,
                    inputTokens: input,
                    outputTokens: output,
                    cost: cost
                ),
            ],
            model: quality.modelID,
            quality: quality
        )

        lastEstimate = estimate
        return estimate
    }

    /// Estimates cost for fixing build errors.
    func estimateBuildFix(errorCount: Int, quality: AIGenerationQuality) -> CostEstimate {
        let pricing = ProviderPricing.pricing(for: quality.modelID)
        let calls = max(errorCount, 1)
        let input = Constants.TokenCost.estimateFixInputTokens * calls
        let output = Constants.TokenCost.estimateFixOutputTokens * calls
        let cost = pricing.totalCost(inputTokens: input, outputTokens: output)

        let estimate = CostEstimate(
            operation: .buildErrorFix,
            estimatedCalls: calls,
            estimatedInputTokens: input,
            estimatedOutputTokens: output,
            estimatedCost: cost,
            breakdown: [
                CostEstimateItem(
                    label: "\(calls) error fix\(calls == 1 ? "" : "es")",
                    calls: calls,
                    inputTokens: input,
                    outputTokens: output,
                    cost: cost
                ),
            ],
            model: quality.modelID,
            quality: quality
        )

        lastEstimate = estimate
        return estimate
    }

    // MARK: - Session Summary

    var sessionSummary: SessionCostSummary {
        guard !usageRecords.isEmpty else { return .empty }

        var totalCost = 0.0
        var totalInput = 0
        var totalOutput = 0
        var byOp: [TokenOperationType: (calls: Int, input: Int, output: Int, cost: Double)] = [:]
        var byModel: [String: Double] = [:]

        for record in usageRecords {
            totalCost += record.totalCost
            totalInput += record.inputTokens
            totalOutput += record.outputTokens

            var entry = byOp[record.operation] ?? (0, 0, 0, 0.0)
            entry.calls += 1
            entry.input += record.inputTokens
            entry.output += record.outputTokens
            entry.cost += record.totalCost
            byOp[record.operation] = entry

            byModel[record.model, default: 0] += record.totalCost
        }

        let opSummaries = byOp.mapValues { entry in
            OperationCostSummary(
                calls: entry.calls,
                inputTokens: entry.input,
                outputTokens: entry.output,
                cost: entry.cost
            )
        }

        return SessionCostSummary(
            totalCost: totalCost,
            totalInputTokens: totalInput,
            totalOutputTokens: totalOutput,
            totalCalls: usageRecords.count,
            byOperation: opSummaries,
            byModel: byModel
        )
    }

    /// One-line session cost summary for status displays.
    var sessionCostLine: String {
        let summary = sessionSummary
        guard summary.totalCalls > 0 else { return "No API calls yet" }

        let costStr = formatCost(summary.totalCost)
        let tokenStr = formatTokenCount(summary.totalTokens)
        return "Session: \(costStr) (\(summary.totalCalls) calls, \(tokenStr) tokens)"
    }

    /// Per-operation breakdown lines for the panel.
    var operationBreakdownLines: [(operation: TokenOperationType, line: String)] {
        let summary = sessionSummary
        return summary.byOperation
            .sorted { $0.value.cost > $1.value.cost }
            .map { op, stats in
                let costStr = formatCost(stats.cost)
                let callStr = stats.calls == 1 ? "1 call" : "\(stats.calls) calls"
                return (op, "\(op.displayName): \(costStr) (\(callStr))")
            }
    }

    /// Per-model cost breakdown.
    var modelBreakdownLines: [(model: String, cost: Double)] {
        sessionSummary.byModel
            .sorted { $0.value > $1.value }
            .map { ($0.key, $0.value) }
    }

    // MARK: - Reset

    func clearSession() {
        usageRecords.removeAll()
        lastEstimate = nil
    }

    // MARK: - Formatting Helpers

    func formatCost(_ cost: Double) -> String {
        if cost < 0.01 {
            return String(format: "$%.4f", cost)
        }
        return String(format: "$%.2f", cost)
    }

    func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        }
        if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }

    /// Short model display name.
    func shortModelName(_ modelID: String) -> String {
        if modelID.contains("sonnet") { return "Sonnet 4.5" }
        if modelID.contains("opus") { return "Opus 4.6" }
        if modelID.contains("gemini") { return "Gemini Flash" }
        if modelID.contains("gpt-4o") { return "GPT-4o" }
        if modelID.contains("deepseek") { return "DeepSeek V2" }
        if modelID.contains("qwen") { return "Qwen 2.5" }
        if modelID.contains("gemma") { return "Gemma 2" }
        if modelID.contains("codellama") { return "CodeLlama" }
        return modelID
    }

    /// Formats cost, showing "FREE" for $0.00 local models.
    func formatCostOrFree(_ cost: Double, isFree: Bool) -> String {
        if isFree { return "FREE" }
        return formatCost(cost)
    }
}
