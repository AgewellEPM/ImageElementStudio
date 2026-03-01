import Foundation

@MainActor
final class DesignTokenService: ObservableObject {
    @Published var latestDesignTokens: DesignTokenSet?
    @Published var tokenRevisions: [TokenRevision] = []

    // Callback to propagate token changes to artboards and components
    var onTokenChangesPropagated: ((DesignTokenSet) -> Void)?

    // MARK: - Public Methods

    func tokenColorValue(_ key: String, fallback: String) -> String {
        latestDesignTokens?.colors[key] ?? fallback
    }

    func updateTokenColor(
        _ key: String,
        value: String,
        mockupGenerator: MockupGenerator,
        latestScope: ProductScopeSnapshot?,
        acceptedStrategySpec: StrategySpec?,
        mockupStylePreset: MockupStylePreset
    ) {
        guard var tokens = editableTokenSet(
            mockupGenerator: mockupGenerator,
            latestScope: latestScope,
            acceptedStrategySpec: acceptedStrategySpec,
            mockupStylePreset: mockupStylePreset
        ) else { return }
        let normalized = _normalizedHex(value)
        guard !normalized.isEmpty else { return }
        captureTokenRevision(
            reason: "Update token color \(key)",
            mockupGenerator: mockupGenerator,
            latestScope: latestScope,
            acceptedStrategySpec: acceptedStrategySpec,
            mockupStylePreset: mockupStylePreset
        )
        tokens.colors[key] = normalized
        latestDesignTokens = tokens
        propagateGlobalTokenChanges()
    }

    func tokenRadiusValue(_ key: String, fallback: Double) -> Double {
        latestDesignTokens?.radius[key] ?? fallback
    }

    func updateTokenRadius(
        _ key: String,
        value: Double,
        mockupGenerator: MockupGenerator,
        latestScope: ProductScopeSnapshot?,
        acceptedStrategySpec: StrategySpec?,
        mockupStylePreset: MockupStylePreset
    ) {
        guard var tokens = editableTokenSet(
            mockupGenerator: mockupGenerator,
            latestScope: latestScope,
            acceptedStrategySpec: acceptedStrategySpec,
            mockupStylePreset: mockupStylePreset
        ) else { return }
        captureTokenRevision(
            reason: "Update token radius \(key)",
            mockupGenerator: mockupGenerator,
            latestScope: latestScope,
            acceptedStrategySpec: acceptedStrategySpec,
            mockupStylePreset: mockupStylePreset
        )
        tokens.radius[key] = min(Constants.TokenRadius.maxValue, max(Constants.TokenRadius.minValue, value))
        latestDesignTokens = tokens
        propagateGlobalTokenChanges()
    }

    func tokenTypographySize(_ key: String, fallback: Double) -> Double {
        guard let tokens = latestDesignTokens else { return fallback }
        return _typographySize(from: tokens.typography[key], fallback: fallback)
    }

    func updateTokenTypographySize(
        _ key: String,
        value: Double,
        mockupGenerator: MockupGenerator,
        latestScope: ProductScopeSnapshot?,
        acceptedStrategySpec: StrategySpec?,
        mockupStylePreset: MockupStylePreset
    ) {
        guard var tokens = editableTokenSet(
            mockupGenerator: mockupGenerator,
            latestScope: latestScope,
            acceptedStrategySpec: acceptedStrategySpec,
            mockupStylePreset: mockupStylePreset
        ) else { return }
        let base = tokens.typography[key] ?? "\(Int(value.rounded()))"
        captureTokenRevision(
            reason: "Update token typography \(key)",
            mockupGenerator: mockupGenerator,
            latestScope: latestScope,
            acceptedStrategySpec: acceptedStrategySpec,
            mockupStylePreset: mockupStylePreset
        )
        tokens.typography[key] = _replacingTypographySize(in: base, with: value)
        latestDesignTokens = tokens
        propagateGlobalTokenChanges()
    }

    func rollbackTokenRevision(_ revisionID: UUID) {
        guard let revision = tokenRevisions.first(where: { $0.id == revisionID }) else { return }
        latestDesignTokens = revision.tokens
        propagateGlobalTokenChanges()
    }

