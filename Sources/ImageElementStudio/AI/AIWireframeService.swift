import Foundation
import os

// MARK: - WireframeQuality

/// Controls how detailed the AI-generated wireframe layout will be.
enum WireframeQuality: String, CaseIterable {
    /// Basic structure: rectangular boxes, placeholder labels, no color.
    case loFi
    /// Detailed design: specific colors, realistic text, proper typography hierarchy.
    case hiFi

    var displayName: String {
        switch self {
        case .loFi: return "Lo-Fi"
        case .hiFi: return "Hi-Fi"
        }
    }

    /// Tag suffix embedded on every generated element for downstream filtering.
    var tagSuffix: String {
        switch self {
        case .loFi: return "quality:lofi"
        case .hiFi: return "quality:hifi"
        }
    }
}

// MARK: - AIWireframeService

/// Generates `CanvasElement` wireframe layouts from a natural-language description
/// using AI (Claude → Gemini → OpenAI, in priority order).
@MainActor
final class AIWireframeService: ObservableObject {

    // MARK: - Published State

    @Published var isGenerating: Bool = false
    @Published var generationProgress: String = ""
    @Published var generationError: String?

    // MARK: - Private

    private let logger = Logger(
        subsystem: "com.imageelementstudio",
        category: "AIWireframeService"
    )

    /// Optional cost service for recording token usage.
    var tokenCostService: TokenCostService?

    // MARK: - Public API

