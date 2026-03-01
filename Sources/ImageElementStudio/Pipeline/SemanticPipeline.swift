import Foundation

struct SemanticPipelineResult {
    var document: AnalysisDocument
    var narrative: String
    var source: String
}

struct SemanticPipeline {
    private let heuristicEngine = HeuristicSemanticEngine()
    private let blueprintEngine = BlueprintInferenceEngine()
    private let remoteEngine: OpenAISemanticEngine?

    init() {
        // Resolve OpenAI key from Keychain (or environment for dev/CI)
        if let apiKey = KeychainService.resolveAPIKey(for: .openaiAPIKey) {
            remoteEngine = OpenAISemanticEngine(apiKey: apiKey)
        } else {
            remoteEngine = nil
        }
    }

    func enrich(document: AnalysisDocument, imageData: Data?) async -> SemanticPipelineResult {
        let heuristicResult = heuristicEngine.interpret(document: document)
        var selectedResult = heuristicResult

        if let remoteEngine, let imageData {
            do {
                selectedResult = try await remoteEngine.interpret(document: heuristicResult.document, imageData: imageData)
            } catch {
                selectedResult.document.metadata.notes.append(
                    "Remote AI enrichment failed: \(error.localizedDescription). Using local semantic inference."
                )
            }
        }

        let blueprintResult = blueprintEngine.infer(document: selectedResult.document)
        let narrativeParts = [selectedResult.narrative, blueprintResult.narrative]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let narrative = narrativeParts.joined(separator: " ")

        return SemanticPipelineResult(
            document: blueprintResult.document,
            narrative: narrative,
            source: selectedResult.source
        )
    }
}