    func clearTokenRevisionHistory() {
        tokenRevisions = []
    }

    // MARK: - Public Token Propagation

    /// Propagates a changed token set across all artboard elements and component specs.
    ///
    /// Call this after modifying `latestDesignTokens` to push colour, stroke, and radius changes
    /// down onto individual elements so the canvas reflects the updated tokens immediately.
    ///
    /// - Parameters:
    ///   - tokens: The updated `DesignTokenSet` to propagate.
    ///   - artboards: The current artboard array (mutated in-place, returned via callbacks).
    ///   - mockupStylePreset: The active mockup style preset (its raw value is written as a tag).
    ///   - latestComponentSpecs: The current component spec array (mutated in-place).
    ///   - onArtboardsUpdated: Called with the fully mutated artboard array.
    ///   - onComponentSpecsUpdated: Called with the updated component spec array.
    ///   - onRegenerateJSON: Called after propagation so the ViewModel refreshes its JSON preview.
    func propagateGlobalTokenChanges(
        _ tokens: DesignTokenSet,
        artboards: [Artboard],
        mockupStylePreset: MockupStylePreset,
        latestComponentSpecs: [ComponentSpec],
        onArtboardsUpdated: ([Artboard]) -> Void,
        onComponentSpecsUpdated: ([ComponentSpec]) -> Void,
        onRegenerateJSON: () -> Void
    ) {
        // Update token bindings on component specs
        let updatedSpecs = latestComponentSpecs.map { spec -> ComponentSpec in
            var copy = spec
            var bindings = copy.tokenBindings ?? [:]
            for key in tokens.colors.keys {
                if bindings[key] == nil {
                    bindings[key] = key
                }
            }
            copy.tokenBindings = bindings
            return copy
        }
        onComponentSpecsUpdated(updatedSpecs)

        // Push token values down onto individual artboard elements
        var updatedArtboards = artboards
        for boardIndex in updatedArtboards.indices {
            for elementIndex in updatedArtboards[boardIndex].elements.indices
                where updatedArtboards[boardIndex].elements[elementIndex].kind != .imageRoot
            {
                var element = updatedArtboards[boardIndex].elements[elementIndex]
                var tags = Set(element.tags)
                tags.insert("token-sync:\(mockupStylePreset.rawValue)")

                var style = element.style ?? ElementVisualStyle(
                    fill: nil,
                    stroke: nil,
                    cornerRadius: nil,
                    opacity: nil,
                    typography: nil
                )

                if tags.contains("token:color.accent.primary") || element.semanticRole == .buttonPrimary {
                    style.fill = ElementFillStyle(color: tokens.colors["accent.primary"], gradient: nil)
                } else if tags.contains("token:color.surface.base") || element.kind == .shape {
                    style.fill = ElementFillStyle(color: tokens.colors["surface.base"], gradient: nil)
                }

                if tags.contains("token:stroke.soft") {
                    style.stroke = ElementStrokeStyle(
                        color: tokens.colors["stroke.soft"],
                        width: style.stroke?.width ?? 1
                    )
                }

                if tags.contains("token:radius.control") {
                    style.cornerRadius = tokens.radius["control"]
                } else if tags.contains("token:radius.panel") {
                    style.cornerRadius = tokens.radius["panel"]
                }

                element.tags = tags.sorted()
                element.style = style
                updatedArtboards[boardIndex].elements[elementIndex] = element
            }
        }
        onArtboardsUpdated(updatedArtboards)
        onRegenerateJSON()
    }

    // MARK: - Public Token Utility Helpers

    /// Returns a normalised `#RRGGBB` hex string, or an empty string when `raw` is invalid.
    func normalizedHex(_ raw: String) -> String {
        _normalizedHex(raw)
    }

    /// Parses a typography token value (e.g. `"Regular / 14"` or `"14"`) and returns the size.
    func typographySize(from value: String?, fallback: Double) -> Double {
        _typographySize(from: value, fallback: fallback)
    }

