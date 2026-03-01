import Foundation

enum ReviewApprovalState: String, Codable, CaseIterable, Hashable, Identifiable {
    case pending
    case approved
    case changesRequested

    var id: String { rawValue }
}

struct DesignReviewComment: Identifiable, Codable, Hashable {
    var id: UUID
    var createdAt: Date
    var author: String
    var assignee: String? = nil
    var dueDate: Date? = nil
    var message: String
    var artboardID: UUID?
    var elementID: UUID?
    var resolved: Bool
}
