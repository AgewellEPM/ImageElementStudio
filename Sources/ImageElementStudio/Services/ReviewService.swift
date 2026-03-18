import Foundation

@MainActor
final class ReviewService: ObservableObject {
    @Published var reviewComments: [DesignReviewComment] = []
    @Published var reviewApprovalState: ReviewApprovalState = .approved
    @Published var reviewCommentDraft: String = ""
    @Published var reviewCommentAssigneeDraft: String = ""
    @Published var reviewCommentHasDueDate: Bool = false
    @Published var reviewCommentDueDateDraft: Date = Date()

    // MARK: - Computed Properties

    var reviewStatusLine: String {
        let unresolved = unresolvedReviewCommentCount
        let overdue = overdueReviewCommentCount
        let overdueFragment = overdue > 0 ? " · \(overdue) overdue" : ""
        return "\(reviewApprovalState.rawValue.capitalized) · \(unresolved) open comments\(overdueFragment)"
    }

    var unresolvedReviewCommentCount: Int {
        reviewComments.filter { !$0.resolved }.count
    }

    var resolvedReviewCommentCount: Int {
        reviewComments.count - unresolvedReviewCommentCount
    }

    var reviewCommentsPreview: [DesignReviewComment] {
        reviewComments.sorted { $0.createdAt > $1.createdAt }
    }

    var overdueReviewCommentCount: Int {
        reviewComments.filter { isReviewCommentOverdue($0) }.count
    }

    var reviewGateBlockReason: String? {
        if reviewApprovalState != .approved {
            return "Approval must be set to Approved."
        }
        if unresolvedReviewCommentCount > 0 {
            return "Resolve \(unresolvedReviewCommentCount) review comments before export."
        }
        return nil
    }

    var canExportBuildArtifacts: Bool {
        reviewGateBlockReason == nil
    }

    var reviewGateStatusLine: String {
        if let reviewGateBlockReason {
            return "Export blocked: \(reviewGateBlockReason)"
        }
        return "Export gate clear."
    }

    // MARK: - Public Methods

    func addReviewComment(_ rawMessage: String, artboardID: UUID?, elementID: UUID?) {
        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        let assignee = reviewCommentAssigneeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAssignee = assignee.isEmpty ? nil : assignee
        let dueDate = reviewCommentHasDueDate ? reviewCommentDueDateDraft : nil
        if reviewApprovalState == .approved {
            reviewApprovalState = .changesRequested
        }
        reviewComments.append(
            DesignReviewComment(
                id: UUID(),
                createdAt: Date(),
                author: "Designer",
                assignee: normalizedAssignee,
                dueDate: dueDate,
                message: message,
                artboardID: artboardID,
                elementID: elementID,
                resolved: false
            )
        )
        reviewCommentDraft = ""
        reviewCommentAssigneeDraft = ""
        reviewCommentHasDueDate = false
        reviewCommentDueDateDraft = Date()
    }

    func toggleReviewCommentResolution(_ commentID: UUID) {
        guard let index = reviewComments.firstIndex(where: { $0.id == commentID }) else { return }
        reviewComments[index].resolved.toggle()
        if !reviewComments[index].resolved, reviewApprovalState == .approved {
            reviewApprovalState = .changesRequested
        }
    }

    func resolveAllReviewComments() {
        guard reviewComments.contains(where: { !$0.resolved }) else { return }
        for index in reviewComments.indices where !reviewComments[index].resolved {
            reviewComments[index].resolved = true
        }
    }

    func clearResolvedReviewComments() {
        reviewComments.removeAll(where: \.resolved)
    }

    func deleteReviewComment(_ commentID: UUID) {
        reviewComments.removeAll(where: { $0.id == commentID })
    }

    func isReviewCommentOverdue(_ comment: DesignReviewComment, referenceDate: Date = Date()) -> Bool {
        guard !comment.resolved, let dueDate = comment.dueDate else { return false }
        let calendar = Calendar.current
        let startOfDueDay = calendar.startOfDay(for: dueDate)
        let endOfDueDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDueDay) ?? dueDate
        return referenceDate > endOfDueDay
    }

    func reviewCommentDueDateLine(_ comment: DesignReviewComment) -> String {
        guard let dueDate = comment.dueDate else { return "No due date" }
        return "Due \(dueDate.formatted(date: .abbreviated, time: .omitted))"
    }

    @discardableResult
    func setReviewApprovalState(_ state: ReviewApprovalState) -> Bool {
        if state == .approved {
            let unresolved = reviewComments.contains { !$0.resolved }
            if unresolved {
                reviewApprovalState = .changesRequested
                return false
            }
        }
        reviewApprovalState = state
        return true
    }
}
