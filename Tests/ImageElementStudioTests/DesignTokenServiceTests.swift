import XCTest
@testable import ImageElementStudio

@MainActor
final class DesignTokenServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeService(withTokens: Bool = true) -> DesignTokenService {
        let service = DesignTokenService()
        if withTokens {
            service.latestDesignTokens = DesignTokenSet(
                colors: [
                    "accent.primary": "#2F6BFF",
                    "surface.base": "#F8FAFF",
                ],
                typography: [
                    "heading": "Bold / 24",
                    "body": "Regular / 14",
                ],
                spacing: [:],
                radius: [
                    "control": 8,
                    "panel": 12,
                ],
                shadow: [:],
                motion: [:]
            )
        }
        return service
    }

    // MARK: - tokenColorValue

    func testTokenColorValueReturnsExistingColor() {
        let service = makeService()

        let value = service.tokenColorValue("accent.primary", fallback: "#000000")

        XCTAssertEqual(value, "#2F6BFF")
    }

    func testTokenColorValueReturnsFallbackForMissingKey() {
        let service = makeService()

        let value = service.tokenColorValue("nonexistent.color", fallback: "#FF0000")

        XCTAssertEqual(value, "#FF0000")
    }

    func testTokenColorValueReturnsFallbackWhenNoTokenSet() {
        let service = makeService(withTokens: false)

        let value = service.tokenColorValue("accent.primary", fallback: "#AABBCC")

        XCTAssertEqual(value, "#AABBCC")
    }

    // MARK: - tokenRadiusValue

    func testTokenRadiusValueReturnsExistingRadius() {
        let service = makeService()

        let value = service.tokenRadiusValue("control", fallback: 4)

        XCTAssertEqual(value, 8)
    }

    func testTokenRadiusValueReturnsFallbackForMissingKey() {
        let service = makeService()

        let value = service.tokenRadiusValue("nonexistent", fallback: 4)

        XCTAssertEqual(value, 4)
    }

    // MARK: - normalizedHex

    func testNormalizedHexReturnsCorrectFormatWithHash() {
        let service = makeService()

        XCTAssertEqual(service.normalizedHex("#aaBBcc"), "#AABBCC")
    }

    func testNormalizedHexReturnsCorrectFormatWithoutHash() {
        let service = makeService()

        XCTAssertEqual(service.normalizedHex("aabbcc"), "#AABBCC")
    }

    func testNormalizedHexReturnsEmptyForInvalidInput() {
        let service = makeService()

        XCTAssertEqual(service.normalizedHex("xyz"), "")
        XCTAssertEqual(service.normalizedHex("12345"), "")
        XCTAssertEqual(service.normalizedHex("#GGHHII"), "")
    }

    func testNormalizedHexTrimsWhitespace() {
        let service = makeService()

        XCTAssertEqual(service.normalizedHex("  #aabbcc  "), "#AABBCC")
    }

    // MARK: - typographySize

    func testTypographySizeExtractsSizeFromSlashFormat() {
        let service = makeService()

        XCTAssertEqual(service.typographySize(from: "Bold / 24", fallback: 16), 24)
    }

    func testTypographySizeExtractsPlainNumber() {
        let service = makeService()

        XCTAssertEqual(service.typographySize(from: "14", fallback: 16), 14)
    }

    func testTypographySizeReturnsFallbackForNil() {
        let service = makeService()

        XCTAssertEqual(service.typographySize(from: nil, fallback: 16), 16)
    }

    func testTypographySizeReturnsFallbackForNonNumeric() {
        let service = makeService()

        XCTAssertEqual(service.typographySize(from: "Bold", fallback: 16), 16)
    }

    // MARK: - replacingTypographySize

    func testReplacingTypographySizeInSlashFormat() {
        let service = makeService()

        let result = service.replacingTypographySize(in: "Bold / 24", with: 18)

        XCTAssertEqual(result, "Bold / 18")
    }

    func testReplacingTypographySizeInPlainNumber() {
        let service = makeService()

        let result = service.replacingTypographySize(in: "14", with: 20)

        XCTAssertEqual(result, "20")
    }

    // MARK: - rollbackTokenRevision

    func testRollbackTokenRevisionRestoresPreviousTokenSet() {
        let service = makeService()
        let originalTokens = service.latestDesignTokens!
        let revisionID = UUID(uuidString: "00000000-0000-0000-0000-000000000701")!
        let previousTokens = DesignTokenSet(
            colors: ["old.color": "#111111"],
            typography: [:],
            spacing: [:],
            radius: [:],
            shadow: [:],
            motion: [:]
        )
        service.tokenRevisions = [
            TokenRevision(id: revisionID, createdAt: Date(), reason: "test", tokens: previousTokens),
        ]

        service.rollbackTokenRevision(revisionID)

        XCTAssertEqual(service.latestDesignTokens, previousTokens)
        XCTAssertNotEqual(service.latestDesignTokens, originalTokens)
    }

    func testRollbackTokenRevisionDoesNothingForUnknownID() {
        let service = makeService()
        let originalTokens = service.latestDesignTokens

        service.rollbackTokenRevision(UUID())

        XCTAssertEqual(service.latestDesignTokens, originalTokens)
    }

    // MARK: - clearTokenRevisionHistory

    func testClearTokenRevisionHistoryClearsAll() {
        let service = makeService()
        let revisionID = UUID(uuidString: "00000000-0000-0000-0000-000000000702")!
        service.tokenRevisions = [
            TokenRevision(
                id: revisionID,
                createdAt: Date(),
                reason: "test",
                tokens: service.latestDesignTokens!
            ),
        ]

        service.clearTokenRevisionHistory()

        XCTAssertTrue(service.tokenRevisions.isEmpty)
    }

    // MARK: - updateTokenColor (integration with real MockupGenerator)

    func testUpdateTokenColorUpdatesColorAndCreatesRevision() {
        let service = makeService()
        let mockupGenerator = MockupGenerator()
        var propagatedTokens: DesignTokenSet?
        service.onTokenChangesPropagated = { tokens in
            propagatedTokens = tokens
        }

        service.updateTokenColor(
            "accent.primary",
            value: "#FF0000",
            mockupGenerator: mockupGenerator,
            latestScope: nil,
            acceptedStrategySpec: nil,
            mockupStylePreset: .apple_hig
        )

        XCTAssertEqual(service.latestDesignTokens?.colors["accent.primary"], "#FF0000")
        XCTAssertEqual(service.tokenRevisions.count, 1)
        XCTAssertNotNil(propagatedTokens)
    }

    func testUpdateTokenColorIgnoresInvalidHex() {
        let service = makeService()

        service.updateTokenColor(
            "accent.primary",
            value: "not-a-hex",
            mockupGenerator: MockupGenerator(),
            latestScope: nil,
            acceptedStrategySpec: nil,
            mockupStylePreset: .apple_hig
        )

        // Should remain unchanged
        XCTAssertEqual(service.latestDesignTokens?.colors["accent.primary"], "#2F6BFF")
    }

    // MARK: - updateTokenRadius

    func testUpdateTokenRadiusUpdatesValueAndClampsRange() {
        let service = makeService()
        let mockupGenerator = MockupGenerator()

        service.updateTokenRadius(
            "control",
            value: 16,
            mockupGenerator: mockupGenerator,
            latestScope: nil,
            acceptedStrategySpec: nil,
            mockupStylePreset: .apple_hig
        )

        XCTAssertEqual(service.latestDesignTokens?.radius["control"], 16)
    }

    func testUpdateTokenRadiusClampsToMaximum() {
        let service = makeService()
        let mockupGenerator = MockupGenerator()

        service.updateTokenRadius(
            "control",
            value: 100,
            mockupGenerator: mockupGenerator,
            latestScope: nil,
            acceptedStrategySpec: nil,
            mockupStylePreset: .apple_hig
        )

        XCTAssertEqual(service.latestDesignTokens?.radius["control"], 28)
    }

    func testUpdateTokenRadiusClampsToMinimum() {
        let service = makeService()
        let mockupGenerator = MockupGenerator()

        service.updateTokenRadius(
            "control",
            value: 0,
            mockupGenerator: mockupGenerator,
            latestScope: nil,
            acceptedStrategySpec: nil,
            mockupStylePreset: .apple_hig
        )

        XCTAssertEqual(service.latestDesignTokens?.radius["control"], 2)
    }
}
