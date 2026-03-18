import SwiftUI

enum ElementListFilter: String, CaseIterable, Hashable {
    case all
    case text
    case shape
}

enum RightSidebarTab: String, CaseIterable, Identifiable {
    case elements
    case code

    var id: String { rawValue }

    var title: String {
        switch self {
        case .elements: return "Elements"
        case .code: return "Code"
        }
    }

    var icon: String {
        switch self {
        case .elements: return "square.stack.3d.up"
        case .code: return "curlybraces"
        }
    }
}

struct ArtboardSidebarPane: View {
    @ObservedObject var viewModel: StudioViewModel
    @State private var elementFilter: ElementListFilter = .all
    @State private var draftProjectName: String = ""
    @State private var sidebarTab: RightSidebarTab = .elements

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Project name
            HStack(spacing: 6) {
                TextField("Project Name", text: $draftProjectName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { applyProjectSelection() }

                Button("Switch") { applyProjectSelection() }
                    .controlSize(.small)
                    .disabled(isProjectSwitchDisabled)
            }

            // Artboards list
            Text("Artboards")
                .font(.subheadline.weight(.semibold))

            List(selection: $viewModel.selectedArtboardID) {
                ForEach(viewModel.artboards) { artboard in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(artboard.name)
                            .font(.caption.weight(.medium))
                        Text("\(artboard.width)x\(artboard.height) \u{00B7} \(artboard.elements.count) elements")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .tag(artboard.id)
                }
            }
            .frame(minHeight: 140)

            HStack(spacing: 6) {
                Button("New") { viewModel.addArtboard() }
                Button("Duplicate") { viewModel.duplicateActiveArtboard() }
                    .disabled(viewModel.activeArtboard == nil)
                Button("Remove", role: .destructive) { viewModel.removeActiveArtboard() }
                    .disabled(!viewModel.canRemoveArtboard)
            }
            .controlSize(.small)

            // Tab switcher: Elements | Code
            Picker("View", selection: $sidebarTab) {
                ForEach(RightSidebarTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            // Tab content
            switch sidebarTab {
            case .elements:
                elementsTab
            case .code:
                ArtboardCodeViewer(viewModel: viewModel)
                    .frame(maxHeight: .infinity)
            }

            Spacer(minLength: 0)

            // Bottom actions
            HStack(spacing: 8) {
                Button("Export JSON") { viewModel.exportJSON() }
                    .controlSize(.small)
                Button {
                    viewModel.openRealtimeBuildOutputFolder()
                } label: {
                    Label("Open Output", systemImage: "folder")
                }
                .controlSize(.small)
                .disabled(viewModel.lastRealtimeBuildPath == nil)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            if draftProjectName.isEmpty {
                draftProjectName = viewModel.projectName
            }
        }
        .onChange(of: viewModel.projectName) { _, newValue in
            draftProjectName = newValue
        }
    }

    // MARK: - Elements Tab

    @ViewBuilder
    private var elementsTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Filter", selection: $elementFilter) {
                Text("All \(viewModel.renderableElements.count)").tag(ElementListFilter.all)
                Text("Text \(viewModel.textElementCount)").tag(ElementListFilter.text)
                Text("Shapes \(viewModel.shapeElementCount)").tag(ElementListFilter.shape)
            }
            .pickerStyle(.segmented)

            List(selection: selectedElementsBinding) {
                ForEach(Array(filteredElements.enumerated()), id: \.element.id) { item in
                    HStack(spacing: 6) {
                        Text("\(item.offset + 1).")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.element.name)
                                .font(.caption)
                                .lineLimit(1)
                            Text(item.element.sidebarSubtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(confidenceLabel(item.element.confidence))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .tag(item.element.id)
                }
            }
            .frame(minHeight: 200)

            // Selected element quick-edit
            if let selected = viewModel.selectedElement {
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Selected: \(selected.name)")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        TextField(
                            "Name",
                            text: Binding(
                                get: { viewModel.selectedElement?.name ?? "" },
                                set: { viewModel.renameSelectedElement($0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                        HStack(spacing: 4) {
                            Button("Rotate -5\u{00B0}") { viewModel.keyboardRotateCounterclockwise() }
                            Button("Rotate +5\u{00B0}") { viewModel.keyboardRotateClockwise() }
                            Spacer()
                            Button("Delete", role: .destructive) { viewModel.deleteSelectedElement() }
                        }
                        .controlSize(.mini)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var filteredElements: [CanvasElement] {
        let elements = viewModel.activeArtboard?.elements ?? []
        switch elementFilter {
        case .all: return elements
        case .text: return elements.filter { $0.kind == .text }
        case .shape: return elements.filter { $0.kind == .shape }
        }
    }

    private func confidenceLabel(_ confidence: Double) -> String {
        "\(Int((confidence * 100).rounded()))%"
    }

    private var isProjectSwitchDisabled: Bool {
        let trimmed = draftProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == viewModel.projectName
    }

    private func applyProjectSelection() {
        let trimmed = draftProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.switchProject(to: trimmed)
    }

    private var selectedElementsBinding: Binding<Set<UUID>> {
        Binding(
            get: { viewModel.selectedElementIDs },
            set: { viewModel.setSelectedElements($0, preferredPrimary: $0.first) }
        )
    }
}

extension CanvasElement {
    var sidebarSubtitle: String {
        if let semanticRole {
            return semanticRole.displayName
        }
        switch kind {
        case .imageRoot:
            return "Canvas Root"
        case .text:
            return "Text"
        case .shape:
            return "Shape"
        }
    }
}

extension SemanticElementRole {
    var displayName: String {
        switch self {
        case .unknown:
            return "Unclassified"
        case .appBrand:
            return "App Brand"
        case .navigationItem:
            return "Navigation Item"
        case .navigationSection:
            return "Navigation Section"
        case .heading:
            return "Heading"
        case .sectionTitle:
            return "Section Title"
        case .metricValue:
            return "Metric Value"
        case .metricLabel:
            return "Metric Label"
        case .metricDelta:
            return "Metric Delta"
        case .chart:
            return "Chart"
        case .chartAxis:
            return "Chart Axis"
        case .tableHeader:
            return "Table Header"
        case .tableCell:
            return "Table Cell"
        case .buttonPrimary:
            return "Primary Button"
        case .buttonSecondary:
            return "Secondary Button"
        case .dateFilter:
            return "Date Filter"
        case .avatar:
            return "Avatar"
        case .tag:
            return "Tag"
        case .panel:
            return "Panel"
        case .listItem:
            return "List Item"
        }
    }
}
