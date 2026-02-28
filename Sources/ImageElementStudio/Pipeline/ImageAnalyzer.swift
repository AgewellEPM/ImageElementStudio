import AppKit
import Foundation
import Vision

enum ImageAnalyzerError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "The selected image could not be converted for analysis."
        }
    }
}

struct ImageAnalyzer {
    func analyze(cgImage: CGImage, filename: String) async throws -> AnalysisDocument {
        try await Task.detached(priority: .userInitiated) {
            try Self.analyzeSync(cgImage: cgImage, filename: filename)
        }.value
    }

    private static func analyzeSync(cgImage: CGImage, filename: String) throws -> AnalysisDocument {
        let width = cgImage.width
        let height = cgImage.height
        let imageSize = CGSize(width: width, height: height)

        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.minimumTextHeight = 0.008

        let rectangleRequest = VNDetectRectanglesRequest()
        rectangleRequest.maximumObservations = 80
        rectangleRequest.minimumAspectRatio = 0.12
        rectangleRequest.minimumSize = 0.02
        rectangleRequest.minimumConfidence = 0.35

        try requestHandler.perform([textRequest, rectangleRequest])

        var elements: [CanvasElement] = [
            CanvasElement.root(width: width, height: height, filename: filename),
        ]

        let textElements = buildTextElements(
            observations: textRequest.results ?? [],
            imageSize: imageSize
        )
        elements.append(contentsOf: textElements)

        let shapeElements = buildShapeElements(
            observations: rectangleRequest.results ?? [],
            imageSize: imageSize,
            existingTextFrames: textElements.map(\.frame)
        )
        elements.append(contentsOf: shapeElements)

        let artboard = Artboard(
            id: UUID(),
            name: "Detected Artboard",
            width: width,
            height: height,
            elements: stableSort(elements)
        )

        return AnalysisDocument(
            image: ImageDescriptor(
                filename: filename,
                width: width,
                height: height
            ),
            artboard: artboard,
            metadata: AnalysisMetadata(
                generatedAt: Date(),
                engine: "Vision OCR + Rectangle Heuristics",
                notes: [
                    "Coordinates are pixel-based with origin at top-left.",
                    "OCR fragments are merged into line-level text elements for cleaner semantic mapping.",
                    "Shapes overlapping text blocks are filtered to reduce duplicates.",
                ]
            ),
            scope: nil,
            blueprint: nil
        )
    }

    private static func buildTextElements(
        observations: [VNRecognizedTextObservation],
        imageSize: CGSize
    ) -> [CanvasElement] {
        let fragments: [TextFragment] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }

            let frame = pixelFrame(from: observation.boundingBox, imageSize: imageSize)
            guard frame.width > 12, frame.height > 8 else { return nil }

