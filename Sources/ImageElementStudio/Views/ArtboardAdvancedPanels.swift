import SwiftUI

struct ArtboardAdvancedPanels: View {
    @ObservedObject var viewModel: StudioViewModel
    @Binding var showElementJSONOnRight: Bool

    var body: some View {
        AIScopePanelView(viewModel: viewModel)
        DesignSystemPanelView(viewModel: viewModel)
        ComponentSystemPanelView(viewModel: viewModel)
        TokenHistoryPanelView(viewModel: viewModel)
        LayoutBenchmarkPanelView(viewModel: viewModel)
        MirrorBlueprintPanelView(viewModel: viewModel)
        InteropPanelView(viewModel: viewModel)
        BuildQualityPanelView(viewModel: viewModel)
        ReviewPanelView(viewModel: viewModel)
        MemoryPanelView(viewModel: viewModel)
        if showElementJSONOnRight {
            ElementJSONPanelView(viewModel: viewModel)
        }
        EditElementPanelView(viewModel: viewModel)
    }
}
