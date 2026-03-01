import SwiftUI

// MARK: - AI Scope Panel

struct AIScopePanelView: View {
    @ObservedObject var viewModel: StudioViewModel

    var body: some View {
        GroupBox("AI Scope") {
            VStack(alignment: .leading, spacing: 8) {
                if let scope = viewModel.latestScope {
                    HStack {
                        Text(scope.appType)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(Int((scope.confidence * 100).rounded()))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(scope.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !scope.keyCapabilities.isEmpty {
                        Text(scope.keyCapabilities.prefix(3).joined(separator: " | "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Analyze a design or generate from idea to infer app type, scope, and semantic roles.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Token History Panel

struct TokenHistoryPanelView: View {
    @ObservedObject var viewModel: StudioViewModel

    var body: some View {
        GroupBox("Token History") {
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.tokenRevisionStatusLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(Array(viewModel.tokenRevisions.suffix(4).reversed())) { revision in
                    HStack {
                        Text(revision.reason)
                            .font(.caption2)
                        Spacer()
                        Button("Rollback") {
                            viewModel.rollbackTokenRevision(revision.id)
                        }
                        .controlSize(.small)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Mirror Blueprint Panel

struct MirrorBlueprintPanelView: View {
    @ObservedObject var viewModel: StudioViewModel

    var body: some View {
        GroupBox("Mirror Blueprint") {
            VStack(alignment: .leading, spacing: 8) {
                if let blueprint = viewModel.latestBlueprint {
                    Text("Controls: \(blueprint.controls.count) \u{00B7} States: \(blueprint.states.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(viewModel.realtimeBuildStatusLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Button("Open Realtime Output") {
                            viewModel.openRealtimeBuildOutputFolder()
                        }
                        .controlSize(.small)
                        .disabled(viewModel.lastRealtimeBuildPath == nil)
                        Button("Refresh Realtime Build") {
                            viewModel.triggerRealtimeBuildNow()
                        }
                        .controlSize(.small)
                    }
                } else {
                    Text("Analyze a design or idea to infer mirror score, controls, and suggested artboards.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Interop Panel

struct InteropPanelView: View {
    @ObservedObject var viewModel: StudioViewModel

    var body: some View {
        GroupBox("Interop Fidelity") {
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.interopStatusLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Export Interop Package") {
                    viewModel.exportInteropPackage()
                }
                .controlSize(.small)
                .disabled(!viewModel.canExportBuildArtifacts)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Memory Panel

struct MemoryPanelView: View {
    @ObservedObject var viewModel: StudioViewModel

    var body: some View {
        GroupBox("Memory") {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(viewModel.memoryStatusLine)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear Memory", role: .destructive) {
                        viewModel.clearProjectMemory()
                    }
                    .controlSize(.small)
                }
                ForEach(viewModel.memoryEntriesPreview) { entry in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.appType)
                            .font(.caption.weight(.medium))
                        Text(entry.summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Element JSON Panel

struct ElementJSONPanelView: View {
    @ObservedObject var viewModel: StudioViewModel

    var body: some View {
        GroupBox("Element JSON") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    Button("Copy JSON") {
                        viewModel.copyJSONToClipboard()
                    }
                    .controlSize(.small)
                }
                ScrollView {
                    Text(viewModel.jsonPreview)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 180, maxHeight: 260)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
            }
        }
    }
}

// MARK: - Edit Element Panel

struct EditElementPanelView: View {
    @ObservedObject var viewModel: StudioViewModel

    var body: some View {
        GroupBox("Edit Element") {
            VStack(alignment: .leading, spacing: 10) {
                if let selected = viewModel.selectedElement {
                    Text("Selected: \(selected.name) (\(viewModel.selectedElementIDs.count))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField(
                        "Element Name",
                        text: Binding(
                            get: { viewModel.selectedElement?.name ?? "" },
                            set: { viewModel.renameSelectedElement($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    HStack(spacing: 6) {
                        Button("Rotate -5\u{00B0}") { viewModel.keyboardRotateCounterclockwise() }
                        Button("Rotate +5\u{00B0}") { viewModel.keyboardRotateClockwise() }
                    }
                    .controlSize(.small)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Constraint Pins")
                            .font(.caption.weight(.semibold))
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 4) {
                            ForEach(ConstraintPin.allCases) { pin in
                                Toggle(
                                    pin.title,
                                    isOn: Binding(
                                        get: { viewModel.hasConstraint(pin) },
                                        set: { viewModel.toggleConstraint(pin, enabled: $0) }
                                    )
                                )
                                .font(.caption2)
                            }
                        }
                    }

                    Button("Delete Element", role: .destructive) {
                        viewModel.deleteSelectedElement()
                    }
                } else {
                    Text("Select an overlay in the center pane to edit it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
