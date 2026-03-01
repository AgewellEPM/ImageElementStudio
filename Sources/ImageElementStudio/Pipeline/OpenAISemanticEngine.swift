import AppKit
import Foundation

struct OpenAISemanticEngine {
    let apiKey: String
    let model: String = "gpt-4.1-mini"

    func interpret(document: AnalysisDocument, imageData: Data) async throws -> SemanticPipelineResult {
        let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
        let serializedElements = serializeElements(document.artboard.elements)
        let base64Image = imageData.base64EncodedString()

        let systemPrompt = """
        You are an AI UI analyst. Infer app type, product scope, and semantic roles for elements.
        Return strict JSON only with keys:
        appType, confidence, productIntent, targetUsers, keyCapabilities, openQuestions, implementationRoadmap, summary, elementMappings.
        elementMappings is an array of objects with: index, name, role, reason, confidence.
        role must be one of:
        unknown, appBrand, navigationItem, navigationSection, heading, sectionTitle, metricValue, metricLabel, metricDelta, chart, chartAxis, tableHeader, tableCell, buttonPrimary, buttonSecondary, dateFilter, avatar, tag, panel, listItem.
        """

        let userPrompt = """
        Infer semantics from this UI screenshot and OCR/layout extraction.
        Elements (index aligned): \(serializedElements)
        """

        let payload: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "response_format": ["type": "json_object"],
            "messages": [
                [
                    "role": "system",
                    "content": systemPrompt,
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": userPrompt,
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)",
                            ],
                        ],
                    ],
                ],
            ],
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SemanticPipelineError.invalidResponse("Missing HTTP response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SemanticPipelineError.invalidResponse("Status \(httpResponse.statusCode): \(body)")
        }

        guard let content = try extractMessageContent(from: data) else {
            throw SemanticPipelineError.invalidResponse("No assistant content found")
        }

        let decoded = try JSONDecoder().decode(RemoteSemanticPayload.self, from: Data(content.utf8))
        let result = applyRemotePayload(decoded, onto: document)

        return result
    }

    private func applyRemotePayload(_ payload: RemoteSemanticPayload, onto document: AnalysisDocument) -> SemanticPipelineResult {
        var updated = document
        var elements = updated.artboard.elements

        for mapping in payload.elementMappings {
            guard elements.indices.contains(mapping.index) else { continue }

            var element = elements[mapping.index]
            let role = SemanticElementRole(rawValue: mapping.role) ?? element.semanticRole ?? .unknown

            element.semanticRole = role
            element.semanticReason = mapping.reason
            if !mapping.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                element.name = mapping.name
            }

            if let mappingConfidence = mapping.confidence {
                element.confidence = max(element.confidence, min(1.0, max(0.0, mappingConfidence)))
            }

            var tags = Set(element.tags)
            tags.insert("semantic:\(role.rawValue)")
            element.tags = tags.sorted()

            elements[mapping.index] = element
        }

        updated.artboard.elements = elements
        updated.scope = ProductScopeSnapshot(
            appType: payload.appType,
            confidence: min(1.0, max(0.0, payload.confidence)),
            productIntent: payload.productIntent,
            targetUsers: normalized(payload.targetUsers),
            keyCapabilities: normalized(payload.keyCapabilities),
            openQuestions: normalized(payload.openQuestions),
            implementationRoadmap: normalized(payload.implementationRoadmap),
            summary: payload.summary
        )
        updated.metadata.engine = "\(updated.metadata.engine) + OpenAI Semantic Vision"
        updated.metadata.notes.append("Remote multimodal semantic analysis applied.")

        return SemanticPipelineResult(
            document: updated,
            narrative: payload.summary,
            source: "OpenAI Semantic Vision"
        )
    }

    private func normalized(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func serializeElements(_ elements: [CanvasElement]) -> String {
        let formatted = elements.enumerated().prefix(140).map { index, element in
            let text = (element.content ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .prefix(90)
            return """
            {
              "index": \(index),
              "kind": "\(element.kind.rawValue)",
              "name": "\(escape(element.name))",
              "text": "\(escape(String(text)))",
              "frame": {"x": \(Int(element.frame.x)), "y": \(Int(element.frame.y)), "w": \(Int(element.frame.width)), "h": \(Int(element.frame.height))}
            }
            """
        }
        return "[\(formatted.joined(separator: ","))]"
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func extractMessageContent(from data: Data) throws -> String? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            return nil
        }

        if let content = message["content"] as? String {
            return content
        }

        if let parts = message["content"] as? [[String: Any]] {
            let texts = parts.compactMap { $0["text"] as? String }
            return texts.joined(separator: "\n")
        }

        return nil
    }
}

struct RemoteSemanticPayload: Codable {
    var appType: String
    var confidence: Double
    var productIntent: String
    var targetUsers: [String]
    var keyCapabilities: [String]
    var openQuestions: [String]
    var implementationRoadmap: [String]
    var summary: String
    var elementMappings: [RemoteElementMapping]
}

struct RemoteElementMapping: Codable {
    var index: Int
    var name: String
    var role: String
    var reason: String?
    var confidence: Double?
}

enum SemanticPipelineError: LocalizedError {
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case let .invalidResponse(message):
            return message
        }
    }
}

extension NSImage {
    func jpegData(maxDimension: CGFloat = 1400, compression: CGFloat = 0.78) -> Data? {
        guard let cgImage = resolvedCGImage else { return nil }

        let sourceSize = CGSize(width: cgImage.width, height: cgImage.height)
        let maxSourceDimension = max(sourceSize.width, sourceSize.height)
        let ratio = maxSourceDimension > maxDimension ? (maxDimension / maxSourceDimension) : 1.0

        let resizedSize = CGSize(
            width: max(1, floor(sourceSize.width * ratio)),
            height: max(1, floor(sourceSize.height * ratio))
        )

        let scaledImage = NSImage(size: resizedSize)
        scaledImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSImage(cgImage: cgImage, size: sourceSize)
            .draw(in: CGRect(origin: .zero, size: resizedSize))
        scaledImage.unlockFocus()

        guard let tiffData = scaledImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: compression]
        )
    }
}
