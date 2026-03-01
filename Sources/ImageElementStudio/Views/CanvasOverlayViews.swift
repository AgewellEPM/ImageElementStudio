import SwiftUI

struct GridOverlay: View {
    let renderRect: CGRect
    let artboardSize: CGSize
    let gridSize: Double
    let color: Color

    var body: some View {
        Canvas { context, _ in
            let safeGrid = max(2, gridSize)
            let xRatio = safeGrid / max(1.0, Double(artboardSize.width))
            let yRatio = safeGrid / max(1.0, Double(artboardSize.height))
            let xStep = max(4, renderRect.width * CGFloat(xRatio))
            let yStep = max(4, renderRect.height * CGFloat(yRatio))

            var path = Path()
            var x = renderRect.minX
            while x <= renderRect.maxX {
                path.move(to: CGPoint(x: x, y: renderRect.minY))
                path.addLine(to: CGPoint(x: x, y: renderRect.maxY))
                x += xStep
            }

            var y = renderRect.minY
            while y <= renderRect.maxY {
                path.move(to: CGPoint(x: renderRect.minX, y: y))
                path.addLine(to: CGPoint(x: renderRect.maxX, y: y))
                y += yStep
            }

            context.stroke(path, with: .color(color.opacity(0.45)), lineWidth: 0.6)
        }
    }
}

struct AlignmentGuideOverlay: View {
    let frame: CGRect
    let renderRect: CGRect
    let color: Color

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: frame.midX, y: renderRect.minY))
            path.addLine(to: CGPoint(x: frame.midX, y: renderRect.maxY))
            path.move(to: CGPoint(x: renderRect.minX, y: frame.midY))
            path.addLine(to: CGPoint(x: renderRect.maxX, y: frame.midY))
        }
        .stroke(color.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
    }
}

struct SelectionTransformOverlay: View {
    let frame: CGRect
    let color: Color
    let onResize: (StudioViewModel.ResizeHandle, CGSize) -> Void
    let onRotate: (Double) -> Void

    @State private var resizeTranslationBaseline: CGSize = .zero
    @State private var rotateTranslationBaseline: CGFloat = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .stroke(color.opacity(0.95), lineWidth: 1.4)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            resizeHandle(for: .topLeft, at: CGPoint(x: frame.minX, y: frame.minY))
            resizeHandle(for: .topRight, at: CGPoint(x: frame.maxX, y: frame.minY))
            resizeHandle(for: .bottomLeft, at: CGPoint(x: frame.minX, y: frame.maxY))
            resizeHandle(for: .bottomRight, at: CGPoint(x: frame.maxX, y: frame.maxY))
            resizeHandle(for: .left, at: CGPoint(x: frame.minX, y: frame.midY))
            resizeHandle(for: .right, at: CGPoint(x: frame.maxX, y: frame.midY))
            resizeHandle(for: .top, at: CGPoint(x: frame.midX, y: frame.minY))
            resizeHandle(for: .bottom, at: CGPoint(x: frame.midX, y: frame.maxY))

            rotateHandle
        }
    }

    @ViewBuilder
    private func resizeHandle(for handle: StudioViewModel.ResizeHandle, at point: CGPoint) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(color, lineWidth: 1.2))
            .frame(width: 9, height: 9)
            .position(point)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let delta = CGSize(
                            width: value.translation.width - resizeTranslationBaseline.width,
                            height: value.translation.height - resizeTranslationBaseline.height
                        )
                        resizeTranslationBaseline = value.translation
                        onResize(handle, delta)
                    }
                    .onEnded { _ in
                        resizeTranslationBaseline = .zero
                    }
            )
    }

    private var rotateHandle: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .position(x: frame.midX, y: frame.minY - 18)
            .overlay(
                Capsule()
                    .fill(color.opacity(0.7))
                    .frame(width: 1.4, height: 12)
                    .offset(y: 6)
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let incremental = value.translation.width - rotateTranslationBaseline
                        rotateTranslationBaseline = value.translation.width
                        let delta = Double(incremental * 0.18)
                        onRotate(delta)
                    }
                    .onEnded { _ in
                        rotateTranslationBaseline = 0
                    }
            )
    }
}
