import AppKit
import Foundation
import PDFKit
import QuickLookThumbnailing

struct ImportedDesignAsset {
    var filename: String
    var image: NSImage?
    var document: AnalysisDocument?
    var importLossReport: ImportLossReport?
    var notes: [String]
}

enum DesignAssetImporterError: LocalizedError {
    case unsupported(String)
    case unreadable

    var errorDescription: String? {
        switch self {
        case let .unsupported(message):
            return message
        case .unreadable:
            return "Could not read the selected design file."
        }
    }
}

struct DesignAssetImporter {
    func importAsset(from url: URL) async throws -> ImportedDesignAsset {
        let extensionName = url.pathExtension.lowercased()
        let filename = url.lastPathComponent

        if let image = NSImage(contentsOf: url), image.resolvedCGImage != nil {
            return ImportedDesignAsset(
                filename: filename,
                image: image,
                document: nil,
                importLossReport: nil,
                notes: ["Loaded raster image source."]
            )
        }

        if ["pdf", "ai", "eps"].contains(extensionName), let image = renderPDFLikeAsset(from: url) {
            return ImportedDesignAsset(
                filename: filename,
                image: image,
                document: nil,
                importLossReport: nil,
                notes: ["Imported \(extensionName.uppercased()) as rendered vector preview."]
            )
        }

        if ["fig", "json"].contains(extensionName),
           let structured = try? parseStructuredDesign(from: url) {
            return ImportedDesignAsset(
                filename: filename,
                image: renderStructuredPreview(for: structured.document.artboard),
                document: structured.document,
                importLossReport: structured.report,
                notes: ["Parsed structured design nodes from \(extensionName.uppercased()) file."]
            )
        }

        if let thumbnail = try? await quickLookThumbnail(from: url) {
            return ImportedDesignAsset(
                filename: filename,
                image: thumbnail,
                document: nil,
                importLossReport: nil,
                notes: ["Rendered preview using QuickLook for \(extensionName.isEmpty ? "file" : extensionName.uppercased())."]
            )
        }

        throw DesignAssetImporterError.unsupported(
            "Unsupported design file format. Try PNG/JPG/PDF/AI/SVG/FIG/JSON or export from design tool as image/PDF."
        )
    }

    private func renderPDFLikeAsset(from url: URL) -> NSImage? {
        if let document = PDFDocument(url: url), let page = document.page(at: 0) {
            let mediaBounds = page.bounds(for: .mediaBox)
            let width = max(300, min(3200, Int(mediaBounds.width)))
            let height = max(200, min(3200, Int(mediaBounds.height)))
            let size = CGSize(width: width, height: height)
            return page.thumbnail(of: size, for: .mediaBox)
        }

        return NSImage(contentsOf: url)
    }

