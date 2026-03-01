import SwiftUI

struct DesignSystemPanelView: View {
    @ObservedObject var viewModel: StudioViewModel

    var body: some View {
        GroupBox("Design System") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Style Preset", selection: stylePresetBinding) {
                    ForEach(MockupStylePreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 240, alignment: .leading)

                Text(viewModel.designSystemStatusLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let tokens = viewModel.latestDesignTokens {
                    HStack(spacing: 8) {
                        TokenSwatch(hex: tokens.colors["accent.primary"] ?? "#3B5CFF", label: "Accent")
                        TokenSwatch(hex: tokens.colors["surface.base"] ?? "#FFFFFF", label: "Surface")
                        TokenSwatch(hex: tokens.colors["text.primary"] ?? "#151A24", label: "Text")
                    }

                    TokenHexEditorRow(
                        title: "Accent",
                        value: tokens.colors["accent.primary"] ?? "#3B5CFF",
                        onChange: { viewModel.updateTokenColor("accent.primary", value: $0) }
                    )
                    TokenHexEditorRow(
                        title: "Surface",
                        value: tokens.colors["surface.base"] ?? "#FFFFFF",
                        onChange: { viewModel.updateTokenColor("surface.base", value: $0) }
                    )
                    TokenHexEditorRow(
                        title: "Text",
                        value: tokens.colors["text.primary"] ?? "#151A24",
                        onChange: { viewModel.updateTokenColor("text.primary", value: $0) }
                    )
                } else {
                    Text("Generate mockups from idea/strategy to create token set and component semantics.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stylePresetBinding: Binding<MockupStylePreset> {
        Binding(
            get: { viewModel.mockupStylePreset },
            set: { viewModel.setMockupStylePreset($0) }
        )
    }
}