    /// Generates a flat array of `CanvasElement` values that form a wireframe layout.
    ///
    /// - Parameters:
    ///   - description: Natural-language description of the screen or component to design.
    ///   - existingElements: Elements already on the canvas (provided for context only;
    ///     the generated layout does not attempt to merge with them).
    ///   - artboardSize: The pixel dimensions of the target artboard.
    ///   - quality: Lo-fi (boxes and labels) or hi-fi (colours, realistic content).
    ///   - tokens: Optional design token set used to pull real colour values in hi-fi mode.
    /// - Returns: An array of parsed `CanvasElement` values, or an empty array on failure.
    func generateWireframe(
        description: String,
        existingElements: [CanvasElement],
        artboardSize: CGSize,
        quality: WireframeQuality,
        tokens: DesignTokenSet?
    ) async -> [CanvasElement] {
        isGenerating = true
        generationError = nil
        generationProgress = "Resolving AI provider..."

        defer {
            isGenerating = false
            generationProgress = ""
        }

        do {
            let response = try await callBestAvailableProvider(
                description: description,
                existingElements: existingElements,
                artboardSize: artboardSize,
                quality: quality,
                tokens: tokens
            )

            generationProgress = "Parsing wireframe elements..."
            let elements = parseWireframeResponse(response, quality: quality)
            logger.info("Wireframe generation complete: \(elements.count) elements")
            return elements

        } catch {
            generationError = error.localizedDescription
            logger.error("Wireframe generation failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Provider Resolution

    private func callBestAvailableProvider(
        description: String,
        existingElements: [CanvasElement],
        artboardSize: CGSize,
        quality: WireframeQuality,
        tokens: DesignTokenSet?
    ) async throws -> String {

        // 1. Anthropic Claude (primary)
        if let anthropicKey = KeychainService.resolveAPIKey(for: .anthropicAPIKey), !anthropicKey.isEmpty {
            generationProgress = "Generating with Claude..."
            logger.info("Wireframe provider: Anthropic Claude")
            return try await callClaude(
                description: description,
                existingElements: existingElements,
                artboardSize: artboardSize,
                quality: quality,
                tokens: tokens
            )
        }

        // 2. Ollama local models (free fallback)
        let ollamaService = OllamaService()
        if await ollamaService.isAvailable() {
            let models = await ollamaService.listModels()
            // Pick the best available coding model
            let preferredModels = ["deepseek-coder-v2", "qwen2.5-coder", "codellama", "gemma2", "llama"]
            if let match = preferredModels.first(where: { pref in models.contains { $0.name.contains(pref) } }),
               let model = models.first(where: { $0.name.contains(match) }) {
                generationProgress = "Generating with \(model.displayName) (free, local)..."
                logger.info("Wireframe provider: Ollama (\(model.name, privacy: .public))")
                return try await callOllama(
                    description: description,
                    existingElements: existingElements,
                    artboardSize: artboardSize,
                    quality: quality,
                    tokens: tokens,
                    modelName: model.name
                )
            }
        }

        // 3. Google Gemini (fallback)
        if let geminiKey = KeychainService.retrieveRaw(for: "gemini-api-key"), !geminiKey.isEmpty {
            generationProgress = "Generating with Gemini..."
            logger.info("Wireframe provider: Google Gemini")
            return try await callGemini(
                description: description,
                existingElements: existingElements,
                artboardSize: artboardSize,
                quality: quality,
                tokens: tokens,
                apiKey: geminiKey
            )
        }

        // 4. OpenAI (fallback)
        if let openaiKey = KeychainService.resolveAPIKey(for: .openaiAPIKey), !openaiKey.isEmpty {
            generationProgress = "Generating with OpenAI..."
            logger.info("Wireframe provider: OpenAI")
            return try await callOpenAI(
                description: description,
                existingElements: existingElements,
                artboardSize: artboardSize,
                quality: quality,
                tokens: tokens,
                apiKey: openaiKey
            )
        }

        // No provider available
        throw WireframeError.noProviderAvailable
    }

    // MARK: - Claude Call

    private func callClaude(
        description: String,
        existingElements: [CanvasElement],
        artboardSize: CGSize,
        quality: WireframeQuality,
        tokens: DesignTokenSet?
    ) async throws -> String {
        let systemPrompt = buildSystemPrompt(artboardSize: artboardSize, quality: quality)
        let userPrompt = buildUserPrompt(
            description: description,
            existingElements: existingElements,
            artboardSize: artboardSize,
            quality: quality,
            tokens: tokens
        )

        let anthropic = AnthropicService()
        let (response, usage) = try await anthropic.streamMessageWithUsage(
            system: systemPrompt,
            messages: [.user(userPrompt)],
            model: .fast,
            maxTokens: 8192,
            temperature: 0.4,
            onChunk: { _ in }
        )

        tokenCostService?.recordUsage(
            provider: "anthropic",
            model: AIGenerationQuality.fast.modelID,
            operation: .wireframeGeneration,
            detail: "Wireframe (\(quality.displayName))",
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens
        )

        return response
    }

    // MARK: - Ollama Call (Free Local)

    private func callOllama(
        description: String,
        existingElements: [CanvasElement],
        artboardSize: CGSize,
        quality: WireframeQuality,
        tokens: DesignTokenSet?,
        modelName: String
    ) async throws -> String {
        let systemPrompt = buildSystemPrompt(artboardSize: artboardSize, quality: quality)
        let userPrompt = buildUserPrompt(
            description: description,
            existingElements: existingElements,
            artboardSize: artboardSize,
            quality: quality,
            tokens: tokens
        )

        let ollamaService = OllamaService()
        let (response, usage) = try await ollamaService.chatCompletion(
            model: modelName,
            system: systemPrompt,
            messages: [("user", userPrompt)],
            temperature: 0.4,
            maxTokens: 8192
        )

        tokenCostService?.recordUsage(
            provider: "ollama",
            model: modelName,
            operation: .wireframeGeneration,
            detail: "Wireframe (\(quality.displayName)) via \(modelName)",
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens
        )

        return response
    }

    // MARK: - Gemini Call

    private func callGemini(
        description: String,
        existingElements: [CanvasElement],
        artboardSize: CGSize,
        quality: WireframeQuality,
        tokens: DesignTokenSet?,
        apiKey: String
    ) async throws -> String {
        let systemPrompt = buildSystemPrompt(artboardSize: artboardSize, quality: quality)
        let userPrompt = buildUserPrompt(
            description: description,
            existingElements: existingElements,
            artboardSize: artboardSize,
            quality: quality,
            tokens: tokens
        )

        let gemini = GeminiService()
        let (response, usage) = try await gemini.generateContentWithUsage(
            prompt: userPrompt,
            systemInstruction: systemPrompt,
            apiKey: apiKey
        )

        tokenCostService?.recordUsage(
            provider: "gemini",
            model: "gemini-2.0-flash",
            operation: .wireframeGeneration,
            detail: "Wireframe (\(quality.displayName))",
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens
        )

        return response
    }

    // MARK: - OpenAI Call

    /// Minimal OpenAI chat-completions call used as the last-resort fallback.
    private func callOpenAI(
        description: String,
        existingElements: [CanvasElement],
        artboardSize: CGSize,
        quality: WireframeQuality,
        tokens: DesignTokenSet?,
        apiKey: String
    ) async throws -> String {
        let systemPrompt = buildSystemPrompt(artboardSize: artboardSize, quality: quality)
        let userPrompt = buildUserPrompt(
            description: description,
            existingElements: existingElements,
            artboardSize: artboardSize,
            quality: quality,
            tokens: tokens
        )

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        let payload: [String: Any] = [
            "model": "gpt-4o",
            "max_tokens": 8192,
            "temperature": 0.4,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw WireframeError.networkError("No HTTP response from OpenAI")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw WireframeError.networkError("OpenAI HTTP \(http.statusCode): \(body)")
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw WireframeError.parsingError("Could not extract text from OpenAI response")
        }

        // Extract OpenAI usage
        if let usageDict = root["usage"] as? [String: Any] {
            let promptTokens = usageDict["prompt_tokens"] as? Int ?? 0
            let completionTokens = usageDict["completion_tokens"] as? Int ?? 0
            tokenCostService?.recordUsage(
                provider: "openai",
                model: "gpt-4o",
                operation: .wireframeGeneration,
                detail: "Wireframe (\(quality.displayName))",
                inputTokens: promptTokens,
                outputTokens: completionTokens
            )
        }

        return content
    }

    // MARK: - Prompt Construction

    private func buildSystemPrompt(artboardSize: CGSize, quality: WireframeQuality) -> String {
        let qualityGuidance: String
        switch quality {
        case .loFi:
            qualityGuidance = """
            You are producing a LO-FI wireframe. Use simple rectangular shapes only.
            - Use gray as the fill color for all shapes (#CCCCCC for panels, #AAAAAA for buttons, #EEEEEE for backgrounds).
            - Use placeholder text (e.g., "Heading Text", "Body copy here", "Button Label").
            - Focus on layout structure, hierarchy, and spacing — not visual polish.
            - Do not specify specific fonts, gradients, or imagery.
            """
        case .hiFi:
            qualityGuidance = """
            You are producing a HI-FI wireframe with realistic visual design.
            - Use specific color values appropriate to the described application's purpose.
            - Use realistic text content (proper headings, descriptive labels, realistic data).
            - Apply proper typographic hierarchy (large headings, medium subheadings, small body text).
            - Include design details: corner radii, fills, stroke colors where appropriate.
            - Make the design look production-ready.
            """
        }

        return """
        You are an expert UI/UX designer and wireframe generator.
        Your task is to produce a structured JSON array of UI elements that form a wireframe layout.

        \(qualityGuidance)

        CRITICAL OUTPUT RULES:
        - Respond ONLY with a valid JSON array. No prose, no markdown outside the JSON block.
        - If you must use a code fence, use ```json ... ```.
        - Every element must have all required fields.
        - Coordinates are in points, origin at top-left of the artboard.
        - Elements must not overflow the artboard bounds.
        - SemanticRole must be one of: unknown, appBrand, navigationItem, navigationSection, heading, sectionTitle, metricValue, metricLabel, metricDelta, chart, chartAxis, tableHeader, tableCell, buttonPrimary, buttonSecondary, dateFilter, avatar, tag, panel, listItem.
        - Kind must be "text" or "shape".
        """
    }

    private func buildUserPrompt(
        description: String,
        existingElements: [CanvasElement],
        artboardSize: CGSize,
        quality: WireframeQuality,
        tokens: DesignTokenSet?
    ) -> String {
        var parts: [String] = []

        parts.append("""
        Design a \(quality.displayName) wireframe for the following screen:

        DESCRIPTION:
        \(description)

        ARTBOARD SIZE: \(Int(artboardSize.width)) x \(Int(artboardSize.height)) points
        """)

        if let tokens, quality == .hiFi {
            var tokenLines: [String] = ["DESIGN TOKENS (use these colors and values):"]
            for (name, hex) in tokens.colors.sorted(by: { $0.key < $1.key }) {
                tokenLines.append("  color.\(name) = \(hex)")
            }
            for (name, value) in tokens.typography.sorted(by: { $0.key < $1.key }) {
                tokenLines.append("  typography.\(name) = \(value)")
            }
            for (name, value) in tokens.spacing.sorted(by: { $0.key < $1.key }) {
                tokenLines.append("  spacing.\(name) = \(value)pt")
            }
            parts.append(tokenLines.joined(separator: "\n"))
        }

        if !existingElements.isEmpty {
            parts.append("""
            EXISTING ELEMENTS ON CANVAS (for context — do NOT duplicate these):
            \(existingElements.prefix(10).map { "- \($0.name) [\($0.kind.rawValue)] at (\(Int($0.frame.x)),\(Int($0.frame.y))) \(Int($0.frame.width))x\(Int($0.frame.height))" }.joined(separator: "\n"))
            """)
        }

        parts.append("""
        OUTPUT FORMAT — a JSON array where each element has exactly these fields:
        [
          {
            "name": "Element Name",
            "kind": "text|shape",
            "x": 0,
            "y": 0,
            "width": 100,
            "height": 40,
            "content": "Display text or null for pure shapes",
            "semanticRole": "panel",
            "confidence": 0.9
          }
        ]

        Generate 8–25 elements that form a complete, coherent \(quality.displayName) layout.
        Ensure the layout fills the artboard meaningfully with proper hierarchy and grouping.
        """)

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Response Parsing

    private func parseWireframeResponse(_ response: String, quality: WireframeQuality) -> [CanvasElement] {
        // Extract the raw JSON string, handling optional markdown code fences
        let jsonString = extractJSON(from: response)

        guard let data = jsonString.data(using: .utf8),
              let rawArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            logger.error("Failed to parse wireframe JSON response")
            generationError = "Could not parse wireframe JSON from AI response."
            return []
        }

        var elements: [CanvasElement] = []

        for raw in rawArray {
            guard let element = parseElement(from: raw, quality: quality) else {
                logger.warning("Skipped unparseable wireframe element: \(raw.keys.joined(separator: ", "), privacy: .public)")
                continue
            }
            elements.append(element)
        }

        return elements
    }

    /// Strips markdown code fences and returns the innermost JSON content.
    private func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle ```json ... ``` or ``` ... ```
        if trimmed.hasPrefix("```") {
            var lines = trimmed.components(separatedBy: "\n")
            // Remove the opening fence line (e.g., "```json")
            lines.removeFirst()
            // Remove the closing fence if present
            if lines.last?.trimmingCharacters(in: .whitespaces) == "```" {
                lines.removeLast()
            }
            return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try to find the first '[' and last ']' for bare JSON arrays embedded in prose
        if let start = trimmed.firstIndex(of: "["),
           let end = trimmed.lastIndex(of: "]") {
            return String(trimmed[start...end])
        }

        return trimmed
    }

    private func parseElement(from raw: [String: Any], quality: WireframeQuality) -> CanvasElement? {
        guard
            let name = raw["name"] as? String,
            let kindRaw = raw["kind"] as? String,
            let kind = ElementKind(rawValue: kindRaw),
            let x = (raw["x"] as? NSNumber).map({ Double(truncating: $0) }),
            let y = (raw["y"] as? NSNumber).map({ Double(truncating: $0) }),
            let width = (raw["width"] as? NSNumber).map({ Double(truncating: $0) }),
            let height = (raw["height"] as? NSNumber).map({ Double(truncating: $0) }),
            width > 0,
            height > 0
        else {
            return nil
        }

        let content = raw["content"] as? String
        let confidence = (raw["confidence"] as? NSNumber).map { Double(truncating: $0) } ?? 0.75

        // SemanticRole: best-effort match, falls back to .unknown
        let semanticRole: SemanticElementRole
        if let roleRaw = raw["semanticRole"] as? String,
           let parsed = SemanticElementRole(rawValue: roleRaw) {
            semanticRole = parsed
        } else {
            semanticRole = .unknown
        }

        let tags: [String] = ["ai-wireframe", quality.tagSuffix]

        return CanvasElement(
            id: UUID(),
            name: name,
            kind: kind,
            frame: ElementFrame(x: x, y: y, width: width, height: height),
            confidence: confidence,
            content: content,
            tags: tags,
            semanticRole: semanticRole,
            semanticReason: "AI-generated wireframe element (\(quality.displayName))",
            rotationDegrees: 0,
            constraints: [],
            parentElementID: nil,
            componentReferenceID: nil,
            instanceOverrides: [:],
            style: nil
        )
    }

    // MARK: - Errors

    private enum WireframeError: LocalizedError {
        case noProviderAvailable
        case networkError(String)
        case parsingError(String)

        var errorDescription: String? {
            switch self {
            case .noProviderAvailable:
                return "No AI provider available. Add an API key in Settings, or install Ollama (ollama.com) with a coding model for free local generation."
            case .networkError(let message):
                return "Network error: \(message)"
            case .parsingError(let message):
                return "Parsing error: \(message)"
            }
        }
    }
}
