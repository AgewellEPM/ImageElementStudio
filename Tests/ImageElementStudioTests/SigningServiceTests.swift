import XCTest
@testable import ImageElementStudio

@MainActor
final class SigningServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeService() -> SigningService {
        SigningService()
    }

    // Valid 40-character hex hashes for test data
    private let hash1 = "ABC123DEF456789012345678901234567890ABCD"
    private let hash2 = "AAAA1111BBBB2222CCCC3333DDDD4444EEEE5555"
    private let hash3 = "FFFF6666AAAA7777BBBB8888CCCC9999DDDD0000"
    private let hash4 = "ABCD1234EFAB5678CDEF9012ABCD3456EFAB7890"

    // MARK: - Initial State

    func testInitialIdentitiesAreEmpty() {
        let service = makeService()
        XCTAssertTrue(service.availableIdentities.isEmpty)
    }

    func testInitialIsDetectingIsFalse() {
        let service = makeService()
        XCTAssertFalse(service.isDetecting)
    }

    func testInitialDetectionErrorIsNil() {
        let service = makeService()
        XCTAssertNil(service.detectionError)
    }

    // MARK: - Identity Parsing

    func testParseEmptyOutputReturnsNoIdentities() {
        let service = makeService()
        let result = service.parseIdentities(from: "")
        XCTAssertTrue(result.isEmpty)
    }

    func testParseSingleValidIdentity() {
        let service = makeService()
        let output = """
          1) \(hash1) "Apple Development: Luke (TEAMID123)"
             1 valid identities found
        """
        let result = service.parseIdentities(from: output)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, hash1)
        XCTAssertTrue(result.first?.name.contains("Apple Development") ?? false)
    }

    func testParseMultipleIdentities() {
        let service = makeService()
        let output = """
          1) \(hash2) "Apple Development: User1 (TEAM1)"
          2) \(hash3) "Apple Distribution: User1 (TEAM1)"
             2 valid identities found
        """
        let result = service.parseIdentities(from: output)
        XCTAssertEqual(result.count, 2)
    }

    func testParseDeveloperIDIdentity() {
        let service = makeService()
        let output = """
          1) \(hash4) "Developer ID Application: Company (TEAMABC)"
             1 valid identities found
        """
        let result = service.parseIdentities(from: output)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.type, .developerID)
    }

    func testParseIdentityExtractsTeamID() {
        let service = makeService()
        let output = """
          1) \(hash1) "Apple Development: Luke (XYZ123ABCD)"
             1 valid identities found
        """
        let result = service.parseIdentities(from: output)
        XCTAssertEqual(result.first?.teamID, "XYZ123ABCD")
    }

    func testParseDevelopmentIdentityType() {
        let service = makeService()
        let output = """
          1) \(hash1) "Apple Development: Luke (TEAM1)"
             1 valid identities found
        """
        let result = service.parseIdentities(from: output)
        XCTAssertEqual(result.first?.type, .development)
    }

    func testParseDistributionIdentityType() {
        let service = makeService()
        let output = """
          1) \(hash1) "Apple Distribution: Luke (TEAM1)"
             1 valid identities found
        """
        let result = service.parseIdentities(from: output)
        XCTAssertEqual(result.first?.type, .distribution)
    }

    func testParseIgnoresSummaryLine() {
        let service = makeService()
        let output = """
          1) \(hash1) "Apple Development: Luke (TEAM1)"
             1 valid identities found
        """
        let result = service.parseIdentities(from: output)
        XCTAssertEqual(result.count, 1)
    }

    func testParseIgnoresInvalidLines() {
        let service = makeService()
        let output = """
        Some random output
        Not a valid line
          1) \(hash1) "Apple Development: Luke (TEAM1)"
        More random text
             1 valid identities found
        """
        let result = service.parseIdentities(from: output)
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - SigningIdentityInfo

    func testSigningIdentityInfoIsHashable() {
        let id1 = SigningService.SigningIdentityInfo(
            id: "ABCDEF1234567890ABCDEF1234567890ABCDEF12", name: "Dev 1", type: .development, teamID: "T1", isValid: true
        )
        let id2 = SigningService.SigningIdentityInfo(
            id: "1234567890ABCDEF1234567890ABCDEF12345678", name: "Dev 2", type: .distribution, teamID: "T2", isValid: true
        )
        var set = Set<SigningService.SigningIdentityInfo>()
        set.insert(id1)
        set.insert(id2)
        XCTAssertEqual(set.count, 2)
    }

    func testSigningIdentityInfoEquality() {
        let id1 = SigningService.SigningIdentityInfo(
            id: "ABCDEF1234567890ABCDEF1234567890ABCDEF12", name: "Dev 1", type: .development, teamID: "T1", isValid: true
        )
        let id1Copy = SigningService.SigningIdentityInfo(
            id: "ABCDEF1234567890ABCDEF1234567890ABCDEF12", name: "Dev 1", type: .development, teamID: "T1", isValid: true
        )
        XCTAssertEqual(id1, id1Copy)
    }

    // MARK: - Signing Configuration Persistence

    func testSaveAndLoadSigningConfig() {
        let service = makeService()
        let config = SigningConfiguration(
            teamID: "TESTTEAM",
            signingIdentity: "Apple Development: Tester",
            codeSignStyle: "Manual"
        )
        service.saveSigningConfig(config)
        let loaded = service.loadSigningConfig()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.teamID, "TESTTEAM")
        XCTAssertEqual(loaded?.signingIdentity, "Apple Development: Tester")
    }
}
