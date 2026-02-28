import Foundation

actor AnthropicService {

    // MARK: - Configuration

    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"
    private let maxRetries = 3

    // MARK: - Public Types

    struct Message: Sendable {
        let role: Role
        let content: [ContentBlock]

        enum Role: String, Sendable {
            case user
            case assistant
        }

        /// Convenience initializer for a simple text message
        static func user(_ text: String) -> Message {
            Message(role: .user, content: [.text(text)])
        }

        static func assistant(_ text: String) -> Message {
            Message(role: .assistant, content: [.text(text)])
        }
    }

    struct ContentBlock: Sendable {
        enum ContentType: Sendable {
            case text(String)
            case image(mediaType: String, base64Data: String)
        }

        let type: ContentType

        static func text(_ value: String) -> ContentBlock {
            ContentBlock(type: .text(value))
        }

        static func image(mediaType: String, base64Data: String) -> ContentBlock {
            ContentBlock(type: .image(mediaType: mediaType, base64Data: base64Data))
        }
    }

    enum ServiceError: LocalizedError, Sendable {
        case noAPIKey
        case httpError(Int, String)
        case decodingError(String)
        case rateLimited(retryAfter: TimeInterval?)
        case serverError(Int)
        case streamingError(String)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No Anthropic API key found. Set it in Keychain, UserDefaults, or ANTHROPIC_API_KEY environment variable."
            case .httpError(let code, let body):
                return "HTTP \(code): \(body)"
            case .decodingError(let message):
                return "Decoding error: \(message)"
            case .rateLimited(let retryAfter):
                if let retryAfter {
                    return "Rate limited. Retry after \(Int(retryAfter))s."
                }
                return "Rate limited."
            case .serverError(let code):
                return "Server error (HTTP \(code))."
            case .streamingError(let message):
                return "Streaming error: \(message)"
            }
        }
    }

    // MARK: - Streaming Message

    /// Streams a Claude API response, calling onChunk for each text delta.
    /// Returns the full accumulated response text when complete.
    func streamMessage(
        system: String,
        messages: [Message],
        model: AIGenerationQuality,
        maxTokens: Int = 8192,
        temperature: Double = 0.3,
        onChunk: @Sendable @MainActor (String) -> Void
    ) async throws -> String {
        let apiKey = try resolveAPIKey()
        let requestBody = buildRequestBody(
            system: system,
            messages: messages,
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            stream: true
        )

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.httpBody = requestBody
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        return try await executeStreamingRequest(request: request, onChunk: onChunk)
    }

    // MARK: - Non-Streaming Message

    /// Sends a non-streaming message and returns the full response text.
    func sendMessage(
        system: String,
        messages: [Message],
        model: AIGenerationQuality,
        maxTokens: Int = 8192,
        temperature: Double = 0.3
    ) async throws -> String {
        let apiKey = try resolveAPIKey()
        let requestBody = buildRequestBody(
            system: system,
            messages: messages,
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            stream: false
        )

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.httpBody = requestBody
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        let (data, httpResponse) = try await executeWithRetry(request: request)

        guard let response = httpResponse as? HTTPURLResponse else {
            throw ServiceError.httpError(0, "Missing HTTP response")
        }

        guard (200..<300).contains(response.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(response.statusCode, body)
        }

        return try extractTextFromResponse(data: data)
    }

    // MARK: - Private: API Key

    private func resolveAPIKey() throws -> String {
        guard let key = KeychainService.resolveAPIKey(for: .anthropicAPIKey) else {
            throw ServiceError.noAPIKey
        }
        return key
    }

    // MARK: - Private: Request Body

    private func buildRequestBody(
        system: String,
        messages: [Message],
        model: AIGenerationQuality,
        maxTokens: Int,
        temperature: Double,
        stream: Bool
    ) -> Data {
        var payload: [String: Any] = [
            "model": model.modelID,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "system": system,
            "stream": stream,
        ]

        let serializedMessages = messages.map { message -> [String: Any] in
            let contentArray = message.content.map { block -> [String: Any] in
                switch block.type {
                case .text(let text):
                    return [
                        "type": "text",
                        "text": text,
                    ]
                case .image(let mediaType, let base64Data):
                    return [
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": mediaType,
                            "data": base64Data,
                        ] as [String: Any],
                    ]
                }
            }

            return [
                "role": message.role.rawValue,
                "content": contentArray,
            ]
        }

        payload["messages"] = serializedMessages

        // Force try is safe here: the structure is always valid JSON
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    // MARK: - Private: Streaming Execution with Retry

    private func executeStreamingRequest(
        request: URLRequest,
        onChunk: @Sendable @MainActor (String) -> Void
    ) async throws -> String {
        var lastError: (any Error)?

        for attempt in 0..<maxRetries {
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ServiceError.httpError(0, "Missing HTTP response")
                }

                let statusCode = httpResponse.statusCode

                // Rate limited
                if statusCode == 429 {
                    let retryAfter = parseRetryAfter(from: httpResponse)
                    if attempt < maxRetries - 1 {
                        let delay = retryAfter ?? Double(2 * (attempt + 1))
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    }
                    throw ServiceError.rateLimited(retryAfter: retryAfter)
                }

                // Overloaded
                if statusCode == 529 {
                    if attempt < maxRetries - 1 {
                        let delay = pow(2.0, Double(attempt + 1)) // 2s, 4s, 8s
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        continue
                    }
                    throw ServiceError.serverError(statusCode)
                }

                // Other errors
                guard (200..<300).contains(statusCode) else {
                    // Collect the body for error details
                    var bodyChunks: [UInt8] = []
                    for try await byte in bytes {
                        bodyChunks.append(byte)
                        if bodyChunks.count > 4096 { break }
                    }
                    let body = String(bytes: bodyChunks, encoding: .utf8) ?? ""
                    throw ServiceError.httpError(statusCode, body)
                }

                // Success: parse the SSE stream
                return try await parseSSEStream(bytes: bytes, onChunk: onChunk)

            } catch let error as ServiceError {
                switch error {
                case .rateLimited, .serverError:
                    lastError = error
                    continue
                default:
                    throw error
                }
            } catch {
                // Network or cancellation errors: don't retry
                throw error
            }
        }

        throw lastError ?? ServiceError.streamingError("Max retries exceeded")
    }

    // MARK: - Private: Non-Streaming Execution with Retry

    private func executeWithRetry(
        request: URLRequest
    ) async throws -> (Data, URLResponse) {
        var lastError: (any Error)?

        for attempt in 0..<maxRetries {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return (data, response)
            }

            let statusCode = httpResponse.statusCode

            // Rate limited
            if statusCode == 429 {
                let retryAfter = parseRetryAfter(from: httpResponse)
                if attempt < maxRetries - 1 {
                    let delay = retryAfter ?? Double(2 * (attempt + 1))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    lastError = ServiceError.rateLimited(retryAfter: retryAfter)
                    continue
                }
                throw ServiceError.rateLimited(retryAfter: retryAfter)
            }

            // Overloaded
            if statusCode == 529 {
                if attempt < maxRetries - 1 {
                    let delay = pow(2.0, Double(attempt + 1))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    lastError = ServiceError.serverError(statusCode)
                    continue
                }
                throw ServiceError.serverError(statusCode)
            }

            // All other statuses: return immediately (caller handles success/error)
            return (data, response)
        }

        throw lastError ?? ServiceError.streamingError("Max retries exceeded")
    }

    // MARK: - Private: SSE Parsing

    private func parseSSEStream(
        bytes: URLSession.AsyncBytes,
        onChunk: @Sendable @MainActor (String) -> Void
    ) async throws -> String {
        var accumulated = ""
        var lineBuffer = ""

        for try await byte in bytes {
            let char = Character(UnicodeScalar(byte))

            if char == "\n" {
                let line = lineBuffer
                lineBuffer = ""

                // SSE lines starting with "data: " contain the payload
                guard line.hasPrefix("data: ") else { continue }

                let jsonString = String(line.dropFirst(6))

                // End of stream signal
                if jsonString == "[DONE]" {
                    break
                }

                guard let jsonData = jsonString.data(using: .utf8) else { continue }

                guard let event = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                    continue
                }

                let eventType = event["type"] as? String ?? ""

                switch eventType {
                case "content_block_delta":
                    if let delta = event["delta"] as? [String: Any],
                       let text = delta["text"] as? String {
                        accumulated += text
                        await onChunk(text)
                    }

                case "message_stop":
                    break

                case "error":
                    let errorInfo = event["error"] as? [String: Any]
                    let message = errorInfo?["message"] as? String ?? "Unknown streaming error"
                    throw ServiceError.streamingError(message)

                default:
                    // Ignore other event types: message_start, content_block_start,
                    // content_block_stop, message_delta, ping
                    break
                }
            } else {
                lineBuffer.append(char)
            }
        }

        return accumulated
    }

    // MARK: - Private: Response Extraction

    private func extractTextFromResponse(data: Data) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ServiceError.decodingError("Response is not valid JSON")
        }

        // Check for API error response
        if let errorInfo = root["error"] as? [String: Any],
           let message = errorInfo["message"] as? String {
            let type = errorInfo["type"] as? String ?? "unknown"
            throw ServiceError.decodingError("\(type): \(message)")
        }

        guard let content = root["content"] as? [[String: Any]] else {
            throw ServiceError.decodingError("No 'content' array in response")
        }

        let textParts = content.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }

        guard !textParts.isEmpty else {
            throw ServiceError.decodingError("No text content blocks in response")
        }

        return textParts.joined()
    }

    // MARK: - Private: Retry-After Parsing

    private func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "retry-after") else {
            return nil
        }
        return Double(value)
    }
}
