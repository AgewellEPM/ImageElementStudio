import SwiftUI

enum ElementListFilter: String, CaseIterable, Hashable {
    case all
    case text
    case shape
}

struct ArtboardSidebarPane: View {
    @ObservedObject var viewModel: StudioViewModel
    @State private var elementFilter: ElementListFilter = .all
    @State private var draftProjectName: String = ""
    @State private var showElementJSONOnRight: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Project")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("Project Name", text: $draftProjectName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        applyProjectSelection()
                    }

                Button("Switch") {
                    applyProjectSelection()
                }
                .disabled(isProjectSwitchDisabled)

                Button(showElementJSONOnRight ? "Hide JSON" : "Element JSON") {
                    showElementJSONOnRight.toggle()
                }
            }

            Text("Artboards")
                .font(.title3.weight(.semibold))

            List(selection: $viewModel.selectedArtboardID) {
                ForEach(viewModel.artboards) { artboard in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(artboard.name)
                            .font(.subheadline.weight(.medium))
                        Text("\(artboard.width)x\(artboard.height) - \(artboard.elements.count) elements")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(artboard.id)
                }
            }
            .frame(minHeight: 190)

            HStack(spacing: 8) {
                Button("New") {
                    viewModel.addArtboard()
                }
                Button("Duplicate") {
                    viewModel.duplicateActiveArtboard()
                }
                .disabled(viewModel.activeArtboard == nil)

                Button("Remove", role: .destructive) {
                    viewModel.removeActiveArtboard()
                }
                .disabled(!viewModel.canRemoveArtboard)
            }

            GroupBox("Elements") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Element Filter", selection: $elementFilter) {
                        Text("All \(viewModel.renderableElements.count)")
                            .tag(ElementListFilter.all)
                        Text("Text \(viewModel.textElementCount)")
                            .tag(ElementListFilter.text)
                        Text("Shapes \(viewModel.shapeElementCount)")
                            .tag(ElementListFilter.shape)
                    }
                    .pickerStyle(.segmented)

                    List(selection: selectedElementsBinding) {
                        ForEach(Array(filteredElements.enumerated()), id: \.element.id) { item in
                            HStack(spacing: 8) {
                                Text("\(item.offset + 1).")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.element.name)
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
                    .frame(minHeight: 180)
                }
            }

            ArtboardAdvancedPanels(viewModel: viewModel, showElementJSONOnRight: $showElementJSONOnRight)

            Spacer()

            Button("Export JSON") {
                viewModel.exportJSON()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .frame(minWidth: 305, idealWidth: 320, maxWidth: 360)
        .background(.ultraThinMaterial)
        .onAppear {
            if draftProjectName.isEmpty {
                draftProjectName = viewModel.projectName
            }
        }
        .onChange(of: viewModel.projectName) { _, newValue in
            draftProjectName = newValue
        }
    }

    private var filteredElements: [CanvasElement] {
        let elements = viewModel.activeArtboard?.elements ?? []
        switch elementFilter {
        case .all:
            return elements
        case .text:
            return elements.filter { $0.kind == .text }
        case .shape:
            return elements.filter { $0.kind == .shape }
        }
    }

    private func confidenceLabel(_ confidence: Double) -> String {
        let percentage = Int((confidence * 100).rounded())
        return "\(percentage)%"
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
