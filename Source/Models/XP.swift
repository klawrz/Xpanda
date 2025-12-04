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
        // Calculate size based on text width with padding (matching sidebar pills)
        let text = token.displayLabel
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.systemBlue
        ]
        let textSize = text.size(withAttributes: attrs)

        // Add 8 points horizontal padding (4 on each side, matching sidebar)
        return NSSize(width: textSize.width + 8, height: 18)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        // Draw rounded rectangle pill
        let path = NSBezierPath(roundedRect: cellFrame, xRadius: 3, yRadius: 3)

        // Fill with light grey background (matching sidebar)
        NSColor.systemGray.withAlphaComponent(0.2).setFill()
        path.fill()

        // Draw grey border
        NSColor.systemGray.withAlphaComponent(0.3).setStroke()
        path.lineWidth = 1.0
        path.stroke()

        // Draw label text
        let text = token.displayLabel
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.systemGray
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

// Custom attachment cell for fill-in pills
class FillInPillAttachmentCell: NSTextAttachmentCell {
    let label: String
    let defaultValue: String

    init(label: String, defaultValue: String) {
        self.label = label
        self.defaultValue = defaultValue
        super.init()
    }

    required init(coder: NSCoder) {
        self.label = ""
        self.defaultValue = ""
        super.init(coder: coder)
    }

    override func cellSize() -> NSSize {
        // Show "single fill" as the display text
        let text = "single fill"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.systemGray
        ]
        let textSize = text.size(withAttributes: attrs)
        return NSSize(width: textSize.width + 8, height: 18)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        // Draw rounded rectangle pill (same style as placeholder pills)
        let path = NSBezierPath(roundedRect: cellFrame, xRadius: 3, yRadius: 3)

        // Fill with light grey background
        NSColor.systemGray.withAlphaComponent(0.2).setFill()
        path.fill()

        // Draw grey border
        NSColor.systemGray.withAlphaComponent(0.3).setStroke()
        path.lineWidth = 1.0
        path.stroke()

        // Draw label text
        let text = "single fill"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.systemGray
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

class MultiLineFillInPillAttachmentCell: NSTextAttachmentCell {
    let label: String
    let defaultValue: String

    init(label: String, defaultValue: String) {
        self.label = label
        self.defaultValue = defaultValue
        super.init()
    }

    required init(coder: NSCoder) {
        self.label = ""
        self.defaultValue = ""
        super.init(coder: coder)
    }

    override func cellSize() -> NSSize {
        // Show "multi fill" as the display text
        let text = "multi fill"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.systemGray
        ]
        let textSize = text.size(withAttributes: attrs)
        return NSSize(width: textSize.width + 8, height: 18)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        // Draw rounded rectangle pill (same style as placeholder pills)
        let path = NSBezierPath(roundedRect: cellFrame, xRadius: 3, yRadius: 3)

        // Fill with light grey background
        NSColor.systemGray.withAlphaComponent(0.2).setFill()
        path.fill()

        // Draw grey border
        NSColor.systemGray.withAlphaComponent(0.3).setStroke()
        path.lineWidth = 1.0
        path.stroke()

        // Draw label text
        let text = "multi fill"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.systemGray
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

class SelectFillInPillAttachmentCell: NSTextAttachmentCell {
    let label: String
    let options: [String]
    let defaultIndex: Int

    init(label: String, options: [String], defaultIndex: Int) {
        self.label = label
        self.options = options
        self.defaultIndex = defaultIndex
        super.init()
    }

    required init(coder: NSCoder) {
        self.label = ""
        self.options = []
        self.defaultIndex = 0
        super.init(coder: coder)
    }

    override func cellSize() -> NSSize {
        // Show "select fill" as the display text
        let text = "select fill"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.systemPurple
        ]
        let textSize = text.size(withAttributes: attrs)
        return NSSize(width: textSize.width + 8, height: 18)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        // Draw rounded rectangle pill
        let path = NSBezierPath(roundedRect: cellFrame, xRadius: 3, yRadius: 3)

        // Fill with light purple background
        NSColor.systemPurple.withAlphaComponent(0.2).setFill()
        path.fill()

        // Draw purple border
        NSColor.systemPurple.withAlphaComponent(0.3).setStroke()
        path.lineWidth = 1.0
        path.stroke()

        // Draw label text
        let text = "select fill"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.systemPurple
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

    // Create a fill-in pill with label and default value
    static func createFillInDisplayString(label: String, defaultValue: String) -> NSAttributedString {
        let attachment = NSTextAttachment()

        // Use custom cell for rendering
        attachment.attachmentCell = FillInPillAttachmentCell(label: label, defaultValue: defaultValue)

        // Store the fill-in data as JSON in the attachment
        let fillInData: [String: String] = [
            "type": "fillin_single",
            "label": label,
            "default": defaultValue
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: fillInData, options: []) {
            let wrapper = FileWrapper(regularFileWithContents: jsonData)
            wrapper.preferredFilename = "fillin_single.json"
            attachment.fileWrapper = wrapper
        }

        return NSAttributedString(attachment: attachment)
    }

    static func createMultiLineFillInDisplayString(label: String, defaultValue: String) -> NSAttributedString {
        let attachment = NSTextAttachment()

        // Use custom cell for rendering
        attachment.attachmentCell = MultiLineFillInPillAttachmentCell(label: label, defaultValue: defaultValue)

        // Store the fill-in data as JSON in the attachment
        let fillInData: [String: String] = [
            "type": "fillin_multi",
            "label": label,
            "default": defaultValue
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: fillInData, options: []) {
            let wrapper = FileWrapper(regularFileWithContents: jsonData)
            wrapper.preferredFilename = "fillin_multi.json"
            attachment.fileWrapper = wrapper
        }

        return NSAttributedString(attachment: attachment)
    }

