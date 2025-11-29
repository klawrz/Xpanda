import Foundation
import AppKit

// MARK: - Placeholder Token System

// Represents a placeholder token that can be inserted into rich text
enum PlaceholderToken: String, CaseIterable {
    case clipboard = "clipboard"
    case date = "date"
    case time = "time"
    case cursor = "cursor"
    case fillIn = "fillin"

    // The text format used for storage (persists through RTF save/load)
    var storageText: String {
        return "{{\(self.rawValue)}}"
    }

    // The display label shown in the pill
    var displayLabel: String {
        switch self {
        case .clipboard: return "clipboard"
        case .date: return "date"
        case .time: return "time"
        case .cursor: return "cursor"
        case .fillIn: return "fill-in"
        }
    }

    // Detect if a string contains this token
    static func detectToken(in text: String) -> [(token: PlaceholderToken, range: NSRange)] {
        var results: [(PlaceholderToken, NSRange)] = []
        let nsText = text as NSString

        for token in PlaceholderToken.allCases {
            var searchRange = NSRange(location: 0, length: nsText.length)

            while searchRange.location < nsText.length {
                let foundRange = nsText.range(of: token.storageText, options: [], range: searchRange)

                if foundRange.location == NSNotFound {
                    break
                }

                results.append((token, foundRange))

                // Move search position forward
                searchRange.location = foundRange.location + foundRange.length
                searchRange.length = nsText.length - searchRange.location
            }
        }

        // Sort by location
        return results.sorted(by: { $0.1.location < $1.1.location })
    }
}

// Custom attachment cell for rendering pills
class PlaceholderPillAttachmentCell: NSTextAttachmentCell {
    let token: PlaceholderToken

    init(token: PlaceholderToken) {
        self.token = token
        super.init()
    }

    required init(coder: NSCoder) {
        self.token = .clipboard
        super.init(coder: coder)
    }

    override func cellSize() -> NSSize {
        return NSSize(width: 80, height: 18)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        // Draw rounded rectangle (oval pill)
        let path = NSBezierPath(roundedRect: cellFrame, xRadius: 9, yRadius: 9)

        // Fill with light blue background
        NSColor.systemBlue.withAlphaComponent(0.15).setFill()
        path.fill()

        // Draw blue border
        NSColor.systemBlue.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 1.0
        path.stroke()

        // Draw label text
        let text = token.displayLabel
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.systemBlue
        ]
        let textSize = text.size(withAttributes: attrs)
        let textRect = NSRect(
            x: cellFrame.origin.x + (cellFrame.width - textSize.width) / 2,
            y: cellFrame.origin.y + (cellFrame.height - textSize.height) / 2 + 1,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attrs)
    }

    override func cellBaselineOffset() -> NSPoint {
        return NSPoint(x: 0, y: -3)
    }
}

// Helper class to render placeholder pills
class PlaceholderPillRenderer {
    // Convert storage text to display attributed string with pill styling
    static func createDisplayString(for token: PlaceholderToken) -> NSAttributedString {
        let attachment = NSTextAttachment()

        // Use custom cell for rendering
        attachment.attachmentCell = PlaceholderPillAttachmentCell(token: token)

        // Store the token type in the attachment for later retrieval
        let markerData = token.storageText.data(using: .utf8)!
        let wrapper = FileWrapper(regularFileWithContents: markerData)
        wrapper.preferredFilename = "\(token.rawValue).txt"
        attachment.fileWrapper = wrapper

        return NSAttributedString(attachment: attachment)
    }
}

// Helper class for converting between storage and display formats
class XPHelper {
    // Convert storage format ({{clipboard}}) to display format (pills with attachments)
    static func convertStorageToDisplay(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        let text = mutableString.string

        // Find all placeholder tokens
        let tokens = PlaceholderToken.detectToken(in: text)

        // Replace in reverse order to maintain correct indices
        for (token, range) in tokens.reversed() {
            // Create pill attachment
            let pillString = PlaceholderPillRenderer.createDisplayString(for: token)

            // Replace the storage text with the pill
            mutableString.replaceCharacters(in: range, with: pillString)
        }

        return mutableString
    }

