import Foundation

// MARK: - Operation Type

/// Every distinct token-consuming operation in the pipeline.
enum TokenOperationType: String, Codable, CaseIterable, Sendable {
    case architecturePlanning
    case fileGeneration
    case codeValidationFix
    case wireframeGeneration
    case semanticEnrichment
    case buildErrorFix
    case chatResponse
    case aiTest

    var displayName: String {
        switch self {
        case .architecturePlanning: return "Architecture Plan"
        case .fileGeneration: return "File Generation"
        case .codeValidationFix: return "Validation Fix"
        case .wireframeGeneration: return "Wireframe"
        case .semanticEnrichment: return "Semantic Enrichment"
        case .buildErrorFix: return "Build Error Fix"
        case .chatResponse: return "Chat Response"
        case .aiTest: return "AI Test"
        }
    }
}

// MARK: - Token Usage (returned from API services)

/// Lightweight token count pair returned alongside API response text.
struct TokenUsage: Sendable {
    let inputTokens: Int
    let outputTokens: Int

    static let zero = TokenUsage(inputTokens: 0, outputTokens: 0)
}

// MARK: - Token Usage Record

/// A single recorded API call with token counts and computed cost.
struct TokenUsageRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let provider: String
    let model: String
    let operation: TokenOperationType
    let operationDetail: String
    let inputTokens: Int
    let outputTokens: Int
    let inputCost: Double
    let outputCost: Double

    var totalCost: Double { inputCost + outputCost }
    var totalTokens: Int { inputTokens + outputTokens }
}

// MARK: - Provider Pricing

/// Per-model pricing used to convert token counts into dollar costs.
struct ProviderPricing: Sendable {
    let modelID: String
    let inputCostPerMillion: Double
    let outputCostPerMillion: Double

    func cost(inputTokens: Int, outputTokens: Int) -> (input: Double, output: Double) {
        let inp = Double(inputTokens) / 1_000_000.0 * inputCostPerMillion
        let out = Double(outputTokens) / 1_000_000.0 * outputCostPerMillion
        return (inp, out)
    }

    func totalCost(inputTokens: Int, outputTokens: Int) -> Double {
        let c = cost(inputTokens: inputTokens, outputTokens: outputTokens)
        return c.input + c.output
    }

    /// Known pricing table. Update when model pricing changes.
    /// Local Ollama models are $0.00 — they run on the user's Mac.
    static let catalog: [String: ProviderPricing] = [
        // Paid cloud models
        "claude-sonnet-4-5-20250929": ProviderPricing(
            modelID: "claude-sonnet-4-5-20250929",
            inputCostPerMillion: 3.0,
            outputCostPerMillion: 15.0
        ),
        "claude-opus-4-6": ProviderPricing(
            modelID: "claude-opus-4-6",
            inputCostPerMillion: 15.0,
            outputCostPerMillion: 75.0
        ),
        "gemini-2.0-flash": ProviderPricing(
            modelID: "gemini-2.0-flash",
            inputCostPerMillion: 0.10,
            outputCostPerMillion: 0.40
        ),
        "gpt-4o": ProviderPricing(
            modelID: "gpt-4o",
            inputCostPerMillion: 2.50,
            outputCostPerMillion: 10.0
        ),
        // Free local models (Ollama) — $0.00
        "deepseek-coder-v2:16b": ProviderPricing(
            modelID: "deepseek-coder-v2:16b",
            inputCostPerMillion: 0.0,
            outputCostPerMillion: 0.0
        ),
        "qwen2.5-coder:7b": ProviderPricing(
            modelID: "qwen2.5-coder:7b",
            inputCostPerMillion: 0.0,
            outputCostPerMillion: 0.0
        ),
        "gemma2:9b": ProviderPricing(
            modelID: "gemma2:9b",
            inputCostPerMillion: 0.0,
            outputCostPerMillion: 0.0
        ),
        "codellama:13b": ProviderPricing(
            modelID: "codellama:13b",
            inputCostPerMillion: 0.0,
            outputCostPerMillion: 0.0
        ),
    ]

    /// Looks up pricing for a model, falling back to Sonnet pricing if unknown.
    static func pricing(for modelID: String) -> ProviderPricing {
        catalog[modelID] ?? catalog["claude-sonnet-4-5-20250929"]!
    }
}

// MARK: - Cost Estimate

/// Pre-operation projection of what an action will cost.
struct CostEstimate: Sendable {
    let operation: TokenOperationType
    let estimatedCalls: Int
    let estimatedInputTokens: Int
    let estimatedOutputTokens: Int
    let estimatedCost: Double
    let breakdown: [CostEstimateItem]
    let model: String
    let quality: AIGenerationQuality

    var estimatedTotalTokens: Int { estimatedInputTokens + estimatedOutputTokens }
}

struct CostEstimateItem: Sendable {
    let label: String
    let calls: Int
    let inputTokens: Int
    let outputTokens: Int
    let cost: Double
}

// MARK: - Session Cost Summary

/// Aggregated cost view for the current session.
struct SessionCostSummary: Sendable {
    let totalCost: Double
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let totalCalls: Int
    let byOperation: [TokenOperationType: OperationCostSummary]
    let byModel: [String: Double]

    var totalTokens: Int { totalInputTokens + totalOutputTokens }

    static let empty = SessionCostSummary(
        totalCost: 0,
        totalInputTokens: 0,
        totalOutputTokens: 0,
        totalCalls: 0,
        byOperation: [:],
        byModel: [:]
    )
}

struct OperationCostSummary: Sendable {
    let calls: Int
    let inputTokens: Int
    let outputTokens: Int
    let cost: Double
}
