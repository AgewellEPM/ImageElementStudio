import AppKit
import SwiftUI

func normalizedRect(from start: CGPoint, to end: CGPoint) -> CGRect {
    CGRect(
        x: min(start.x, end.x),
        y: min(start.y, end.y),
        width: abs(end.x - start.x),
        height: abs(end.y - start.y)
    )
}

func isAdditiveSelectionModifierActive() -> Bool {
    let flags = NSEvent.modifierFlags
    return flags.contains(.command) || flags.contains(.shift)
}

struct CanvasLayoutMetrics {
    private let imageRect: CGRect
    private let scale: CGFloat

    init(containerSize: CGSize, canvasSize: CGSize) {
        let safeCanvasWidth = max(1, canvasSize.width)
        let safeCanvasHeight = max(1, canvasSize.height)
        let safeContainerWidth = max(1, containerSize.width)
        let safeContainerHeight = max(1, containerSize.height)

        scale = min(
            safeContainerWidth / safeCanvasWidth,
            safeContainerHeight / safeCanvasHeight
        )

        let renderedWidth = safeCanvasWidth * scale
        let renderedHeight = safeCanvasHeight * scale
        let originX = (safeContainerWidth - renderedWidth) / 2
        let originY = (safeContainerHeight - renderedHeight) / 2

        imageRect = CGRect(
            x: originX,
            y: originY,
            width: renderedWidth,
            height: renderedHeight
        )
    }

    func project(frame: ElementFrame) -> CGRect {
        CGRect(
            x: imageRect.minX + CGFloat(frame.x) * scale,
            y: imageRect.minY + CGFloat(frame.y) * scale,
            width: CGFloat(frame.width) * scale,
            height: CGFloat(frame.height) * scale
        )
    }

    var renderRect: CGRect {
        imageRect
    }

    func unproject(delta: CGSize) -> CGSize {
        guard scale > 0 else { return .zero }
        return CGSize(width: delta.width / scale, height: delta.height / scale)
    }
}

struct ElementOverlayBox: View {
    let element: CanvasElement
    let rect: CGRect
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? overlayColor : overlayColor.opacity(0.75), lineWidth: isSelected ? 2.2 : 1.2)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(overlayColor.opacity(0.14))
                )

            Text(element.name)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(overlayColor.opacity(0.9), in: Capsule())
                .foregroundStyle(.white)
                .padding(4)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }

    private var overlayColor: Color {
        switch element.kind {
        case .imageRoot:
            return .gray
        case .text:
            return .green
        case .shape:
            return .orange
        }
    }
}

struct ImageOverlayCanvas: View {
    let image: NSImage
    let canvasSize: CGSize
    let elements: [CanvasElement]
    let selectedElementIDs: Set<UUID>
    let onSelect: (UUID?, Bool) -> Void
    let onMarqueeSelect: ([UUID], Bool) -> Void

    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let layout = CanvasLayoutMetrics(
                containerSize: geometry.size,
                canvasSize: canvasSize
            )
            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelect(nil, false)
                    }

                ForEach(elements.filter { $0.kind != .imageRoot }) { element in
                    let rect = layout.project(frame: element.frame)
                    if rect.width > 2, rect.height > 2 {
                        ElementOverlayBox(
                            element: element,
                            rect: rect,
                            isSelected: selectedElementIDs.contains(element.id),
                            onTap: {
                                onSelect(element.id, isAdditiveSelectionModifierActive())
                            }
                        )
                    }
                }

                if let marqueeRect {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.12))
                        .overlay(
                            Rectangle()
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.2, dash: [5, 3]))
                        )
                        .frame(width: marqueeRect.width, height: marqueeRect.height)
                        .position(x: marqueeRect.midX, y: marqueeRect.midY)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        marqueeStart = marqueeStart ?? value.startLocation
                        marqueeCurrent = value.location
                    }
                    .onEnded { value in
                        defer {
                            marqueeStart = nil
                            marqueeCurrent = nil
                        }

                        let start = marqueeStart ?? value.startLocation
                        let selectionRect = normalizedRect(from: start, to: value.location)
                        guard selectionRect.width > 4, selectionRect.height > 4 else { return }

                        let selectedIDs = elements
                            .filter { $0.kind != .imageRoot }
                            .filter { selectionRect.intersects(layout.project(frame: $0.frame)) }
                            .map(\.id)
                        onMarqueeSelect(selectedIDs, isAdditiveSelectionModifierActive())
                    }
            )
        }
    }

    private var marqueeRect: CGRect? {
        guard let marqueeStart, let marqueeCurrent else { return nil }
        return normalizedRect(from: marqueeStart, to: marqueeCurrent)
    }
}

