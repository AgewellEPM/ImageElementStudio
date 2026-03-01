import Foundation

struct ChatMessage: Identifiable, Hashable {
    enum Role: String, Hashable {
        case system
        case user
        case assistant
    }

    var id: UUID = UUID()
    var role: Role
    var text: String
    var createdAt: Date = Date()
}