    static func createSelectFillInDisplayString(label: String, options: [String], defaultIndex: Int) -> NSAttributedString {
        let attachment = NSTextAttachment()

        // Use custom cell for rendering
        attachment.attachmentCell = SelectFillInPillAttachmentCell(label: label, options: options, defaultIndex: defaultIndex)

        // Store the fill-in data as JSON in the attachment
        let fillInData: [String: Any] = [
            "type": "fillin_select",
            "label": label,
            "options": options,
            "defaultIndex": defaultIndex
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: fillInData, options: []) {
            let wrapper = FileWrapper(regularFileWithContents: jsonData)
            wrapper.preferredFilename = "fillin_select.json"
            attachment.fileWrapper = wrapper
        }

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

        // Find and replace single-line fill-in tokens
        let nsText = mutableString.string as NSString
        var fillInReplacements: [(range: NSRange, label: String, defaultValue: String, isMulti: Bool)] = []

        // Pattern: {{fillin_single|label|defaultValue}}
        let singlePattern = "\\{\\{fillin_single\\|([^|]*)\\|([^}]*)\\}\\}"
        if let regex = try? NSRegularExpression(pattern: singlePattern, options: []) {
            let matches = regex.matches(in: mutableString.string, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches.reversed() {
                let labelRange = match.range(at: 1)
                let defaultRange = match.range(at: 2)
                let label = nsText.substring(with: labelRange)
                let defaultValue = nsText.substring(with: defaultRange)
                fillInReplacements.append((range: match.range, label: label, defaultValue: defaultValue, isMulti: false))
            }
        }

        // Pattern: {{fillin_multi|label|defaultValue}}
        let multiPattern = "\\{\\{fillin_multi\\|([^|]*)\\|([^}]*)\\}\\}"
        if let regex = try? NSRegularExpression(pattern: multiPattern, options: []) {
            let matches = regex.matches(in: mutableString.string, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches.reversed() {
                let labelRange = match.range(at: 1)
                let defaultRange = match.range(at: 2)
                let label = nsText.substring(with: labelRange)
                let defaultValue = nsText.substring(with: defaultRange)
                fillInReplacements.append((range: match.range, label: label, defaultValue: defaultValue, isMulti: true))
            }
        }

        // Replace fill-in tokens with pills (sorted in reverse by location to maintain indices)
        for replacement in fillInReplacements.sorted(by: { $0.range.location > $1.range.location }) {
            let pillString = replacement.isMulti
                ? PlaceholderPillRenderer.createMultiLineFillInDisplayString(
                    label: replacement.label,
                    defaultValue: replacement.defaultValue
                  )
                : PlaceholderPillRenderer.createFillInDisplayString(
                    label: replacement.label,
                    defaultValue: replacement.defaultValue
                  )
            mutableString.replaceCharacters(in: replacement.range, with: pillString)
        }

        // Pattern: {{fillin_select|label|option1,option2,option3|defaultIndex}}
        let selectPattern = "\\{\\{fillin_select\\|([^|]*)\\|([^|]*)\\|([^}]*)\\}\\}"
        if let regex = try? NSRegularExpression(pattern: selectPattern, options: []) {
            let nsText2 = mutableString.string as NSString
            let matches = regex.matches(in: mutableString.string, options: [], range: NSRange(location: 0, length: nsText2.length))
            for match in matches.reversed() {
                let labelRange = match.range(at: 1)
                let optionsRange = match.range(at: 2)
                let defaultIndexRange = match.range(at: 3)
                let label = nsText2.substring(with: labelRange)
                let optionsString = nsText2.substring(with: optionsRange)
                let defaultIndexString = nsText2.substring(with: defaultIndexRange)

                let options = optionsString.components(separatedBy: ",")
                let defaultIndex = Int(defaultIndexString) ?? 0

                let pillString = PlaceholderPillRenderer.createSelectFillInDisplayString(
                    label: label,
                    options: options,
                    defaultIndex: defaultIndex
                )
                mutableString.replaceCharacters(in: match.range, with: pillString)
            }
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
               let data = fileWrapper.regularFileContents {

                // Check if it's a fill-in attachment (JSON)
                if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let type = json["type"] as? String,
                   let label = json["label"] as? String {

                    let storageText: String
                    if type == "fillin_select" {
                        // Convert select fill-in: {{fillin_select|label|option1,option2|defaultIndex}}
                        let options = json["options"] as? [String] ?? []
                        let defaultIndex = json["defaultIndex"] as? Int ?? 0
                        let optionsString = options.joined(separator: ",")
                        storageText = "{{\(type)|\(label)|\(optionsString)|\(defaultIndex)}}"
                    } else if let defaultValue = json["default"] as? String {
                        // Convert single/multi fill-in: {{fillin_single|label|defaultValue}} or {{fillin_multi|label|defaultValue}}
                        storageText = "{{\(type)|\(label)|\(defaultValue)}}"
                    } else {
                        return
                    }
                    replacements.append((range: range, text: storageText))
                }
                // Check if it's a placeholder token (plain text)
                else if let storageText = String(data: data, encoding: .utf8),
                        storageText.hasPrefix("{{") && storageText.hasSuffix("}}") {
                    // This is one of our placeholder tokens
                    replacements.append((range: range, text: storageText))
                }
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

    // Helper to get plain text preview with placeholders (for sidebar display)
    var previewText: String {
        if isRichText, let data = richTextData {
            do {
                let loadedString = try NSAttributedString(
                    data: data,
                    options: [NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                )

                return loadedString.string
            } catch {
                return expansion
            }
        }
        return expansion
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
