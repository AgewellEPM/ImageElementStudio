import Foundation

@MainActor
final class ComponentService: ObservableObject {
    // MARK: - Published Properties

    @Published var latestComponentSpecs: [ComponentSpec] = []
    @Published var componentInstances: [ComponentInstance] = []
    @Published var selectedComponentID: UUID?
    @Published var selectedComponentInstanceID: UUID?
    @Published var selectedComponentStateDraft: String = "default"
    @Published var selectedInstanceOverrideKeyDraft: String = "content"
    @Published var selectedInstanceOverrideValueDraft: String = ""

    // MARK: - Public Methods

    /// Creates a new component spec from the selected elements
    /// - Parameters:
    ///   - rawName: Optional name for the component (will be auto-generated if nil/empty)
    ///   - selectedElementIDs: Set of element IDs to include in the component
    ///   - selectedElements: Array of selected CanvasElement objects for role/kind inference
    ///   - activeArtboard: The active artboard (for creating the first instance)
    ///   - latestDesignTokens: Current design token set (for token bindings)
    ///   - updateArtboard: Closure to update artboard elements with component reference
    func createComponentFromSelection(
        named rawName: String?,
        selectedElementIDs: Set<UUID>,
        selectedElements: [CanvasElement],
        activeArtboard: Artboard?,
        latestDesignTokens: DesignTokenSet?,
        updateArtboard: (UUID, (inout Artboard) -> Void) -> Void
    ) {
        guard !selectedElementIDs.isEmpty else { return }
        let name = rawName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName: String
        if let name, !name.isEmpty {
            resolvedName = name
        } else {
            resolvedName = "Component \(latestComponentSpecs.count + 1)"
        }

        let selectionIDs = selectedElementIDs.sorted { $0.uuidString < $1.uuidString }
        let role = selectedElements.compactMap(\.semanticRole).first
        let kind = selectedElements.compactMap { element -> ComponentKind? in
            switch element.semanticRole ?? .unknown {
            case .navigationItem, .navigationSection:
                return .nav
            case .buttonPrimary, .buttonSecondary:
                return .cta
            case .chart:
                return .chart
            case .tableHeader, .tableCell:
                return .table
            case .listItem:
                return .list
            case .panel:
                return .panel
            default:
                return element.kind == .shape ? .panel : .card
            }
        }.first ?? .card

        let spec = ComponentSpec(
            id: UUID(),
            name: resolvedName,
            kind: kind,
            role: role,
            elementIDs: selectionIDs,
            notes: "Created from \(selectionIDs.count) selected elements.",
            variantAxes: ["state": ["default"]],
            stateMappings: ["default": "default"],
            tokenBindings: latestDesignTokens?.colors.keys.reduce(into: [String: String]()) { result, key in
                result[key] = key
            },
            instanceElementIDs: selectionIDs,
            version: 1
        )

        latestComponentSpecs.append(spec)
        selectedComponentID = spec.id

        if let activeArtboard {
            componentInstances.append(
                ComponentInstance(
                    id: UUID(),
                    componentID: spec.id,
                    name: "\(spec.name) Instance 1",
                    artboardID: activeArtboard.id,
                    elementIDs: selectionIDs,
                    variantSelection: ["state": "default"],
                    state: "default",
                    overrides: [:]
                )
            )
        }

        // Update artboard elements with component reference
        if let activeArtboard {
            updateArtboard(activeArtboard.id) { board in
                for index in board.elements.indices where selectedElementIDs.contains(board.elements[index].id) {
                    board.elements[index].componentReferenceID = spec.id
                }
            }
        }
    }

    /// Creates a new instance from the currently selected component spec
    /// - Parameters:
    ///   - activeArtboard: The active artboard to place the instance
    ///   - updateArtboard: Closure to update artboard with new elements, returns new element IDs
    ///   - setSelectedElements: Closure to update selection
    func createComponentInstanceFromSelectedComponent(
        activeArtboard: Artboard?,
        updateArtboard: ((inout Artboard) -> [UUID]) -> Void,
        setSelectedElements: (Set<UUID>, UUID?) -> Void
    ) {
        guard let selectedComponentID,
              let spec = latestComponentSpecs.first(where: { $0.id == selectedComponentID }),
              let artboard = activeArtboard else { return }

        var copiedIDs: [UUID] = []
        updateArtboard { board in
            let sourceElements = board.elements.filter { spec.elementIDs.contains($0.id) }
            let offsetX = 24.0
            let offsetY = 24.0
            var newIDs: [UUID] = []
            for source in sourceElements {
                var copy = source
                copy.id = UUID()
                copy.frame.x = min(Double(board.width) - copy.frame.width, max(0, copy.frame.x + offsetX))
                copy.frame.y = min(Double(board.height) - copy.frame.height, max(0, copy.frame.y + offsetY))
                copy.componentReferenceID = spec.id
                board.elements.append(copy)
                newIDs.append(copy.id)
            }
            copiedIDs = newIDs
            return newIDs
        }

        guard !copiedIDs.isEmpty else { return }
        let instance = ComponentInstance(
            id: UUID(),
            componentID: spec.id,
            name: "\(spec.name) Instance \(componentInstances.filter { $0.componentID == spec.id }.count + 1)",
            artboardID: artboard.id,
            elementIDs: copiedIDs,
            variantSelection: ["state": selectedComponentStateDraft],
            state: selectedComponentStateDraft,
            overrides: [:]
        )
        componentInstances.append(instance)
        selectedComponentInstanceID = instance.id
        setSelectedElements(Set(copiedIDs), copiedIDs.first)
    }

