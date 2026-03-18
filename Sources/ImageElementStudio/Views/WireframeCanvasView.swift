import SwiftUI

// MARK: - Wireframe palette constants

private enum WF {
    static let background    = Color(red: 0.961, green: 0.961, blue: 0.961) // #F5F5F5
    static let elementFill   = Color.white
    static let border        = Color(red: 0.6,   green: 0.6,   blue: 0.6)   // #999999
    static let borderDark    = Color(red: 0.2,   green: 0.2,   blue: 0.2)   // #333333
    static let textPrimary   = Color(red: 0.2,   green: 0.2,   blue: 0.2)   // #333333
    static let textSecondary = Color(red: 0.6,   green: 0.6,   blue: 0.6)   // #999999
    static let fillGray      = Color(red: 0.87,  green: 0.87,  blue: 0.87)  // #DEDEDE
    static let selection     = Color(red: 0.2,   green: 0.47,  blue: 0.95)

    static let dash: [CGFloat] = [6, 4]
    static let strokeW: CGFloat = 1.5
    static let corner: CGFloat  = 2
}

// MARK: - Main wireframe canvas

struct WireframeCanvasView: View {
    let artboard: Artboard
    let selectedElementIDs: Set<UUID>
    let onSelect: (UUID?, Bool) -> Void
    let onMarqueeSelect: ([UUID], Bool) -> Void

    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let layout = CanvasLayoutMetrics(
                containerSize: geometry.size,
                canvasSize: CGSize(width: artboard.width, height: artboard.height)
            )
            let rr = layout.renderRect

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(WF.background)
                    .overlay(Rectangle().stroke(WF.border, lineWidth: 1))
                    .frame(width: rr.width, height: rr.height)
                    .position(x: rr.midX, y: rr.midY)

                ForEach(renderedElements) { element in
                    let rect = layout.project(frame: element.frame)
                    if rect.width > 3, rect.height > 3 {
                        WireframeElement(
                            element: element,
                            rect: rect,
                            isSelected: selectedElementIDs.contains(element.id),
                            onTap: { onSelect(element.id, isAdditiveSelectionModifierActive()) }
                        )
                    }
                }

                if let mq = marqueeRect {
                    Rectangle()
                        .fill(WF.selection.opacity(0.08))
                        .overlay(Rectangle().stroke(WF.selection.opacity(0.85),
                                                     style: StrokeStyle(lineWidth: 1.2, dash: [5, 3])))
                        .frame(width: mq.width, height: mq.height)
                        .position(x: mq.midX, y: mq.midY)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onSelect(nil, false) }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        marqueeStart = marqueeStart ?? value.startLocation
                        marqueeCurrent = value.location
                    }
                    .onEnded { value in
                        defer { marqueeStart = nil; marqueeCurrent = nil }
                        let start = marqueeStart ?? value.startLocation
                        let sel = normalizedRect(from: start, to: value.location)
                        guard sel.width > 4, sel.height > 4 else { return }
                        let ids = renderedElements
                            .filter { sel.intersects(layout.project(frame: $0.frame)) }
                            .map(\.id)
                        onMarqueeSelect(ids, isAdditiveSelectionModifierActive())
                    }
            )
        }
    }

    private var marqueeRect: CGRect? {
        guard let marqueeStart, let marqueeCurrent else { return nil }
        return normalizedRect(from: marqueeStart, to: marqueeCurrent)
    }

    private var renderedElements: [CanvasElement] {
        artboard.elements
            .filter { $0.kind != .imageRoot }
            .sorted { lhs, rhs in
                let lp = lhs.kind == .shape ? 0 : 1
                let rp = rhs.kind == .shape ? 0 : 1
                if lp != rp { return lp < rp }
                if lhs.frame.y != rhs.frame.y { return lhs.frame.y < rhs.frame.y }
                if lhs.frame.x != rhs.frame.x { return lhs.frame.x < rhs.frame.x }
                return lhs.name < rhs.name
            }
    }
}

// MARK: - Individual wireframe element

private struct WireframeElement: View {
    let element: CanvasElement
    let rect: CGRect
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack {
            fillLayer
            strokeLayer
            if isSelected {
                RoundedRectangle(cornerRadius: WF.corner)
                    .stroke(WF.selection, lineWidth: 2)
            }
            contentLayer
        }
        .frame(width: rect.width, height: rect.height)
        .rotationEffect(.degrees(element.rotationDegrees))
        .position(x: rect.midX, y: rect.midY)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    // MARK: Fill

    @ViewBuilder private var fillLayer: some View {
        switch role {
        case .buttonPrimary, .tableHeader, .navigationItem:
            RoundedRectangle(cornerRadius: WF.corner).fill(WF.fillGray)
        case .avatar:
            Circle().fill(WF.fillGray)
        case .tag:
            Capsule().fill(WF.fillGray)
        default:
            RoundedRectangle(cornerRadius: WF.corner)
                .fill(element.kind == .shape ? WF.elementFill : Color.clear)
        }
    }

