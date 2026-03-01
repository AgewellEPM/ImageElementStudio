import AppKit
import SwiftUI

struct StudioRootView: View {
    @ObservedObject var viewModel: StudioViewModel

    var body: some View {
        HSplitView {
            ChatSidebarPane(viewModel: viewModel)
            AnalyzerCenterPane(viewModel: viewModel)
            ArtboardSidebarPane(viewModel: viewModel)
        }
        .frame(minWidth: 1220, minHeight: 760)
        .background(
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "#F7F9FD", fallback: .white), Color(hex: "#EEF3FA", fallback: Color(nsColor: .windowBackgroundColor))],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color(hex: "#DDE9FF", fallback: .blue.opacity(0.12)).opacity(0.45), .clear],
                    center: .topLeading,
                    startRadius: 30,
                    endRadius: 520
                )
            }
            .ignoresSafeArea()
        )
    }
}
