import Foundation

enum ElementKind: String, Codable, CaseIterable, Hashable {
    case imageRoot
    case text
    case shape
}

enum SemanticElementRole: String, Codable, CaseIterable, Hashable {
    case unknown
    case appBrand
    case navigationItem
    case navigationSection
    case heading
    case sectionTitle
    case metricValue
    case metricLabel
    case metricDelta
    case chart
    case chartAxis
    case tableHeader
    case tableCell
    case buttonPrimary
    case buttonSecondary
    case dateFilter
    case avatar
    case tag
    case panel
    case listItem
}

struct ElementFrame: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

enum ConstraintPin: String, Codable, CaseIterable, Hashable, Identifiable {
    case left
    case right
    case top
    case bottom
    case centerX
    case centerY
    case fixedWidth
    case fixedHeight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left:
            return "Left"
        case .right:
            return "Right"
        case .top:
            return "Top"
        case .bottom:
            return "Bottom"
        case .centerX:
            return "Center X"
        case .centerY:
            return "Center Y"
        case .fixedWidth:
            return "Fixed Width"
        case .fixedHeight:
            return "Fixed Height"
        }
    }
}

struct ElementTypographyStyle: Codable, Hashable {
    var family: String?
    var weight: String?
    var size: Double?
    var lineHeight: Double?
    var letterSpacing: Double?
}

struct ElementStrokeStyle: Codable, Hashable {
    var color: String?
    var width: Double?
}

struct ElementFillStyle: Codable, Hashable {
    var color: String?
    var gradient: String?
}

struct ElementVisualStyle: Codable, Hashable {
    var fill: ElementFillStyle?
    var stroke: ElementStrokeStyle?
    var cornerRadius: Double?
    var opacity: Double?
    var typography: ElementTypographyStyle?
}

struct CanvasElement: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var kind: ElementKind
    var frame: ElementFrame
    var confidence: Double
    var content: String?
    var tags: [String]
    var semanticRole: SemanticElementRole?
    var semanticReason: String?
    var rotationDegrees: Double
    var constraints: [ConstraintPin]
    var parentElementID: UUID?
    var componentReferenceID: UUID?
    var instanceOverrides: [String: String]
    var style: ElementVisualStyle?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case kind
        case frame
        case confidence
        case content
        case tags
        case semanticRole
        case semanticReason
        case rotationDegrees
        case constraints
        case parentElementID
        case componentReferenceID
        case instanceOverrides
        case style
    }

    init(
        id: UUID,
        name: String,
        kind: ElementKind,
        frame: ElementFrame,
        confidence: Double,
        content: String?,
        tags: [String],
        semanticRole: SemanticElementRole?,
        semanticReason: String?,
        rotationDegrees: Double = 0,
        constraints: [ConstraintPin] = [],
        parentElementID: UUID? = nil,
        componentReferenceID: UUID? = nil,
        instanceOverrides: [String: String] = [:],
        style: ElementVisualStyle? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.frame = frame
        self.confidence = confidence
        self.content = content
        self.tags = tags
        self.semanticRole = semanticRole
        self.semanticReason = semanticReason
        self.rotationDegrees = rotationDegrees
        self.constraints = constraints
        self.parentElementID = parentElementID
        self.componentReferenceID = componentReferenceID
        self.instanceOverrides = instanceOverrides
        self.style = style
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(ElementKind.self, forKey: .kind)
        frame = try container.decode(ElementFrame.self, forKey: .frame)
        confidence = try container.decode(Double.self, forKey: .confidence)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        semanticRole = try container.decodeIfPresent(SemanticElementRole.self, forKey: .semanticRole)
        semanticReason = try container.decodeIfPresent(String.self, forKey: .semanticReason)
        rotationDegrees = try container.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0
        constraints = try container.decodeIfPresent([ConstraintPin].self, forKey: .constraints) ?? []
        parentElementID = try container.decodeIfPresent(UUID.self, forKey: .parentElementID)
        componentReferenceID = try container.decodeIfPresent(UUID.self, forKey: .componentReferenceID)
        instanceOverrides = try container.decodeIfPresent([String: String].self, forKey: .instanceOverrides) ?? [:]
        style = try container.decodeIfPresent(ElementVisualStyle.self, forKey: .style)
    }
}

struct Artboard: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var width: Int
    var height: Int
    var elements: [CanvasElement]
}

extension CanvasElement {
    static func root(width: Int, height: Int, filename: String?) -> CanvasElement {
        CanvasElement(
            id: UUID(),
            name: "Canvas Root",
            kind: .imageRoot,
            frame: ElementFrame(x: 0, y: 0, width: Double(width), height: Double(height)),
            confidence: 1.0,
            content: filename,
            tags: ["root", "canvas"],
            semanticRole: .unknown,
            semanticReason: "Canvas bounds"
        )
    }
}

extension Artboard {
    static func empty(named name: String = "Main Artboard", width: Int = 1280, height: Int = 720, filename: String? = nil) -> Artboard {
        Artboard(
            id: UUID(),
            name: name,
            width: width,
            height: height,
            elements: [CanvasElement.root(width: width, height: height, filename: filename)]
        )
    }
}

extension ElementFrame {
    var minX: Double { x }
    var maxX: Double { x + width }
    var minY: Double { y }
    var maxY: Double { y + height }
    var midX: Double { x + width / 2 }
    var midY: Double { y + height / 2 }

    func intersects(_ other: ElementFrame) -> Bool {
        !(other.maxX < minX || other.minX > maxX || other.maxY < minY || other.minY > maxY)
    }
}