    // MARK: Border

    @ViewBuilder private var strokeLayer: some View {
        let dashed = StrokeStyle(lineWidth: WF.strokeW, dash: WF.dash)
        switch role {
        case .buttonPrimary, .tableHeader:
            RoundedRectangle(cornerRadius: WF.corner).stroke(WF.borderDark, lineWidth: WF.strokeW)
        case .navigationSection:
            EmptyView()
        case .avatar:
            Circle().stroke(WF.border, style: dashed)
        case .tag:
            Capsule().stroke(WF.border, style: dashed)
        default:
            RoundedRectangle(cornerRadius: WF.corner).stroke(WF.border, style: dashed)
        }
    }

    // MARK: Content

    @ViewBuilder private var contentLayer: some View {
        switch role {
        case .heading, .sectionTitle:
            label(text: labelText, size: fs(0.50, 10, 28), weight: .bold, color: WF.textPrimary,
                  align: .topLeading, lines: 2)
        case .metricValue:
            label(text: labelText, size: fs(0.55, 11, 38), weight: .semibold, color: WF.textPrimary,
                  design: .monospaced, align: .center, lines: 1)
        case .metricLabel:
            label(text: labelText, size: fs(0.38, 8, 14), weight: .regular, color: WF.textSecondary,
                  design: .monospaced, align: .center, lines: 1)
        case .buttonPrimary:
            label(text: labelText, size: fs(0.40, 9, 16), weight: .semibold, color: WF.textPrimary,
                  align: .center, lines: 1)
        case .buttonSecondary:
            label(text: labelText, size: fs(0.40, 9, 16), weight: .regular, color: WF.textSecondary,
                  align: .center, lines: 1)
        case .navigationItem, .navigationSection:
            navBars
        case .chart:
            chartBars
        case .tableHeader:
            label(text: labelText, size: fs(0.38, 8, 13), weight: .semibold, color: WF.textPrimary,
                  align: .leading, lines: 1).padding(.horizontal, 4)
        case .tableCell:
            label(text: labelText, size: fs(0.35, 8, 12), weight: .regular, color: WF.textSecondary,
                  align: .leading, lines: 1).padding(.horizontal, 4)
        case .avatar:
            label(text: "?", size: fs(0.40, 9, 22), weight: .light, color: WF.textSecondary,
                  align: .center, lines: 1)
        case .tag:
            label(text: labelText, size: fs(0.38, 7, 11), weight: .regular, color: WF.textSecondary,
                  align: .center, lines: 1).padding(.horizontal, 4)
        case .panel:
            label(text: labelText, size: fs(0.20, 8, 12), weight: .regular, color: WF.textSecondary,
                  align: .topLeading, lines: 1).padding(4)
        default:
            if element.kind == .shape {
                crossHatch
            } else {
                label(text: labelText, size: fs(0.38, 8, 13), weight: .regular, color: WF.textSecondary,
                      align: .center, lines: 1)
            }
        }
    }

    // MARK: Sub-views

    private var navBars: some View {
        HStack(spacing: 4) {
            ForEach(0..<min(3, max(1, Int(rect.width / 60))), id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1)
                    .fill(WF.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(4, rect.height * 0.18))
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var chartBars: some View {
        GeometryReader { geo in
            let bw = geo.size.width * 0.12
            let maxH = geo.size.height * 0.7
            HStack(alignment: .bottom, spacing: bw * 0.6) {
                ForEach([0.55, 1.0, 0.75] as [CGFloat], id: \.self) { h in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(WF.fillGray)
                        .overlay(RoundedRectangle(cornerRadius: 1).stroke(WF.border, lineWidth: 1))
                        .frame(width: bw, height: maxH * h)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
            .padding(.bottom, 4)
        }
    }

    private var crossHatch: some View {
        Canvas { ctx, size in
            let step: CGFloat = 10
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                ctx.stroke(path, with: .color(WF.border.opacity(0.4)), lineWidth: 0.8)
                x += step
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: WF.corner))
    }

    // MARK: Helpers

    private var role: SemanticElementRole { element.semanticRole ?? .unknown }

    private var labelText: String {
        let t = element.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !t.isEmpty { return String(t.prefix(36)) }
        return element.kind == .text ? "Aa" : element.name
    }

    private func fs(_ scale: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        Swift.max(lo, Swift.min(hi, rect.height * scale))
    }

    private func label(
        text: String, size: CGFloat, weight: Font.Weight, color: Color,
        design: Font.Design = .default, align: Alignment, lines: Int
    ) -> some View {
        Text(text)
            .font(.system(size: size, weight: weight, design: design))
            .foregroundStyle(color)
            .lineLimit(lines)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: align)
    }
}