    // Convert display format (pills with attachments) to storage format ({{clipboard}})
    static func convertDisplayToStorage(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        let fullRange = NSRange(location: 0, length: mutableString.length)

        var replacements: [(range: NSRange, text: String)] = []

        // Find all attachments
        mutableString.enumerateAttribute(.attachment, in: fullRange, options: [.reverse]) { value, range, _ in
            if let attachment = value as? NSTextAttachment,
               let fileWrapper = attachment.fileWrapper,
               let data = fileWrapper.regularFileContents,
               let storageText = String(data: data, encoding: .utf8),
               storageText.hasPrefix("{{") && storageText.hasSuffix("}}") {
                // This is one of our placeholder tokens
                replacements.append((range: range, text: storageText))
            }
        }

        // Replace pills with storage text
        for replacement in replacements {
            let storageString = NSAttributedString(string: replacement.text)
            mutableString.replaceCharacters(in: replacement.range, with: storageString)
        }

        return mutableString
    }
}

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
            let loadedString = try NSAttributedString(
                data: data,
                options: [NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )

            // Convert storage format to display format ({{clipboard}} -> pill)
            let displayString = XPHelper.convertStorageToDisplay(loadedString)
            return displayString
        } catch {
            print("Error loading rich text data: \(error)")
            // Fallback to plain text if RTF fails to load
            return NSAttributedString(string: expansion)
        }
    }

    // Helper to restore clipboard attachments from RTF
    private func restoreClipboardAttachments(in attributedString: NSAttributedString) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        let fullRange = NSRange(location: 0, length: mutableString.length)

        print("🔄 Restoring clipboard attachments")
        print("   String: \(mutableString.string)")
        print("   Length: \(mutableString.length)")

        var replacements: [(range: NSRange, attachment: ClipboardAttachment)] = []
        var attachmentCount = 0

        // Find all attachments and check if they're clipboard placeholders
        mutableString.enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, _ in
            attachmentCount += 1
            if let attachment = value as? NSTextAttachment {
                print("   Found attachment #\(attachmentCount) at range: \(range)")
                print("      Has fileWrapper: \(attachment.fileWrapper != nil)")

                if let fileWrapper = attachment.fileWrapper {
                    print("      FileWrapper filename: \(fileWrapper.preferredFilename ?? "nil")")
                    if let data = fileWrapper.regularFileContents {
                        print("      FileWrapper data size: \(data.count) bytes")
                        if let content = String(data: data, encoding: .utf8) {
                            print("      FileWrapper content: \(content)")
                            if content == ClipboardAttachment.clipboardMarker {
                                // This is a clipboard attachment - create a new one
                                let clipboardAttachment = ClipboardAttachment()
                                replacements.append((range: range, attachment: clipboardAttachment))
                                print("      ✓ Identified as clipboard placeholder!")
                            }
                        }
                    }
                }
            }
        }

        print("   Total attachments found: \(attachmentCount)")
        print("   Clipboard attachments to restore: \(replacements.count)")

        // Replace generic attachments with ClipboardAttachments
        for replacement in replacements.reversed() {
            mutableString.removeAttribute(.attachment, range: replacement.range)
            mutableString.addAttribute(.attachment, value: replacement.attachment, range: replacement.range)
        }

        return mutableString
    }

    // Helper to create rich text data from attributed string
    static func makeRichTextData(from attributedString: NSAttributedString) -> Data? {
        guard attributedString.length > 0 else {
            // Return nil for empty strings
            return nil
        }

        // Convert pills to storage format before saving
        let storageString = XPHelper.convertDisplayToStorage(attributedString)

        print("💾 Saving rich text data")
        print("   Original: \(attributedString.string)")
        print("   Storage:  \(storageString.string)")

        do {
            let data = try storageString.data(
                from: NSRange(location: 0, length: storageString.length),
                documentAttributes: [NSAttributedString.DocumentAttributeKey.documentType: NSAttributedString.DocumentType.rtf]
            )
            print("   ✓ Created RTF data: \(data.count) bytes")
            return data
        } catch {
            print("   ✗ Error creating rich text data: \(error)")
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
