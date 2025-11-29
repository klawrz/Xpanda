import Foundation
import AppKit

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
        case .fillin: return "fill-in"
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