struct AppEmulatorCanvas: View {
    let artboard: Artboard
    let selectedElementIDs: Set<UUID>
    let tokens: DesignTokenSet?
    let showGrid: Bool
    let gridSize: Double
    let showAlignmentGuides: Bool
    let onSelect: (UUID?, Bool) -> Void
    let onMarqueeSelect: ([UUID], Bool) -> Void
    let onResize: (StudioViewModel.ResizeHandle, Double, Double) -> Void
    let onRotate: (Double) -> Void

    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let layout = CanvasLayoutMetrics(
                containerSize: geometry.size,
                canvasSize: CGSize(width: artboard.width, height: artboard.height)
            )
            let renderRect = layout.renderRect
            let palette = EmulatorTokenPalette(tokens: tokens)
            let selectedProjectedFrame = projectedSelectionFrame(using: layout)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [palette.canvasBackground, palette.surfacePanel],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(palette.strokeSoft.opacity(0.8), lineWidth: 1)
                    )
                    .frame(width: renderRect.width, height: renderRect.height)
                    .position(x: renderRect.midX, y: renderRect.midY)
                    .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)

                if showGrid {
                    GridOverlay(
                        renderRect: renderRect,
                        artboardSize: CGSize(width: artboard.width, height: artboard.height),
                        gridSize: gridSize,
                        color: palette.strokeSoft
                    )
                }

                ForEach(renderedElements) { element in
                    let rect = layout.project(frame: element.frame)
                    if rect.width > 3, rect.height > 3 {
                        AppEmulatorElement(
                            element: element,
                            rect: rect,
                            palette: palette,
                            isSelected: selectedElementIDs.contains(element.id),
                            onTap: { onSelect(element.id, isAdditiveSelectionModifierActive()) }
                        )
                    }
                }

                if let selectedProjectedFrame {
                    SelectionTransformOverlay(
                        frame: selectedProjectedFrame,
                        color: palette.accentPrimary,
                        onResize: { handle, delta in
                            let canvasDelta = layout.unproject(delta: delta)
                            onResize(handle, canvasDelta.width, canvasDelta.height)
                        },
                        onRotate: { degrees in
                            onRotate(degrees)
                        }
                    )
                }

                if showAlignmentGuides, let selectedProjectedFrame {
                    AlignmentGuideOverlay(
                        frame: selectedProjectedFrame,
                        renderRect: renderRect,
                        color: palette.accentPrimary
                    )
                }

                if let marqueeRect {
                    Rectangle()
                        .fill(palette.accentPrimary.opacity(0.12))
                        .overlay(
                            Rectangle()
                                .stroke(palette.accentPrimary.opacity(0.95), style: StrokeStyle(lineWidth: 1.2, dash: [5, 3]))
                        )
                        .frame(width: marqueeRect.width, height: marqueeRect.height)
                        .position(x: marqueeRect.midX, y: marqueeRect.midY)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect(nil, false)
            }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        marqueeStart = marqueeStart ?? value.startLocation
                        marqueeCurrent = value.location
                    }
                    .onEnded { value in
                        defer {
                            marqueeStart = nil
                            marqueeCurrent = nil
                        }

                        let start = marqueeStart ?? value.startLocation
                        let selectionRect = normalizedRect(from: start, to: value.location)
                        guard selectionRect.width > 4, selectionRect.height > 4 else { return }

                        let selectedIDs = renderedElements
                            .filter { selectionRect.intersects(layout.project(frame: $0.frame)) }
                            .map(\.id)
                        onMarqueeSelect(selectedIDs, isAdditiveSelectionModifierActive())
                    }
            )
        }
    }

    private func projectedSelectionFrame(using layout: CanvasLayoutMetrics) -> CGRect? {
        let frames = renderedElements
            .filter { selectedElementIDs.contains($0.id) }
            .map { layout.project(frame: $0.frame) }
        guard var result = frames.first else { return nil }
        for frame in frames.dropFirst() {
            result = result.union(frame)
        }
        return result
    }

    private var marqueeRect: CGRect? {
        guard let marqueeStart, let marqueeCurrent else { return nil }
        return normalizedRect(from: marqueeStart, to: marqueeCurrent)
    }

    private var renderedElements: [CanvasElement] {
        artboard.elements
            .filter { $0.kind != .imageRoot }
            .sorted { lhs, rhs in
                if zPriority(lhs) != zPriority(rhs) {
                    return zPriority(lhs) < zPriority(rhs)
                }
                if lhs.frame.y != rhs.frame.y {
                    return lhs.frame.y < rhs.frame.y
                }
                if lhs.frame.x != rhs.frame.x {
                    return lhs.frame.x < rhs.frame.x
                }
                return lhs.name < rhs.name
            }
    }

    private func zPriority(_ element: CanvasElement) -> Int {
        if element.kind == .shape { return 0 }
        return 1
    }
}