            return TextFragment(
                text: text,
                frame: frame,
                confidence: Double(observation.confidence)
            )
        }

        let merged = deduplicateTextFragments(mergeTextFragmentsIntoLines(fragments))

        return merged.enumerated().map { index, fragment in
            CanvasElement(
                id: UUID(),
                name: textElementName(fragment.text, fallbackIndex: index),
                kind: .text,
                frame: fragment.frame,
                confidence: fragment.confidence,
                content: fragment.text,
                tags: ["ocr", "text-line"],
                semanticRole: .unknown,
                semanticReason: nil
            )
        }
    }

    private static func buildShapeElements(
        observations: [VNRectangleObservation],
        imageSize: CGSize,
        existingTextFrames: [ElementFrame]
    ) -> [CanvasElement] {
        observations.enumerated().compactMap { index, observation in
            let frame = pixelFrame(from: observation.boundingBox, imageSize: imageSize)
            guard frame.width > 24, frame.height > 24 else { return nil }

            let isTextContainer = existingTextFrames.contains { textFrame in
                overlapRatio(between: frame, and: textFrame) > 0.72
            }
            guard !isTextContainer else { return nil }

            return CanvasElement(
                id: UUID(),
                name: "Shape \(index + 1)",
                kind: .shape,
                frame: frame,
                confidence: Double(observation.confidence),
                content: nil,
                tags: ["vision-rectangle"],
                semanticRole: .unknown,
                semanticReason: nil
            )
        }
    }

    private static func pixelFrame(from normalized: CGRect, imageSize: CGSize) -> ElementFrame {
        let x = normalized.origin.x * imageSize.width
        let y = (1 - normalized.origin.y - normalized.height) * imageSize.height
        let width = normalized.width * imageSize.width
        let height = normalized.height * imageSize.height

        return ElementFrame(
            x: Double(max(0, x)),
            y: Double(max(0, y)),
            width: Double(max(0, width)),
            height: Double(max(0, height))
        )
    }

    private static func overlapRatio(between a: ElementFrame, and b: ElementFrame) -> Double {
        let left = max(a.x, b.x)
        let right = min(a.x + a.width, b.x + b.width)
        let top = max(a.y, b.y)
        let bottom = min(a.y + a.height, b.y + b.height)

        guard right > left, bottom > top else { return 0 }

        let intersection = (right - left) * (bottom - top)
        let area = max(1, min(a.width * a.height, b.width * b.height))
        return intersection / area
    }

    private static func stableSort(_ elements: [CanvasElement]) -> [CanvasElement] {
        elements.sorted { lhs, rhs in
            if lhs.frame.y != rhs.frame.y {
                return lhs.frame.y < rhs.frame.y
            }
            if lhs.frame.x != rhs.frame.x {
                return lhs.frame.x < rhs.frame.x
            }
            return lhs.name < rhs.name
        }
    }

    private static func mergeTextFragmentsIntoLines(_ fragments: [TextFragment]) -> [TextFragment] {
        guard !fragments.isEmpty else { return [] }

        var lineBuckets: [[TextFragment]] = []
        let sorted = fragments.sorted { lhs, rhs in
            if lhs.frame.y != rhs.frame.y {
                return lhs.frame.y < rhs.frame.y
            }
            return lhs.frame.x < rhs.frame.x
        }

        for fragment in sorted {
            if let lineIndex = lineBuckets.firstIndex(where: { bucket in
                guard let anchor = bucket.last else { return false }
                return isLikelySameLine(fragment, anchor)
            }) {
                lineBuckets[lineIndex].append(fragment)
            } else {
                lineBuckets.append([fragment])
            }
        }

        var merged: [TextFragment] = []
        for bucket in lineBuckets {
            let sortedLine = bucket.sorted { $0.frame.x < $1.frame.x }
            guard var current = sortedLine.first else { continue }

            for fragment in sortedLine.dropFirst() {
                let gap = fragment.frame.x - (current.frame.x + current.frame.width)
                let averageHeight = (current.frame.height + fragment.frame.height) / 2
                let verticalOverlap = verticalOverlapRatio(current.frame, fragment.frame)
                let mergeThreshold = max(10.0, averageHeight * 1.15)

                if verticalOverlap > 0.45, gap <= mergeThreshold {
                    current = merge(current, with: fragment, includeSpace: gap > 2)
                } else {
                    merged.append(current)
                    current = fragment
                }
            }
            merged.append(current)
        }

        return merged
    }

    private static func deduplicateTextFragments(_ fragments: [TextFragment]) -> [TextFragment] {
        let ranked = fragments.sorted { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }
            let leftArea = lhs.frame.width * lhs.frame.height
            let rightArea = rhs.frame.width * rhs.frame.height
            return leftArea > rightArea
        }

        var accepted: [TextFragment] = []
        for fragment in ranked {
            let duplicateExists = accepted.contains { existing in
                normalize(fragment.text) == normalize(existing.text)
                    && overlapRatio(between: fragment.frame, and: existing.frame) > 0.82
            }
            if !duplicateExists {
                accepted.append(fragment)
            }
        }

        return accepted.sorted { lhs, rhs in
            if lhs.frame.y != rhs.frame.y {
                return lhs.frame.y < rhs.frame.y
            }
            return lhs.frame.x < rhs.frame.x
        }
    }

    private static func textElementName(_ text: String, fallbackIndex: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Text \(fallbackIndex + 1)" }

        if trimmed.count <= 30 {
            return trimmed
        }

        return "\(trimmed.prefix(27))..."
    }

    private static func isLikelySameLine(_ lhs: TextFragment, _ rhs: TextFragment) -> Bool {
        let leftCenter = lhs.frame.y + (lhs.frame.height / 2)
        let rightCenter = rhs.frame.y + (rhs.frame.height / 2)
        let centerDelta = abs(leftCenter - rightCenter)
        let tolerance = max(7.0, min(lhs.frame.height, rhs.frame.height) * 0.7)

        return centerDelta <= tolerance && verticalOverlapRatio(lhs.frame, rhs.frame) > 0.35
    }

    private static func merge(_ lhs: TextFragment, with rhs: TextFragment, includeSpace: Bool) -> TextFragment {
        let separator = includeSpace ? " " : ""
        let combinedText = (lhs.text + separator + rhs.text)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let union = unionFrame(lhs.frame, rhs.frame)
        let confidence = min(1.0, max(0.0, (lhs.confidence + rhs.confidence) / 2))

        return TextFragment(
            text: combinedText.isEmpty ? lhs.text : combinedText,
            frame: union,
            confidence: confidence
        )
    }

    private static func unionFrame(_ lhs: ElementFrame, _ rhs: ElementFrame) -> ElementFrame {
        let minX = min(lhs.x, rhs.x)
        let minY = min(lhs.y, rhs.y)
        let maxX = max(lhs.x + lhs.width, rhs.x + rhs.width)
        let maxY = max(lhs.y + lhs.height, rhs.y + rhs.height)

        return ElementFrame(
            x: minX,
            y: minY,
            width: max(0, maxX - minX),
            height: max(0, maxY - minY)
        )
    }

    private static func verticalOverlapRatio(_ lhs: ElementFrame, _ rhs: ElementFrame) -> Double {
        let top = max(lhs.y, rhs.y)
        let bottom = min(lhs.y + lhs.height, rhs.y + rhs.height)
        guard bottom > top else { return 0 }

        let overlap = bottom - top
        let base = max(1, min(lhs.frameHeight, rhs.frameHeight))
        return overlap / base
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct TextFragment {
        var text: String
        var frame: ElementFrame
        var confidence: Double
    }
}

private extension ElementFrame {
    var frameHeight: Double {
        max(0, height)
    }
}

extension NSImage {
    var resolvedCGImage: CGImage? {
        var proposedRect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }
}
