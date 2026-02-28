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
        let normalized = normalizedHex(value)
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
        tokens.radius[key] = min(28, max(2, value))
        latestDesignTokens = tokens
        propagateGlobalTokenChanges()
    }

    func tokenTypographySize(_ key: String, fallback: Double) -> Double {
        guard let tokens = latestDesignTokens else { return fallback }
        return typographySize(from: tokens.typography[key], fallback: fallback)
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
        tokens.typography[key] = replacingTypographySize(in: base, with: value)
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
        if tokenRevisions.count > 80 {
            tokenRevisions.removeFirst(tokenRevisions.count - 80)
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

    private func normalizedHex(_ raw: String) -> String {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()
        guard cleaned.count == 6, cleaned.allSatisfy(\.isHexDigit) else { return "" }
        return "#\(cleaned)"
    }

    private func typographySize(from value: String?, fallback: Double) -> Double {
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

    private func replacingTypographySize(in value: String, with size: Double) -> String {
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
