import Foundation
import os

// MARK: - OllamaService

/// Lightweight actor that wraps the Ollama local REST API (`/api/generate` and `/api/chat`).
/// Ollama runs free, open-source models locally on the Mac — zero API cost.
///
/// Supported models: DeepSeek Coder V2, Qwen 2.5 Coder, Gemma 2, CodeLlama, and any
/// model the user has pulled via `ollama pull`.
actor OllamaService {

    // MARK: - Configuration

    private let defaultBaseURL = "http://localhost:11434"
    private let maxRetries = 2

    private let logger = Logger(
        subsystem: "com.imageelementstudio",
        category: "OllamaService"
    )

    // MARK: - Errors

    enum OllamaError: LocalizedError {
        case notRunning
        case invalidURL
        case httpError(Int, String)
        case decodingError(String)
        case emptyResponse
        case modelNotFound(String)

        var errorDescription: String? {
            switch self {
            case .notRunning:
                return "Ollama is not running. Start it with `ollama serve` or launch the Ollama app."
            case .invalidURL:
                return "Could not construct a valid Ollama API URL."
            case .httpError(let code, let body):
                return "Ollama HTTP \(code): \(body)"
            case .decodingError(let message):
                return "Ollama response decoding error: \(message)"
            case .emptyResponse:
                return "Ollama returned an empty response."
            case .modelNotFound(let model):
                return "Model '\(model)' not found. Run `ollama pull \(model)` to download it."
            }
        }
    }

    // MARK: - Health Check

    /// Checks whether Ollama is running and reachable.
    func isAvailable() async -> Bool {
        guard let url = URL(string: "\(resolveBaseURL())/api/tags") else { return false }

        do {
            let (_, response) = try await URLSession.shared.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    /// Lists locally available models.
    func listModels() async -> [OllamaModelInfo] {
        guard let url = URL(string: "\(resolveBaseURL())/api/tags") else { return [] }

        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return [] }

            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = root["models"] as? [[String: Any]] else { return [] }

            return models.compactMap { dict in
                guard let name = dict["name"] as? String else { return nil }
                let size = dict["size"] as? Int ?? 0
                return OllamaModelInfo(name: name, sizeBytes: size)
            }
        } catch {
            return []
        }
    }

    // MARK: - Chat Completion (OpenAI-compatible format)

    /// Sends a chat completion request to the Ollama API and returns the full text + token usage.
    func chatCompletion(
        model: String,
        system: String,
        messages: [(role: String, content: String)],
        temperature: Double = 0.3,
        maxTokens: Int = 8192
    ) async throws -> (String, TokenUsage) {
        guard await isAvailable() else {
            throw OllamaError.notRunning
        }

        let baseURL = resolveBaseURL()
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw OllamaError.invalidURL
        }

        var allMessages: [[String: String]] = [
            ["role": "system", "content": system]
        ]
        for msg in messages {
            allMessages.append(["role": msg.role, "content": msg.content])
        }

        let payload: [String: Any] = [
            "model": model,
            "messages": allMessages,
            "stream": false,
            "options": [
                "temperature": temperature,
                "num_predict": maxTokens
            ] as [String: Any]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
            throw OllamaError.decodingError("Failed to serialize request body")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300 // Local models can be slow

        logger.info("Ollama chat: model=\(model, privacy: .public), messages=\(allMessages.count)")

        return try await executeWithRetry(request: request, model: model)
    }

    /// Streaming chat completion — calls onChunk for each text delta, returns full text + usage.
    func streamChatCompletion(
        model: String,
        system: String,
        messages: [(role: String, content: String)],
        temperature: Double = 0.3,
        maxTokens: Int = 8192,
        onChunk: @Sendable @MainActor (String) -> Void
    ) async throws -> (String, TokenUsage) {
        guard await isAvailable() else {
            throw OllamaError.notRunning
        }

        let baseURL = resolveBaseURL()
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw OllamaError.invalidURL
        }

        var allMessages: [[String: String]] = [
            ["role": "system", "content": system]
        ]
        for msg in messages {
            allMessages.append(["role": msg.role, "content": msg.content])
        }

        let payload: [String: Any] = [
            "model": model,
            "messages": allMessages,
            "stream": true,
            "options": [
                "temperature": temperature,
                "num_predict": maxTokens
            ] as [String: Any]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: payload) else {
            throw OllamaError.decodingError("Failed to serialize request body")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        logger.info("Ollama streaming chat: model=\(model, privacy: .public)")

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OllamaError.httpError(0, "No HTTP response")
        }

        guard (200..<300).contains(http.statusCode) else {
            throw OllamaError.httpError(http.statusCode, "HTTP error")
        }

        var accumulated = ""
        var promptTokens = 0
        var completionTokens = 0
        var lineBuffer = ""

        for try await byte in bytes {
            let char = Character(UnicodeScalar(byte))

            if char == "\n" {
                let line = lineBuffer.trimmingCharacters(in: .whitespaces)
                lineBuffer = ""

                guard !line.isEmpty,
                      let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }

                // Extract streamed text
                if let message = json["message"] as? [String: Any],
                   let content = message["content"] as? String, !content.isEmpty {
                    accumulated += content
                    await onChunk(content)
                }

                // Final message has "done": true and token counts
                if let done = json["done"] as? Bool, done {
                    promptTokens = json["prompt_eval_count"] as? Int ?? 0
                    completionTokens = json["eval_count"] as? Int ?? 0
                }
            } else {
                lineBuffer.append(char)
            }
        }

        guard !accumulated.isEmpty else {
            throw OllamaError.emptyResponse
        }

        let usage = TokenUsage(inputTokens: promptTokens, outputTokens: completionTokens)
        logger.info("Ollama streaming complete: \(accumulated.count) chars, \(usage.inputTokens)+\(usage.outputTokens) tokens")
        return (accumulated, usage)
    }

    // MARK: - Private: Retry Logic

    private func executeWithRetry(request: URLRequest, model: String) async throws -> (String, TokenUsage) {
        var lastError: (any Error)?

        for attempt in 0..<maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let http = response as? HTTPURLResponse else {
                    throw OllamaError.httpError(0, "No HTTP response")
                }

                // Model not found
                if http.statusCode == 404 {
                    throw OllamaError.modelNotFound(model)
                }

                guard (200..<300).contains(http.statusCode) else {
                    let body = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
                    if attempt < maxRetries - 1 {
                        lastError = OllamaError.httpError(http.statusCode, body)
                        let delay = pow(2.0, Double(attempt + 1))
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    }
                    throw OllamaError.httpError(http.statusCode, body)
                }

                return try extractResponse(from: data)

            } catch let err as OllamaError {
                switch err {
                case .modelNotFound:
                    throw err // Don't retry model-not-found
                default:
                    lastError = err
                }
            } catch {
                throw error // Network/cancellation — don't retry
            }
        }

        throw lastError ?? OllamaError.decodingError("Max retries exceeded")
    }

    // MARK: - Private: Response Extraction

    private func extractResponse(from data: Data) throws -> (String, TokenUsage) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OllamaError.decodingError("Response is not a JSON object")
        }

        // Ollama /api/chat non-streaming response
        guard let message = root["message"] as? [String: Any],
              let content = message["content"] as? String, !content.isEmpty else {
            // Check for error
            if let errorMsg = root["error"] as? String {
                if errorMsg.lowercased().contains("not found") {
                    throw OllamaError.modelNotFound(errorMsg)
                }
                throw OllamaError.decodingError(errorMsg)
            }
            throw OllamaError.emptyResponse
        }

        let promptTokens = root["prompt_eval_count"] as? Int ?? 0
        let completionTokens = root["eval_count"] as? Int ?? 0

        let usage = TokenUsage(inputTokens: promptTokens, outputTokens: completionTokens)
        logger.info("Ollama response: \(content.count) chars, \(usage.inputTokens)+\(usage.outputTokens) tokens")

        return (content, usage)
    }

    // MARK: - Private: Base URL

    private func resolveBaseURL() -> String {
        // Allow override via environment variable or UserDefaults
        if let envURL = ProcessInfo.processInfo.environment["OLLAMA_HOST"], !envURL.isEmpty {
            return envURL.hasSuffix("/") ? String(envURL.dropLast()) : envURL
        }
        if let customURL = UserDefaults.standard.string(forKey: "ollamaBaseURL"), !customURL.isEmpty {
            return customURL.hasSuffix("/") ? String(customURL.dropLast()) : customURL
        }
        return defaultBaseURL
    }
}

