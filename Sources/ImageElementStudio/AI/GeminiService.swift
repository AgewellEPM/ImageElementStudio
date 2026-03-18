import Foundation
import os

// MARK: - GeminiService

/// A lightweight actor that wraps the Google Gemini `generateContent` REST endpoint.
/// Mirrors the rate-limiting structure of `AnthropicService` (500 ms minimum interval,
/// 30 requests / minute cap).
actor GeminiService {

    // MARK: - Configuration

    private let defaultModel = "gemini-2.0-flash"
    private let baseURLTemplate = "https://generativelanguage.googleapis.com/v1beta/models/%@:generateContent"
    private let maxRetries = 3

    // MARK: - Rate Limiting

    private let minimumRequestInterval: TimeInterval = 0.5
    private let maxRequestsPerMinute = 30
    private var requestTimestamps: [Date] = []

    private let logger = Logger(
        subsystem: "com.imageelementstudio",
        category: "GeminiService"
    )

    // MARK: - Errors

    enum GeminiServiceError: LocalizedError {
        case invalidURL
        case noResponse
        case httpError(Int, String)
        case decodingError(String)
        case rateLimited(retryAfter: TimeInterval?)
        case clientRateLimited(retryAfter: TimeInterval)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Could not construct a valid Gemini API URL."
            case .noResponse:
                return "No HTTP response received from Gemini API."
            case .httpError(let code, let body):
                return "Gemini API HTTP \(code): \(body)"
            case .decodingError(let message):
                return "Gemini response decoding error: \(message)"
            case .rateLimited(let retryAfter):
                if let retryAfter {
                    return "Gemini API rate limited. Retry after \(Int(retryAfter))s."
                }
                return "Gemini API rate limited."
            case .clientRateLimited(let retryAfter):
                return "Client rate limit exceeded. Wait \(String(format: "%.1f", retryAfter))s before retrying."
            case .emptyResponse:
                return "Gemini API returned a response with no text content."
            }
        }
    }

    // MARK: - Rate Limit Enforcement

    private func checkRateLimit() throws {
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)

        // Drop timestamps outside the rolling window
        requestTimestamps.removeAll { $0 < oneMinuteAgo }

        // Minimum interval between consecutive requests
        if let last = requestTimestamps.last {
            let elapsed = now.timeIntervalSince(last)
            if elapsed < minimumRequestInterval {
                let wait = minimumRequestInterval - elapsed
                logger.warning("Rate limit: minimum interval not met, elapsed=\(elapsed, format: .fixed(precision: 3))s")
                throw GeminiServiceError.clientRateLimited(retryAfter: wait)
            }
        }

        // Per-minute cap
        if requestTimestamps.count >= maxRequestsPerMinute {
            let oldest = requestTimestamps[0]
            let wait = max(60.0 - now.timeIntervalSince(oldest), 0.5)
            logger.warning("Rate limit: \(self.maxRequestsPerMinute) req/min cap reached")
            throw GeminiServiceError.clientRateLimited(retryAfter: wait)
        }

        requestTimestamps.append(now)
    }

    // MARK: - Public API

    /// Sends a prompt to the Gemini API and returns the full text response.
    func generateContent(
        prompt: String,
        systemInstruction: String? = nil,
        apiKey: String,
        model: String? = nil
    ) async throws -> String {
        let (text, _) = try await generateContentWithUsage(
            prompt: prompt,
            systemInstruction: systemInstruction,
            apiKey: apiKey,
            model: model
        )
        return text
    }

    /// Sends a prompt to the Gemini API and returns the text response with token usage.
    func generateContentWithUsage(
        prompt: String,
        systemInstruction: String? = nil,
        apiKey: String,
        model: String? = nil
    ) async throws -> (String, TokenUsage) {
        try checkRateLimit()

        let resolvedModel = model ?? defaultModel
        let urlString = String(format: baseURLTemplate, resolvedModel)
            + "?key=\(apiKey)"

        guard let url = URL(string: urlString) else {
            throw GeminiServiceError.invalidURL
        }

        let body = buildRequestBody(prompt: prompt, systemInstruction: systemInstruction)
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            throw GeminiServiceError.decodingError("Failed to serialize request body")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        logger.info("Gemini generateContent: model=\(resolvedModel, privacy: .public), promptLen=\(prompt.count)")

        let (text, usage) = try await executeWithRetryAndUsage(request: request)

        logger.info("Gemini generateContent complete: responseLen=\(text.count), tokens=\(usage.inputTokens)+\(usage.outputTokens)")
        return (text, usage)
    }

    // MARK: - Private: Request Body

    private func buildRequestBody(prompt: String, systemInstruction: String?) -> [String: Any] {
        var body: [String: Any] = [
            "contents": [
                [
                    "parts": [["text": prompt]]
                ]
            ]
        ]

        if let system = systemInstruction, !system.isEmpty {
            body["system_instruction"] = [
                "parts": [["text": system]]
            ]
        }

        return body
    }

    // MARK: - Private: HTTP Execution with Retry

    private func executeWithRetry(request: URLRequest) async throws -> String {
        let (text, _) = try await executeWithRetryAndUsage(request: request)
        return text
    }

    private func executeWithRetryAndUsage(request: URLRequest) async throws -> (String, TokenUsage) {
        var lastError: (any Error)?

        for attempt in 0..<maxRetries {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let http = response as? HTTPURLResponse else {
                    throw GeminiServiceError.noResponse
                }

                // Rate limited — back off and retry
                if http.statusCode == 429 {
                    let retryAfter = parseRetryAfter(from: http)
                    logger.warning("Gemini 429 (attempt \(attempt + 1)/\(self.maxRetries))")
                    if attempt < maxRetries - 1 {
                        let delay = retryAfter ?? Double(2 * (attempt + 1))
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        lastError = GeminiServiceError.rateLimited(retryAfter: retryAfter)
                        continue
                    }
                    throw GeminiServiceError.rateLimited(retryAfter: retryAfter)
                }

                // Server errors — exponential back-off
                if http.statusCode >= 500 {
                    logger.warning("Gemini \(http.statusCode) (attempt \(attempt + 1)/\(self.maxRetries))")
                    if attempt < maxRetries - 1 {
                        let delay = pow(2.0, Double(attempt + 1))
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        lastError = GeminiServiceError.httpError(http.statusCode, "Server error")
                        continue
                    }
                }

                // Non-2xx error — surface immediately
                guard (200..<300).contains(http.statusCode) else {
                    let body = String(data: data, encoding: .utf8) ?? "<non-UTF8 body>"
                    throw GeminiServiceError.httpError(http.statusCode, body)
                }

                return try extractTextAndUsage(from: data)

            } catch let err as GeminiServiceError {
                // Propagate non-retriable errors immediately
                switch err {
                case .rateLimited, .httpError:
                    lastError = err
                default:
                    throw err
                }
            } catch {
                // Network / cancellation errors are not retried
                throw error
            }
        }

        throw lastError ?? GeminiServiceError.decodingError("Max retries exceeded")
    }

    // MARK: - Private: Response Extraction

    private func extractText(from data: Data) throws -> String {
        let (text, _) = try extractTextAndUsage(from: data)
        return text
    }

    private func extractTextAndUsage(from data: Data) throws -> (String, TokenUsage) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiServiceError.decodingError("Response is not a JSON object")
        }

        // Surface API-level error objects
        if let error = root["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw GeminiServiceError.decodingError(message)
        }

        // candidates[0].content.parts[0].text
        guard let candidates = root["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw GeminiServiceError.decodingError("Unexpected response structure; no candidates")
        }

        let texts = parts.compactMap { $0["text"] as? String }

        guard !texts.isEmpty else {
            throw GeminiServiceError.emptyResponse
        }

        // Extract usage metadata
        var inputTokens = 0
        var outputTokens = 0
        if let usageMeta = root["usageMetadata"] as? [String: Any] {
            inputTokens = usageMeta["promptTokenCount"] as? Int ?? 0
            outputTokens = usageMeta["candidatesTokenCount"] as? Int ?? 0
        }

        return (texts.joined(), TokenUsage(inputTokens: inputTokens, outputTokens: outputTokens))
    }

    // MARK: - Private: Retry-After Parsing

    private func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        return Double(value)
    }
}
