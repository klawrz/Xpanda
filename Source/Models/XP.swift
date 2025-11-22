import Foundation

struct XP: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var keyword: String
    var expansion: String
    var isRichText: Bool
    var tags: [String]
    var folder: String?
    var dateCreated: Date
    var dateModified: Date

    init(
        id: UUID = UUID(),
        keyword: String,
        expansion: String,
        isRichText: Bool = false,
        tags: [String] = [],
        folder: String? = nil,
        dateCreated: Date = Date(),
        dateModified: Date = Date()
    ) {
        self.id = id
        self.keyword = keyword
        self.expansion = expansion
        self.isRichText = isRichText
        self.tags = tags
        self.folder = folder
        self.dateCreated = dateCreated
        self.dateModified = dateModified
    }

    static func == (lhs: XP, rhs: XP) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// Sample data for testing
extension XP {
    static let samples = [
        XP(keyword: "xintro", expansion: "Hi, this is Adam!", tags: ["greeting"]),
        XP(keyword: "xemail", expansion: "adam@example.com", tags: ["personal"]),
        XP(keyword: "xsig", expansion: "Best regards,\nAdam Traversy", tags: ["signature", "email"])
    ]
}
