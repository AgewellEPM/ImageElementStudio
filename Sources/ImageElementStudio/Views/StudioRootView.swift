import AppKit
import SwiftUI

struct StudioRootView: View {
    @ObservedObject var viewModel: StudioViewModel

    var body: some View {
        GeometryReader { geometry in
            let layout = ResponsiveLayout(totalWidth: geometry.size.width)

            HStack(spacing: 0) {
                // Left sidebar
                ScrollView(.vertical, showsIndicators: true) {
                    ChatSidebarPane(viewModel: viewModel)
                }
                .frame(width: layout.leftSidebarWidth)
                .background(Color(hex: "#1E2126", fallback: Color(nsColor: .controlBackgroundColor)))

                Divider()
                    .background(Color.white.opacity(0.08))

                // Center pane (fills available height — no scroll wrapper)
                AnalyzerCenterPane(viewModel: viewModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()
                    .background(Color.white.opacity(0.08))

                // Right sidebar
                ArtboardSidebarPane(viewModel: viewModel)
                    .frame(width: layout.rightSidebarWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color(hex: "#1E2126", fallback: Color(nsColor: .controlBackgroundColor)))
            }
        }
        .frame(minWidth: 1100, minHeight: 660)
        .background(
            LinearGradient(
                colors: [Color(hex: "#1A1D23", fallback: .black), Color(hex: "#12141A", fallback: Color(nsColor: .windowBackgroundColor))],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .preferredColorScheme(.dark)
    }
}

/// Calculates pane widths based on total available window width.
struct ResponsiveLayout {
    let totalWidth: CGFloat

    /// Left sidebar: 22% of width, clamped between 260–330pt.
    var leftSidebarWidth: CGFloat {
        min(max(totalWidth * 0.22, 260), 330)
    }

    /// Right sidebar: 24% of width, clamped between 290–370pt.
    var rightSidebarWidth: CGFloat {
        min(max(totalWidth * 0.24, 290), 370)
    }
}
