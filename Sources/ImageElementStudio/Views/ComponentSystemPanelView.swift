import SwiftUI

struct ComponentSystemPanelView: View {
    @ObservedObject var viewModel: StudioViewModel

    var body: some View {
        GroupBox("Component System") {
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.componentSystemStatusLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Button("Create Component") {
                        viewModel.createComponentFromSelection(named: nil)
                    }
                    .disabled(viewModel.selectedElementIDs.isEmpty)
                    Button("New Instance") {
                        viewModel.createComponentInstanceFromSelectedComponent()
                    }
                    .disabled(viewModel.selectedComponentID == nil)
                }
                .controlSize(.small)

                if !viewModel.latestComponentSpecs.isEmpty {
                    Picker(
                        "Component",
                        selection: Binding(
                            get: { viewModel.selectedComponentID },
                            set: { viewModel.selectedComponentID = $0 }
                        )
                    ) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(viewModel.latestComponentSpecs) { spec in
                            Text(spec.name).tag(Optional(spec.id))
                        }
                    }
                    .pickerStyle(.menu)

                    TextField("Variant axis", text: $viewModel.selectedVariantAxisName)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    TextField("Variant options (comma separated)", text: $viewModel.selectedVariantOptionsDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                    Button("Apply Variants") {
                        viewModel.updateSelectedComponentVariants(
                            axis: viewModel.selectedVariantAxisName,
                            options: viewModel.selectedVariantOptionsDraft
                        )
                    }
                    .controlSize(.small)
                    .disabled(viewModel.selectedComponentID == nil)

                    if !viewModel.componentInstances.isEmpty {
                        Picker(
                            "Instance",
                            selection: Binding(
                                get: { viewModel.selectedComponentInstanceID },
                                set: { viewModel.selectComponentInstance($0) }
                            )
                        ) {
                            Text("None").tag(Optional<UUID>.none)
                            ForEach(viewModel.componentInstances) { instance in
                                Text(instance.name).tag(Optional(instance.id))
                            }
                        }
                        .pickerStyle(.menu)

                        TextField("Override key", text: $viewModel.selectedInstanceOverrideKeyDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                        TextField("Override value", text: $viewModel.selectedInstanceOverrideValueDraft)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)

                        HStack(spacing: 8) {
                            Button("Apply Override") {
                                viewModel.updateSelectedInstanceOverride(
                                    key: viewModel.selectedInstanceOverrideKeyDraft,
                                    value: viewModel.selectedInstanceOverrideValueDraft
                                )
                            }
                            .controlSize(.small)
                            .disabled(viewModel.selectedComponentInstanceID == nil)

                            Button("Apply To All Instances") {
                                viewModel.applySelectedInstanceOverridesToAll()
                            }
                            .controlSize(.small)
                            .disabled(viewModel.selectedComponentInstanceID == nil)
                        }
                    }

                    if !viewModel.variantMatrixPreview.isEmpty {
                        Text("Variant Matrix")
                            .font(.caption.weight(.semibold))
                        ForEach(Array(viewModel.variantMatrixPreview.prefix(5).enumerated()), id: \.offset) { item in
                            Text(item.element)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
