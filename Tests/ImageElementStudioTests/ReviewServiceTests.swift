import XCTest
@testable import ImageElementStudio

@MainActor
final class ReviewServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeService() -> ReviewService {
        ReviewService()
    }

    private let commentID = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
    private let artboardID = UUID(uuidString: "00000000-0000-0000-0000-000000000502")!
    private let elementID = UUID(uuidString: "00000000-0000-0000-0000-000000000503")!

    private func makeUnresolvedComment(
        id: UUID? = nil,
        dueDate: Date? = nil
    ) -> DesignReviewComment {
        DesignReviewComment(
            id: id ?? commentID,
            createdAt: Date(timeIntervalSince1970: 100),
            author: "QA",
            assignee: "Dev",
            dueDate: dueDate,
            message: "Fix alignment.",
            artboardID: artboardID,
            elementID: elementID,
            resolved: false
        )
    }

    // MARK: - addReviewComment

    func testAddReviewCommentAppendsNewComment() {
        let service = makeService()
        service.reviewCommentDraft = "Check padding."

        service.addReviewComment("Check padding.", artboardID: artboardID, elementID: elementID)

        XCTAssertEqual(service.reviewComments.count, 1)
        XCTAssertEqual(service.reviewComments.first?.message, "Check padding.")
        XCTAssertEqual(service.reviewComments.first?.artboardID, artboardID)
        XCTAssertEqual(service.reviewComments.first?.elementID, elementID)
        XCTAssertFalse(service.reviewComments.first?.resolved ?? true)
    }

    func testAddReviewCommentIgnoresEmptyMessage() {
        let service = makeService()

        service.addReviewComment("   ", artboardID: nil, elementID: nil)

        XCTAssertTrue(service.reviewComments.isEmpty)
    }

    func testAddReviewCommentResetsDraftFields() {
        let service = makeService()
        service.reviewCommentAssigneeDraft = "Alice"
        service.reviewCommentHasDueDate = true

        service.addReviewComment("New comment.", artboardID: nil, elementID: nil)

        XCTAssertEqual(service.reviewCommentAssigneeDraft, "")
        XCTAssertFalse(service.reviewCommentHasDueDate)
        XCTAssertEqual(service.reviewCommentDraft, "")
    }

    func testAddReviewCommentWithAssigneeAndDueDate() {
        let service = makeService()
        service.reviewCommentAssigneeDraft = "Bob"
        service.reviewCommentHasDueDate = true
        service.reviewCommentDueDateDraft = Date(timeIntervalSince1970: 0)

        service.addReviewComment("Fix button.", artboardID: nil, elementID: nil)

        XCTAssertEqual(service.reviewComments.first?.assignee, "Bob")
        XCTAssertNotNil(service.reviewComments.first?.dueDate)
    }

    func testAddReviewCommentDowngradesApprovalFromApprovedToChangesRequested() {
        let service = makeService()
        service.reviewApprovalState = .approved

        service.addReviewComment("New finding.", artboardID: nil, elementID: nil)

        XCTAssertEqual(service.reviewApprovalState, .changesRequested)
    }

    // MARK: - toggleReviewCommentResolution

    func testToggleReviewCommentResolutionResolvesUnresolvedComment() {
        let service = makeService()
        service.reviewComments = [makeUnresolvedComment()]

        service.toggleReviewCommentResolution(commentID)

        XCTAssertTrue(service.reviewComments.first?.resolved ?? false)
    }

    func testToggleReviewCommentResolutionUnresolvesResolvedComment() {
        let service = makeService()
        var comment = makeUnresolvedComment()
        comment.resolved = true
        service.reviewComments = [comment]

        service.toggleReviewCommentResolution(commentID)

        XCTAssertFalse(service.reviewComments.first?.resolved ?? true)
    }

    func testUnresolvingCommentDowngradesApprovalFromApproved() {
        let service = makeService()
        var comment = makeUnresolvedComment()
        comment.resolved = true
        service.reviewComments = [comment]
        service.reviewApprovalState = .approved

        service.toggleReviewCommentResolution(commentID)

        XCTAssertEqual(service.reviewApprovalState, .changesRequested)
    }

    // MARK: - resolveAllReviewComments

    func testResolveAllReviewCommentsMarksAllResolved() {
        let service = makeService()
        let id2 = UUID(uuidString: "00000000-0000-0000-0000-000000000504")!
        service.reviewComments = [
            makeUnresolvedComment(),
            makeUnresolvedComment(id: id2),
        ]

        service.resolveAllReviewComments()

        XCTAssertTrue(service.reviewComments.allSatisfy(\.resolved))
        XCTAssertEqual(service.unresolvedReviewCommentCount, 0)
    }

    // MARK: - clearResolvedReviewComments

    func testClearResolvedReviewCommentsRemovesOnlyResolved() {
        let service = makeService()
        let id2 = UUID(uuidString: "00000000-0000-0000-0000-000000000504")!
        var resolved = makeUnresolvedComment(id: id2)
        resolved.resolved = true
        service.reviewComments = [makeUnresolvedComment(), resolved]

        service.clearResolvedReviewComments()

        XCTAssertEqual(service.reviewComments.count, 1)
        XCTAssertEqual(service.reviewComments.first?.id, commentID)
    }

    // MARK: - deleteReviewComment

    func testDeleteReviewCommentRemovesSpecificComment() {
        let service = makeService()
        let id2 = UUID(uuidString: "00000000-0000-0000-0000-000000000504")!
        service.reviewComments = [makeUnresolvedComment(), makeUnresolvedComment(id: id2)]

        service.deleteReviewComment(commentID)

        XCTAssertEqual(service.reviewComments.count, 1)
        XCTAssertEqual(service.reviewComments.first?.id, id2)
    }

    // MARK: - isReviewCommentOverdue

    func testIsReviewCommentOverdueReturnsTrueWhenPastDueDate() {
        let service = makeService()
        let comment = makeUnresolvedComment(dueDate: Date(timeIntervalSince1970: 0))
        // Reference date is well past the due date
        let referenceDate = Date(timeIntervalSince1970: 200_000)

        XCTAssertTrue(service.isReviewCommentOverdue(comment, referenceDate: referenceDate))
    }

    func testIsReviewCommentOverdueReturnsFalseWhenResolved() {
        let service = makeService()
        var comment = makeUnresolvedComment(dueDate: Date(timeIntervalSince1970: 0))
        comment.resolved = true
        let referenceDate = Date(timeIntervalSince1970: 200_000)

        XCTAssertFalse(service.isReviewCommentOverdue(comment, referenceDate: referenceDate))
    }

    func testIsReviewCommentOverdueReturnsFalseWhenNoDueDate() {
        let service = makeService()
        let comment = makeUnresolvedComment(dueDate: nil)

        XCTAssertFalse(service.isReviewCommentOverdue(comment, referenceDate: Date()))
    }

    func testIsReviewCommentOverdueReturnsFalseWhenBeforeDueDate() {
        let service = makeService()
        let farFuture = Date(timeIntervalSinceNow: 365 * 24 * 3600)
        let comment = makeUnresolvedComment(dueDate: farFuture)

        XCTAssertFalse(service.isReviewCommentOverdue(comment, referenceDate: Date()))
    }

    // MARK: - setReviewApprovalState

    func testSetReviewApprovalStateToApprovedSucceedsWhenNoUnresolvedComments() {
        let service = makeService()

        let result = service.setReviewApprovalState(.approved)

        XCTAssertTrue(result)
        XCTAssertEqual(service.reviewApprovalState, .approved)
    }

    func testSetReviewApprovalStateToApprovedFailsWithUnresolvedComments() {
        let service = makeService()
        service.reviewComments = [makeUnresolvedComment()]

        let result = service.setReviewApprovalState(.approved)

        XCTAssertFalse(result)
        XCTAssertEqual(service.reviewApprovalState, .changesRequested)
    }

    func testSetReviewApprovalStateToChangesRequestedAlwaysSucceeds() {
        let service = makeService()
        service.reviewApprovalState = .approved

        let result = service.setReviewApprovalState(.changesRequested)

        XCTAssertTrue(result)
        XCTAssertEqual(service.reviewApprovalState, .changesRequested)
    }

    // MARK: - reviewGateBlockReason / canExportBuildArtifacts

    func testReviewGateBlockReasonShowsApprovalRequiredWhenPending() {
        let service = makeService()
        service.reviewApprovalState = .pending

        XCTAssertEqual(service.reviewGateBlockReason, "Approval must be set to Approved.")
        XCTAssertFalse(service.canExportBuildArtifacts)
    }

    func testReviewGateBlockReasonShowsUnresolvedCommentsMessage() {
        let service = makeService()
        service.reviewApprovalState = .approved
        service.reviewComments = [makeUnresolvedComment()]

        XCTAssertEqual(service.reviewGateBlockReason, "Resolve 1 review comments before export.")
        XCTAssertFalse(service.canExportBuildArtifacts)
    }

    func testReviewGateBlockReasonIsNilWhenApprovedAndAllResolved() {
        let service = makeService()
        service.reviewApprovalState = .approved

        XCTAssertNil(service.reviewGateBlockReason)
        XCTAssertTrue(service.canExportBuildArtifacts)
    }

    // MARK: - Computed properties

    func testOverdueReviewCommentCountReflectsOverdueComments() {
        let service = makeService()
        service.reviewComments = [
            makeUnresolvedComment(dueDate: Date(timeIntervalSince1970: 0)),
        ]

        // The overdue count uses Date() internally, and epoch 0 is definitely past
        XCTAssertEqual(service.overdueReviewCommentCount, 1)
    }

    func testReviewStatusLineContainsApprovalStateAndOpenCount() {
        let service = makeService()
        service.reviewApprovalState = .changesRequested
        service.reviewComments = [makeUnresolvedComment()]

        let line = service.reviewStatusLine
        XCTAssertTrue(line.contains("Changesrequested") || line.contains("changesRequested") || line.contains("Changesrequested") || line.localizedCaseInsensitiveContains("changesrequested"))
        XCTAssertTrue(line.contains("1 open comments"))
    }
}