    private func quickLookThumbnail(from url: URL) async throws -> NSImage {
        try await withCheckedThrowingContinuation { continuation in
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: 2400, height: 2400),
                scale: NSScreen.main?.backingScaleFactor ?? 2,
                representationTypes: .all
            )
            request.iconMode = false

            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, error in
                if let image = representation?.nsImage {
                    continuation.resume(returning: image)
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume(throwing: DesignAssetImporterError.unreadable)
            }
        }
    }

    private func parseStructuredDesign(from url: URL) throws -> StructuredImportResult {
        let data = try Data(contentsOf: url)
        let rootObject = try JSONSerialization.jsonObject(with: data)

        var stats = ParseStats()
        var collectedNodes: [ParsedNode] = []
        walkNodes(rootObject, parentNodeID: nil, collectedNodes: &collectedNodes, stats: &stats, depth: 0)

        guard !collectedNodes.isEmpty else {
            throw DesignAssetImporterError.unsupported("Structured file contains no parseable design nodes.")
        }

        var minX = collectedNodes.map { $0.frame.x }.min() ?? 0
        var minY = collectedNodes.map { $0.frame.y }.min() ?? 0
        minX = min(minX, 0)
        minY = min(minY, 0)

        if minX < 0 || minY < 0 {
            for index in collectedNodes.indices {
                collectedNodes[index].frame.x -= minX
                collectedNodes[index].frame.y -= minY
            }
        }

        let maxX = collectedNodes.map { $0.frame.x + $0.frame.width }.max() ?? 1366
        let maxY = collectedNodes.map { $0.frame.y + $0.frame.height }.max() ?? 768

        let boardWidth = Int(max(360, min(3840, ceil(maxX))))
        let boardHeight = Int(max(640, min(3840, ceil(maxY))))

        var elements: [CanvasElement] = [
            CanvasElement.root(width: boardWidth, height: boardHeight, filename: url.lastPathComponent),
        ]

        let sortedNodes = collectedNodes.sorted { lhs, rhs in
            if lhs.frame.y != rhs.frame.y {
                return lhs.frame.y < rhs.frame.y
            }
            if lhs.frame.x != rhs.frame.x {
                return lhs.frame.x < rhs.frame.x
            }
            return lhs.name < rhs.name
        }

        let mappedNodes = Array(sortedNodes.prefix(450))
        let nodeIDToElementID = Dictionary(uniqueKeysWithValues: mappedNodes.map { ($0.sourceNodeID, UUID()) })

        for node in mappedNodes {
            let content: String?
            if node.kind == .text {
                content = node.text ?? node.name
            } else {
                content = nil
            }

            var tags = node.tags
            tags.append("depth:\(node.depth)")
            if node.parentNodeID != nil {
                tags.append("hierarchy:child")
            } else {
                tags.append("hierarchy:root")
            }

            elements.append(
                CanvasElement(
                    id: nodeIDToElementID[node.sourceNodeID] ?? UUID(),
                    name: node.name,
                    kind: node.kind,
                    frame: node.frame,
                    confidence: node.confidence,
                    content: content,
                    tags: tags,
                    semanticRole: .unknown,
                    semanticReason: "Structured design import",
                    parentElementID: node.parentNodeID.flatMap { nodeIDToElementID[$0] },
                    style: node.style
                )
            )
        }

        let artboard = Artboard(
            id: UUID(),
            name: "Imported \(url.deletingPathExtension().lastPathComponent)",
            width: boardWidth,
            height: boardHeight,
            elements: elements
        )

        let document = AnalysisDocument(
            image: ImageDescriptor(
                filename: url.lastPathComponent,
                width: boardWidth,
                height: boardHeight
            ),
            artboard: artboard,
            metadata: AnalysisMetadata(
                generatedAt: Date(),
                engine: "Structured Design Import",
                notes: [
                    "Imported \(sortedNodes.count) design nodes from structured file.",
                    "Coordinates normalized to top-left origin with pixel units.",
                ]
            ),
            scope: nil,
            blueprint: nil
        )

        let report = buildLossReport(
            sourceFilename: url.lastPathComponent,
            totalNodeCount: sortedNodes.count,
            mappedNodes: mappedNodes,
            stats: stats
        )

        return StructuredImportResult(document: document, report: report)
    }

    private func walkNodes(
        _ any: Any,
        parentNodeID: String?,
        collectedNodes: inout [ParsedNode],
        stats: inout ParseStats,
        depth: Int
    ) {
        guard depth < 40 else { return }

        if let dictionary = any as? [String: Any] {
            stats.totalObjects += 1
            if let node = parseNode(from: dictionary, parentNodeID: parentNodeID, depth: depth) {
                collectedNodes.append(node)
                stats.parsedNodes += 1
                if node.style == nil {
                    stats.nodesMissingStyle += 1
                }
                if depth > 8 {
                    stats.deepHierarchyNodeCount += 1
                }
            }

            let nextParentID = stringValue(from: dictionary["id"]) ?? stringValue(from: dictionary["name"])
            for key in ["children", "layers", "items"] {
                if let array = dictionary[key] as? [Any] {
                    for child in array {
                        walkNodes(
                            child,
                            parentNodeID: nextParentID ?? parentNodeID,
                            collectedNodes: &collectedNodes,
                            stats: &stats,
                            depth: depth + 1
                        )
                    }
                }
            }

            if let dictionaryNodes = dictionary["nodes"] as? [String: Any] {
                for value in dictionaryNodes.values {
                    walkNodes(
                        value,
                        parentNodeID: nextParentID ?? parentNodeID,
                        collectedNodes: &collectedNodes,
                        stats: &stats,
                        depth: depth + 1
                    )
                }
            }
            return
        }

        if let array = any as? [Any] {
            for value in array {
                walkNodes(
                    value,
                    parentNodeID: parentNodeID,
                    collectedNodes: &collectedNodes,
                    stats: &stats,
                    depth: depth + 1
                )
            }
        }
    }

    private func parseNode(from dictionary: [String: Any], parentNodeID: String?, depth: Int) -> ParsedNode? {
        guard let frame = parseFrame(from: dictionary), frame.width > 1, frame.height > 1 else {
            return nil
        }

        let rawType = stringValue(from: dictionary["type"]) ?? stringValue(from: dictionary["nodeType"]) ?? "LAYER"
        let normalizedType = rawType.uppercased()
        let sourceNodeID = stringValue(from: dictionary["id"]) ?? UUID().uuidString
        let name = (stringValue(from: dictionary["name"]) ?? stringValue(from: dictionary["id"]) ?? "Layer")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let characters = stringValue(from: dictionary["characters"])
            ?? stringValue(from: dictionary["text"])
            ?? stringValue(from: dictionary["content"])

        let isText = normalizedType.contains("TEXT") || characters != nil
        let kind: ElementKind = isText ? .text : .shape
        let confidence: Double = isText ? 0.86 : 0.78

        var tags = ["structured-import", "type:\(normalizedType.lowercased())"]
        if let role = stringValue(from: dictionary["role"])?.lowercased() {
            tags.append("role:\(role)")
        }
        tags.append("depth:\(depth)")

        let cleanedName: String = {
            if !name.isEmpty {
                return name.count > 50 ? "\(name.prefix(47))..." : name
            }
            if let characters, !characters.isEmpty {
                return characters.count > 50 ? "\(characters.prefix(47))..." : characters
            }
            return kind == .text ? "Text Layer" : "Shape Layer"
        }()

        return ParsedNode(
            sourceNodeID: sourceNodeID,
            parentNodeID: parentNodeID,
            depth: depth,
            name: cleanedName,
            kind: kind,
            frame: frame,
            text: characters,
            confidence: confidence,
            tags: tags,
            style: parseVisualStyle(from: dictionary, nodeKind: kind)
        )
    }

    private func parseFrame(from dictionary: [String: Any]) -> ElementFrame? {
        if let bbox = dictionary["absoluteBoundingBox"] as? [String: Any],
           let frame = directFrame(from: bbox) {
            return frame
        }

        if let frameDict = dictionary["frame"] as? [String: Any],
           let frame = directFrame(from: frameDict) {
            return frame
        }

        if let bounds = dictionary["bounds"] as? [String: Any],
           let frame = directFrame(from: bounds) {
            return frame
        }

        return directFrame(from: dictionary)
    }

    private func directFrame(from dictionary: [String: Any]) -> ElementFrame? {
        guard let x = numberValue(from: dictionary["x"]),
              let y = numberValue(from: dictionary["y"]),
              let width = numberValue(from: dictionary["width"]),
              let height = numberValue(from: dictionary["height"]) else {
            return nil
        }

        return ElementFrame(
            x: max(0, x),
            y: max(0, y),
            width: max(0, width),
            height: max(0, height)
        )
    }

    private func numberValue(from any: Any?) -> Double? {
        if let value = any as? Double { return value }
        if let value = any as? CGFloat { return Double(value) }
        if let value = any as? Int { return Double(value) }
        if let value = any as? NSNumber { return value.doubleValue }
        if let value = any as? String { return Double(value) }
        return nil
    }

    private func stringValue(from any: Any?) -> String? {
        if let value = any as? String { return value }
        return nil
    }

    private func parseVisualStyle(from dictionary: [String: Any], nodeKind: ElementKind) -> ElementVisualStyle? {
        var fillColor: String?
        var fillGradient: String?
        var strokeColor: String?
        var strokeWidth: Double?

        if let fills = dictionary["fills"] as? [[String: Any]], let first = fills.first {
            if let colorDict = first["color"] as? [String: Any] {
                fillColor = hexColor(fromRGBA: colorDict)
            }
            if let gradientType = stringValue(from: first["gradientType"]) {
                fillGradient = gradientType
            }
        } else if let color = stringValue(from: dictionary["fill"]) {
            fillColor = normalizedColorString(color)
        }

        if let strokes = dictionary["strokes"] as? [[String: Any]], let first = strokes.first {
            if let colorDict = first["color"] as? [String: Any] {
                strokeColor = hexColor(fromRGBA: colorDict)
            }
            strokeWidth = numberValue(from: first["weight"]) ?? numberValue(from: dictionary["strokeWeight"])
        } else if let stroke = stringValue(from: dictionary["stroke"]) {
            strokeColor = normalizedColorString(stroke)
            strokeWidth = numberValue(from: dictionary["strokeWidth"])
        }

        let cornerRadius = numberValue(from: dictionary["cornerRadius"]) ?? numberValue(from: dictionary["radius"])
        let opacity = numberValue(from: dictionary["opacity"])

        let typography: ElementTypographyStyle?
        if nodeKind == .text {
            if let style = dictionary["style"] as? [String: Any] {
                typography = ElementTypographyStyle(
                    family: stringValue(from: style["fontFamily"]),
                    weight: stringValue(from: style["fontWeight"]) ?? stringValue(from: style["fontPostScriptName"]),
                    size: numberValue(from: style["fontSize"]),
                    lineHeight: numberValue(from: style["lineHeightPx"]) ?? numberValue(from: style["lineHeight"]),
                    letterSpacing: numberValue(from: style["letterSpacing"])
                )
            } else {
                typography = ElementTypographyStyle(
                    family: stringValue(from: dictionary["fontFamily"]),
                    weight: stringValue(from: dictionary["fontWeight"]),
                    size: numberValue(from: dictionary["fontSize"]),
                    lineHeight: numberValue(from: dictionary["lineHeight"]),
                    letterSpacing: numberValue(from: dictionary["letterSpacing"])
                )
            }
        } else {
            typography = nil
        }

        let style = ElementVisualStyle(
            fill: (fillColor == nil && fillGradient == nil) ? nil : ElementFillStyle(color: fillColor, gradient: fillGradient),
            stroke: (strokeColor == nil && strokeWidth == nil) ? nil : ElementStrokeStyle(color: strokeColor, width: strokeWidth),
            cornerRadius: cornerRadius,
            opacity: opacity,
            typography: typography
        )

        let hasValue = style.fill != nil
            || style.stroke != nil
            || style.cornerRadius != nil
            || style.opacity != nil
            || style.typography != nil
        return hasValue ? style : nil
    }

    private func normalizedColorString(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#"), trimmed.count == 7 {
            return trimmed.uppercased()
        }
        return trimmed
    }

    private func hexColor(fromRGBA dictionary: [String: Any]) -> String? {
        let red = numberValue(from: dictionary["r"]) ?? 0
        let green = numberValue(from: dictionary["g"]) ?? 0
        let blue = numberValue(from: dictionary["b"]) ?? 0

        let maxComponent = max(red, max(green, blue))
        let scale = maxComponent <= 1.0 ? 255.0 : 1.0

        let r = max(0, min(255, Int((red * scale).rounded())))
        let g = max(0, min(255, Int((green * scale).rounded())))
        let b = max(0, min(255, Int((blue * scale).rounded())))
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func buildLossReport(
        sourceFilename: String,
        totalNodeCount: Int,
        mappedNodes: [ParsedNode],
        stats: ParseStats
    ) -> ImportLossReport {
        let mappedCount = mappedNodes.count
        let truncated = max(0, totalNodeCount - mappedCount)
        let styleMissing = mappedNodes.filter { $0.style == nil }.count
        let parentLinksMissing = mappedNodes.filter { $0.parentNodeID != nil && $0.depth > 0 }.count

        var lossItems: [ImportLossItem] = []

        if truncated > 0 {
            lossItems.append(
                ImportLossItem(
                    id: UUID(),
                    category: "Node Truncation",
                    detail: "\(truncated) nodes were not imported due to current 450-node cap.",
                    severity: .high,
                    affectedElementCount: truncated
                )
            )
        }

        if styleMissing > 0 {
            lossItems.append(
                ImportLossItem(
                    id: UUID(),
                    category: "Style Fidelity",
                    detail: "\(styleMissing) mapped nodes are missing explicit fill/stroke/typography style metadata.",
                    severity: styleMissing > max(20, mappedCount / 2) ? .high : .medium,
                    affectedElementCount: styleMissing
                )
            )
        }

        if stats.deepHierarchyNodeCount > 0 {
            lossItems.append(
                ImportLossItem(
                    id: UUID(),
                    category: "Hierarchy Depth",
                    detail: "\(stats.deepHierarchyNodeCount) nodes were nested deeper than 8 levels and may need manual regrouping.",
                    severity: .low,
                    affectedElementCount: stats.deepHierarchyNodeCount
                )
            )
        }

        if parentLinksMissing > 0 {
            lossItems.append(
                ImportLossItem(
                    id: UUID(),
                    category: "Group Structure",
                    detail: "Imported nodes include \(parentLinksMissing) child layers that may need additional grouping cleanup.",
                    severity: .medium,
                    affectedElementCount: parentLinksMissing
                )
            )
        }

        if lossItems.isEmpty {
            lossItems.append(
                ImportLossItem(
                    id: UUID(),
                    category: "Fidelity",
                    detail: "No significant structural losses detected in structured import.",
                    severity: .low,
                    affectedElementCount: 0
                )
            )
        }

        let truncationPercent = Double(truncated) / Double(max(1, totalNodeCount)) * 100
        let stylePercent = Double(styleMissing) / Double(max(1, mappedCount)) * 18
        let hierarchyPercent = Double(stats.deepHierarchyNodeCount) / Double(max(1, mappedCount)) * 8
        let estimatedCleanup = min(95, max(2, truncationPercent + stylePercent + hierarchyPercent))

        return ImportLossReport(
            sourceFilename: sourceFilename,
            importedAt: Date(),
            totalNodeCount: totalNodeCount,
            successfullyMappedCount: mappedCount,
            lossItems: lossItems,
            estimatedManualCleanupPercent: estimatedCleanup
        )
    }

    private func renderStructuredPreview(for artboard: Artboard) -> NSImage {
        let sourceWidth = max(1, artboard.width)
        let sourceHeight = max(1, artboard.height)
        let maxDimension = 2400.0
        let scale = min(1.0, maxDimension / Double(max(sourceWidth, sourceHeight)))
        let width = max(1, Int(Double(sourceWidth) * scale))
        let height = max(1, Int(Double(sourceHeight) * scale))
        let targetSize = NSSize(width: width, height: height)

        let image = NSImage(size: targetSize)
        image.lockFocus()

        NSColor(white: 0.1, alpha: 1.0).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: targetSize)).fill()

        let xScale = Double(width) / Double(sourceWidth)
        let yScale = Double(height) / Double(sourceHeight)

        for element in artboard.elements.prefix(260) where element.kind != .imageRoot {
            let rect = NSRect(
                x: element.frame.x * xScale,
                y: (Double(height) - ((element.frame.y + element.frame.height) * yScale)),
                width: max(1, element.frame.width * xScale),
                height: max(1, element.frame.height * yScale)
            )

            let strokeColor: NSColor = element.kind == .text ? NSColor.systemGreen : NSColor.systemOrange
            strokeColor.withAlphaComponent(0.95).setStroke()
            strokeColor.withAlphaComponent(0.12).setFill()
            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            path.lineWidth = 1.0
            path.fill()
            path.stroke()

            if element.kind == .text, let content = element.content, !content.isEmpty {
                let clipped = content.count > 40 ? "\(content.prefix(37))..." : content
                clipped.draw(
                    in: rect.insetBy(dx: 3, dy: 2),
                    withAttributes: [
                        .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                        .foregroundColor: NSColor.white,
                    ]
                )
            }
        }

        image.unlockFocus()
        return image
    }

    private struct ParsedNode {
        var sourceNodeID: String
        var parentNodeID: String?
        var depth: Int
        var name: String
        var kind: ElementKind
        var frame: ElementFrame
        var text: String?
        var confidence: Double
        var tags: [String]
        var style: ElementVisualStyle?
    }

    private struct ParseStats {
        var totalObjects: Int = 0
        var parsedNodes: Int = 0
        var nodesMissingStyle: Int = 0
        var deepHierarchyNodeCount: Int = 0
    }

    private struct StructuredImportResult {
        var document: AnalysisDocument
        var report: ImportLossReport
    }
}