    /// Updates variant axes for the selected component
    /// - Parameters:
    ///   - rawAxis: The axis name (e.g., "state", "size")
    ///   - rawOptions: Comma-separated list of options (e.g., "default,hover,active")
    func updateSelectedComponentVariants(axis rawAxis: String, options rawOptions: String) {
        guard let selectedComponentID,
              let index = latestComponentSpecs.firstIndex(where: { $0.id == selectedComponentID }) else { return }
        let axis = rawAxis.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !axis.isEmpty else { return }
        let options = rawOptions
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !options.isEmpty else { return }

        var spec = latestComponentSpecs[index]
        var variantAxes = spec.variantAxes ?? [:]
        variantAxes[axis] = options
        spec.variantAxes = variantAxes
        if axis.lowercased() == "state" {
            spec.stateMappings = options.reduce(into: [String: String]()) { result, option in
                result[option] = option.capitalized
            }
        }
        spec.version = (spec.version ?? 1) + 1
        latestComponentSpecs[index] = spec
    }

    /// Maps the selected component instance to a specific state
    /// - Parameters:
    ///   - rawState: The state name
    ///   - updateArtboard: Closure to update artboard elements with state tags
    func mapSelectedInstanceToState(
        _ rawState: String,
        updateArtboard: ((inout Artboard) -> Void) -> Void
    ) {
        guard let selectedComponentInstanceID,
              let index = componentInstances.firstIndex(where: { $0.id == selectedComponentInstanceID }) else { return }
        let state = rawState.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !state.isEmpty else { return }

        let elementIDs = componentInstances[index].elementIDs

        componentInstances[index].state = state
        componentInstances[index].variantSelection["state"] = state
        selectedComponentStateDraft = state

        updateArtboard { board in
            for elementIndex in board.elements.indices where elementIDs.contains(board.elements[elementIndex].id) {
                var tags = Set(board.elements[elementIndex].tags)
                tags.insert("component-state:\(state)")
                board.elements[elementIndex].tags = tags.sorted()
            }
        }
    }

    /// Selects a component instance and updates related state
    /// - Parameters:
    ///   - instanceID: The instance ID to select (nil to clear)
    ///   - setSelectedElements: Closure to update element selection
    func selectComponentInstance(
        _ instanceID: UUID?,
        setSelectedElements: (Set<UUID>, UUID?) -> Void
    ) {
        selectedComponentInstanceID = instanceID
        guard let instanceID,
              let instance = componentInstances.first(where: { $0.id == instanceID }) else {
            return
        }
        selectedComponentID = instance.componentID
        selectedComponentStateDraft = instance.state
        selectedInstanceOverrideValueDraft = instance.overrides[selectedInstanceOverrideKeyDraft] ?? ""
        setSelectedElements(Set(instance.elementIDs), instance.elementIDs.first)
    }

    /// Updates an override for the selected component instance
    /// - Parameters:
    ///   - rawKey: The override key (e.g., "content", "fill", "opacity")
    ///   - rawValue: The override value
    ///   - applyToElements: Closure to apply overrides to artboard elements (called after update)
    func updateSelectedInstanceOverride(
        key rawKey: String,
        value rawValue: String,
        applyToElements: () -> Void
    ) {
        guard let selectedComponentInstanceID,
              let instanceIndex = componentInstances.firstIndex(where: { $0.id == selectedComponentInstanceID }) else { return }
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        componentInstances[instanceIndex].overrides[key] = value
        selectedInstanceOverrideKeyDraft = key
        selectedInstanceOverrideValueDraft = value
        applyToElements()
    }

    /// Applies the selected instance's overrides to all instances of the same component
    func applySelectedInstanceOverridesToAll(applyToElements: () -> Void) {
        guard let selectedComponentInstanceID,
              let instance = componentInstances.first(where: { $0.id == selectedComponentInstanceID }) else { return }
        applyOverridesToAllInstances(of: instance.componentID, overrides: instance.overrides, applyToElements: applyToElements)
    }

    // MARK: - Private Helpers

    /// Applies overrides to all instances of a specific component
    /// - Parameters:
    ///   - componentID: The component ID
    ///   - overrides: The overrides to apply
    ///   - applyToElements: Closure to apply overrides to artboard elements (called after each update)
    private func applyOverridesToAllInstances(
        of componentID: UUID,
        overrides: [String: String],
        applyToElements: () -> Void
    ) {
        guard !overrides.isEmpty else { return }
        let targetIDs = componentInstances.filter { $0.componentID == componentID }.map(\.id)
        for instanceID in targetIDs {
            guard let index = componentInstances.firstIndex(where: { $0.id == instanceID }) else { continue }
            componentInstances[index].overrides = overrides
            applyToElements()
        }
    }

}
