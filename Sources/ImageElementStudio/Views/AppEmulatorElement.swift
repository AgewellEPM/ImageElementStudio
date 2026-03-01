import SwiftUI

struct AppEmulatorElement: View {
    let element: CanvasElement
    let rect: CGRect
    let palette: EmulatorTokenPalette
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            elementBackground
            if let overlayText {
                Text(overlayText)
                    .font(textFont)
                    .foregroundStyle(textColor)
                    .lineLimit(textLineLimit)
                    .minimumScaleFactor(0.7)
                    .padding(textPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: textAlignment)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .rotationEffect(.degrees(element.rotationDegrees))
        .position(x: rect.midX, y: rect.midY)
        .opacity(styleOpacity)
        .shadow(color: elementShadowColor, radius: elementShadowRadius, x: 0, y: elementShadowYOffset)
        .overlay(
            ZStack {
                if let styleStrokeColor {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(styleStrokeColor, lineWidth: styleStrokeWidth)
                }
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(isSelected ? palette.accentPrimary : Color.clear, lineWidth: 2.2)
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }

    @ViewBuilder
    private var elementBackground: some View {
        let role = semanticRole
        let rounded = RoundedRectangle(cornerRadius: cornerRadius)

        if let styleFillColor {
            rounded.fill(styleFillColor)
        } else {
            switch role {
            case .buttonPrimary:
                rounded.fill(
                    LinearGradient(
                        colors: [palette.accentPrimary, palette.accentSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            case .buttonSecondary, .dateFilter:
                rounded.fill(palette.surfaceElevated)
            case .navigationItem:
                rounded.fill(palette.surfaceNav)
            case .navigationSection:
                rounded.fill(Color.clear)
            case .chart:
                rounded
                    .fill(
                        LinearGradient(
                            colors: [palette.accentSoft, palette.accentPrimary.opacity(0.22)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            case .tableHeader:
                rounded.fill(palette.surfaceElevated)
            case .tableCell:
                rounded.fill(palette.surfaceBase)
            case .panel:
                rounded.fill(palette.surfacePanel)
            default:
                if element.kind == .shape {
                    rounded.fill(palette.surfaceBase)
                } else {
                    rounded.fill(Color.clear)
                }
            }
        }
    }

    private var semanticRole: SemanticElementRole {
        element.semanticRole ?? .unknown
    }

    private var overlayText: String? {
        guard rect.width > 20, rect.height > 12 else { return nil }

        let source = element.content?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let source, !source.isEmpty {
            if source.count <= 42 {
                return source
            }
            return "\(source.prefix(39))..."
        }

        if element.kind == .text {
            return element.name
        }

        switch semanticRole {
        case .chart:
            return "Chart"
        case .tableHeader:
            return "Header"
        case .panel:
            return "Panel"
        default:
            return nil
        }
    }

    private var textFont: Font {
        if let explicitSize = element.style?.typography?.size {
            return .system(
                size: cappedSize(base: CGFloat(explicitSize), min: 8, max: 46),
                weight: .medium,
                design: .rounded
            )
        }
        if semanticRole == .heading {
            return .system(
                size: cappedSize(base: rect.height * 0.56 * palette.titleScale, min: 11, max: 34),
                weight: .semibold,
                design: .rounded
            )
        }
        if semanticRole == .metricValue {
            return .system(
                size: cappedSize(base: rect.height * 0.6 * palette.metricScale, min: 11, max: 42),
                weight: .bold,
                design: .rounded
            )
        }
        if semanticRole == .navigationSection {
            return .system(size: cappedSize(base: rect.height * 0.45 * palette.bodyScale, min: 9, max: 16), weight: .semibold)
        }
        return .system(
            size: cappedSize(base: rect.height * 0.45 * palette.bodyScale, min: 9, max: 20),
            weight: .medium,
            design: .rounded
        )
    }

    private var textColor: Color {
        if semanticRole == .buttonPrimary {
            return palette.textInverse
        }
        if semanticRole == .navigationSection {
            return palette.textSecondary
        }
        if semanticRole == .navigationItem {
            return palette.textSecondary
        }
        return palette.textPrimary
    }

    private var textPadding: CGFloat {
        max(2, min(8, rect.height * 0.18))
    }

    private var textLineLimit: Int {
        semanticRole == .heading ? 2 : 1
    }

    private var textAlignment: Alignment {
        if semanticRole == .metricValue {
            return .center
        }
        return .topLeading
    }

    private var cornerRadius: CGFloat {
        if let styleCorner = element.style?.cornerRadius {
            return max(0, min(CGFloat(styleCorner), min(rect.width, rect.height) * 0.45))
        }
        let base = semanticRole == .panel ? palette.panelRadius : palette.controlRadius
        return max(4, min(base, min(rect.width, rect.height) * 0.18))
    }

    private var styleFillColor: Color? {
        if let hex = element.style?.fill?.color {
            return Color(hex: hex, fallback: .clear)
        }
        return nil
    }

    private var styleStrokeColor: Color? {
        if let hex = element.style?.stroke?.color {
            return Color(hex: hex, fallback: .clear)
        }
        return nil
    }

    private var styleStrokeWidth: CGFloat {
        CGFloat(element.style?.stroke?.width ?? 1)
    }

    private var styleOpacity: Double {
        max(0.05, min(1, element.style?.opacity ?? 1))
    }

    private var elementShadowColor: Color {
        if semanticRole == .buttonPrimary || semanticRole == .panel || semanticRole == .chart {
            return Color.black.opacity(0.12)
        }
        return Color.clear
    }

    private var elementShadowRadius: CGFloat {
        if semanticRole == .buttonPrimary {
            return 10
        }
        if semanticRole == .panel || semanticRole == .chart {
            return 6
        }
        return 0
    }

    private var elementShadowYOffset: CGFloat {
        if semanticRole == .buttonPrimary {
            return 5
        }
        if semanticRole == .panel || semanticRole == .chart {
            return 3
        }
        return 0
    }

    private func cappedSize(base: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.max(minValue, Swift.min(maxValue, base))
    }
}