    /// Replaces the trailing size component in a typography token value string.
    func replacingTypographySize(in value: String, with size: Double) -> String {
        _replacingTypographySize(in: value, with: size)
    }

    // MARK: - Private Helpers

    private func captureTokenRevision(
        reason: String,
        mockupGenerator: MockupGenerator,
        latestScope: ProductScopeSnapshot?,
        acceptedStrategySpec: StrategySpec?,
        mockupStylePreset: MockupStylePreset
    ) {
        guard let current = editableTokenSet(
            mockupGenerator: mockupGenerator,
            latestScope: latestScope,
            acceptedStrategySpec: acceptedStrategySpec,
            mockupStylePreset: mockupStylePreset
        ) else { return }
        if tokenRevisions.last?.tokens == current {
            return
        }
        tokenRevisions.append(
            TokenRevision(
                id: UUID(),
                createdAt: Date(),
                reason: reason,
                tokens: current
            )
        )
        if tokenRevisions.count > Constants.Memory.maxTokenRevisions {
            tokenRevisions.removeFirst(tokenRevisions.count - Constants.Memory.maxTokenRevisions)
        }
    }

    private func propagateGlobalTokenChanges() {
        guard let tokens = latestDesignTokens else { return }
        onTokenChangesPropagated?(tokens)
    }

    private func editableTokenSet(
        mockupGenerator: MockupGenerator,
        latestScope: ProductScopeSnapshot?,
        acceptedStrategySpec: StrategySpec?,
        mockupStylePreset: MockupStylePreset
    ) -> DesignTokenSet? {
        if let latestDesignTokens {
            return latestDesignTokens
        }

        guard let scope = latestScope ?? fallbackScopeForTokenization(acceptedStrategySpec: acceptedStrategySpec) else { return nil }
        return mockupGenerator.defaultTokenSet(
            scope: scope,
            strategySpec: acceptedStrategySpec,
            preset: mockupStylePreset
        )
    }

    private func _normalizedHex(_ raw: String) -> String {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()
        guard cleaned.count == 6, cleaned.allSatisfy(\.isHexDigit) else { return "" }
        return "#\(cleaned)"
    }

    private func _typographySize(from value: String?, fallback: Double) -> Double {
        guard let value else { return fallback }
        let components = value
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let last = components.last, let number = Double(last) {
            return number
        }
        if let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return number
        }
        return fallback
    }

    private func _replacingTypographySize(in value: String, with size: Double) -> String {
        let rounded = Int(size.rounded())
        let parts = value
            .split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard !parts.isEmpty else {
            return "\(rounded)"
        }

        if parts.count == 1 {
            return "\(rounded)"
        }

        var updated = parts
        updated[updated.count - 1] = "\(rounded)"
        return updated.joined(separator: " / ")
    }

    func fallbackScopeForTokenization(acceptedStrategySpec: StrategySpec?) -> ProductScopeSnapshot? {
        guard let acceptedStrategySpec else { return nil }
        return ProductScopeSnapshot(
            appType: inferredAppType(from: acceptedStrategySpec),
            confidence: acceptedStrategySpec.confidence,
            productIntent: acceptedStrategySpec.vision,
            targetUsers: acceptedStrategySpec.targetUsers,
            keyCapabilities: acceptedStrategySpec.mustHaveFeatures,
            openQuestions: acceptedStrategySpec.laterFeatures,
            implementationRoadmap: [],
            summary: acceptedStrategySpec.summary
        )
    }

    private func inferredAppType(from spec: StrategySpec) -> String {
        let vision = spec.vision.lowercased()
        let features = spec.mustHaveFeatures.joined(separator: " ").lowercased()
        let combined = vision + " " + features

        if combined.contains("mobile") || combined.contains("ios") || combined.contains("android") {
            return "Mobile App"
        } else if combined.contains("web") || combined.contains("browser") {
            return "Web App"
        } else if combined.contains("desktop") || combined.contains("macos") || combined.contains("windows") {
            return "Desktop App"
        } else {
            return "App"
        }
    }
}
