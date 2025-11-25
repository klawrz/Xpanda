import Foundation
import AppKit

struct XP: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var keyword: String
    var expansion: String
    var isRichText: Bool
    var richTextData: Data? // Stores RTF data when isRichText is true
    var outputPlainText: Bool = false // If true, strip formatting when expanding (for JSON, code, etc.)
    var tags: [String]
    var folder: String?
    var dateCreated: Date
    var dateModified: Date

    // Custom decoding to handle backward compatibility
    enum CodingKeys: String, CodingKey {
        case id, keyword, expansion, isRichText, richTextData, outputPlainText, tags, folder, dateCreated, dateModified
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        keyword = try container.decode(String.self, forKey: .keyword)
        expansion = try container.decode(String.self, forKey: .expansion)
        isRichText = try container.decode(Bool.self, forKey: .isRichText)
        richTextData = try container.decodeIfPresent(Data.self, forKey: .richTextData)
        outputPlainText = try container.decodeIfPresent(Bool.self, forKey: .outputPlainText) ?? false
        tags = try container.decode([String].self, forKey: .tags)
        folder = try container.decodeIfPresent(String.self, forKey: .folder)
        dateCreated = try container.decode(Date.self, forKey: .dateCreated)
        dateModified = try container.decode(Date.self, forKey: .dateModified)
    }

    init(
        id: UUID = UUID(),
        keyword: String,
        expansion: String,
        isRichText: Bool = false,
        richTextData: Data? = nil,
        outputPlainText: Bool = false,
        tags: [String] = [],
        folder: String? = nil,
        dateCreated: Date = Date(),
        dateModified: Date = Date()
    ) {
        self.id = id
        self.keyword = keyword
        self.expansion = expansion
        self.isRichText = isRichText
        self.richTextData = richTextData
        self.outputPlainText = outputPlainText
        self.tags = tags
        self.folder = folder
        self.dateCreated = dateCreated
        self.dateModified = dateModified
    }

    // Helper to get attributed string from rich text data
    var attributedString: NSAttributedString? {
        guard isRichText, let data = richTextData else { return nil }

        do {
            let attributedString = try NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
            return attributedString
        } catch {
            print("Error loading rich text data: \(error)")
            // Fallback to plain text if RTF fails to load
            return NSAttributedString(string: expansion)
        }
    }

    // Helper to create rich text data from attributed string
    static func makeRichTextData(from attributedString: NSAttributedString) -> Data? {
        guard attributedString.length > 0 else {
            // Return nil for empty strings
            return nil
        }

        do {
            let data = try attributedString.data(
                from: NSRange(location: 0, length: attributedString.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            print("Created RTF data: \(data.count) bytes")
            return data
        } catch {
            print("Error creating rich text data: \(error)")
            return nil
        }
    }

    // Helper to create attributed string from plain text
    static func makeAttributedString(from plainText: String) -> NSAttributedString {
        return NSAttributedString(string: plainText)
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