// MARK: - Model Info

struct OllamaModelInfo: Sendable, Identifiable {
    let name: String
    let sizeBytes: Int

    var id: String { name }

    var displayName: String {
        // Clean up model name for display
        let base = name.components(separatedBy: ":").first ?? name
        return base
            .replacingOccurrences(of: "deepseek-coder-v2", with: "DeepSeek Coder V2")
            .replacingOccurrences(of: "qwen2.5-coder", with: "Qwen 2.5 Coder")
            .replacingOccurrences(of: "gemma2", with: "Gemma 2")
            .replacingOccurrences(of: "codellama", with: "CodeLlama")
            .replacingOccurrences(of: "llama3.1", with: "Llama 3.1")
            .replacingOccurrences(of: "mistral", with: "Mistral")
    }

    var sizeDescription: String {
        let gb = Double(sizeBytes) / 1_073_741_824.0
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(sizeBytes) / 1_048_576.0
        return String(format: "%.0f MB", mb)
    }
}

// MARK: - Recommended Free Models

/// Well-known free coding models that work great with Ollama for code generation.
enum OllamaRecommendedModel: String, CaseIterable, Identifiable, Sendable {
    case deepseekCoderV2 = "deepseek-coder-v2:16b"
    case qwen25Coder = "qwen2.5-coder:7b"
    case gemma2 = "gemma2:9b"
    case codeLlama = "codellama:13b"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepseekCoderV2: return "DeepSeek Coder V2 (16B)"
        case .qwen25Coder: return "Qwen 2.5 Coder (7B)"
        case .gemma2: return "Gemma 2 (9B)"
        case .codeLlama: return "CodeLlama (13B)"
        }
    }

    var pullCommand: String {
        "ollama pull \(rawValue)"
    }

    var shortName: String {
        switch self {
        case .deepseekCoderV2: return "DeepSeek V2"
        case .qwen25Coder: return "Qwen 2.5"
        case .gemma2: return "Gemma 2"
        case .codeLlama: return "CodeLlama"
        }
    }

    /// The raw Ollama model tag to pass to the API.
    var modelTag: String { rawValue }
}
