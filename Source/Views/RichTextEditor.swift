import SwiftUI
import AppKit

// Wrapper that includes both the toolbar and editor
struct RichTextEditorWithToolbar: View {
    @Binding var attributedString: NSAttributedString
    @StateObject private var textViewHolder = RichTextViewHolder()
    @State private var linkClickedAt: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            RichTextToolbar(textViewHolder: textViewHolder, linkClickedAt: $linkClickedAt)
            RichTextEditor(
                attributedString: $attributedString,
                textViewHolder: textViewHolder,
                linkClickedAt: $linkClickedAt
            )
                .border(Color.secondary.opacity(0.2))
        }
    }
}

// Custom NSTextView subclass to override paste behavior and link clicking
class XpandaTextView: NSTextView {
    override func paste(_ sender: Any?) {
        // Get plain text from pasteboard
        let pasteboard = NSPasteboard.general
        guard let plainText = pasteboard.string(forType: .string), !plainText.isEmpty else {
            super.paste(sender)
            return
        }

        // Create attributed string with Xpanda's default attributes
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ]
        let attributedString = NSAttributedString(string: plainText, attributes: attributes)

        // Insert at current location
        let range = self.selectedRange()
        if self.shouldChangeText(in: range, replacementString: plainText) {
            self.textStorage?.replaceCharacters(in: range, with: attributedString)
            self.didChangeText()

            // Move cursor to end of pasted text
            let newLocation = range.location + plainText.count
            self.setSelectedRange(NSRange(location: newLocation, length: 0))
        }
    }

    // Override to disable link clicking at the mouse event level
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let charIndex = characterIndexForInsertion(at: point)

        // Check if clicking on a link
        if charIndex < textStorage?.length ?? 0,
           let storage = textStorage,
           storage.attribute(.link, at: charIndex, effectiveRange: nil) != nil {
            // Handle link click via delegate
            if let link = storage.attribute(.link, at: charIndex, effectiveRange: nil),
               let textDelegate = delegate {
                _ = textDelegate.textView?(self, clickedOnLink: link, at: charIndex)
            }
            // Don't call super - this prevents the default link opening
            return
        }

        // Normal click, not on a link
        super.mouseDown(with: event)
    }
}

struct RichTextEditor: NSViewRepresentable {
    @Binding var attributedString: NSAttributedString
    @ObservedObject var textViewHolder: RichTextViewHolder
    @Binding var linkClickedAt: Int?
    var isEditable: Bool = true

    func makeNSView(context: Context) -> NSScrollView {
        // Create scroll view manually
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        // Create our custom text view
        let textView = XpandaTextView()

        // Set up text container
        let textContainer = NSTextContainer()
        textContainer.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textContainer.widthTracksTextView = true

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        textView.replaceTextContainer(textContainer)

        scrollView.documentView = textView

        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.usesFontPanel = true
        textView.usesRuler = false
        textView.importsGraphics = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        // Disable automatic link detection
        textView.isAutomaticLinkDetectionEnabled = false

        // Set initial content
        textView.textStorage?.setAttributedString(attributedString)

        // Set typing attributes to match text view defaults
        // This ensures pasted text and typed text use the same style
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor
        ]

        // Store reference to textView
        DispatchQueue.main.async {
            textViewHolder.textView = textView
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only update if content is different to avoid cursor jumping
        // Compare by string content rather than the entire attributed string
        if textView.string != attributedString.string {
            let selectedRange = textView.selectedRange()
            textView.textStorage?.setAttributedString(attributedString)
            // Restore selection if still valid
            if selectedRange.location <= textView.string.count {
                textView.setSelectedRange(selectedRange)
            }
        }

        textView.isEditable = isEditable
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: RichTextEditor

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.attributedString = textView.attributedString()
        }

        // This gets called when attributes change (bold, italic, underline)
        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
            if editedMask.contains(.editedAttributes) || editedMask.contains(.editedCharacters) {
                // Attributes or text changed, update the binding
                DispatchQueue.main.async {
                    self.parent.attributedString = textStorage.copy() as! NSAttributedString
                }
            }
        }

        // Intercept link clicks - open edit dialog instead of browser
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            // Trigger the link editing dialog by setting the clicked position
            parent.linkClickedAt = charIndex
            return false  // Don't open in browser
        }

        // Fix typing attributes when selection changes (e.g., after moving cursor past an attachment)
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }

            let range = textView.selectedRange()
            guard let storage = textView.textStorage else { return }

            // If cursor is at a position (not selecting text)
            if range.length == 0 {
                var shouldResetAttributes = false

                // Check if we're right after an attachment
                if range.location > 0 {
                    let charIndex = range.location - 1
                    if charIndex >= 0 && charIndex < storage.length {
                        if storage.attribute(.attachment, at: charIndex, effectiveRange: nil) != nil {
                            shouldResetAttributes = true
                        }
                    }
                }

                // Check if we're right before an attachment
                if range.location < storage.length {
                    if storage.attribute(.attachment, at: range.location, effectiveRange: nil) != nil {
                        shouldResetAttributes = true
                    }
                }

                // Reset typing attributes if we're adjacent to an attachment
                if shouldResetAttributes {
                    textView.typingAttributes = [
                        .font: NSFont.systemFont(ofSize: 13),
                        .foregroundColor: NSColor.labelColor
                    ]
                }
            }
        }
    }
}

// Formatting toolbar for rich text
struct RichTextToolbar: View {
    @ObservedObject var textViewHolder: RichTextViewHolder
    @Binding var linkClickedAt: Int?
    @State private var isBoldActive = false
    @State private var isItalicActive = false
    @State private var isUnderlineActive = false
    @State private var updateTimer: Timer?
    @State private var showingLinkDialog = false
    @State private var linkURL = ""
    @State private var linkText = ""
    @State private var editingLinkRange: NSRange? = nil

    var body: some View {
        HStack(spacing: 4) {
            // Bold
            Button(action: { toggleBold() }) {
                Image(systemName: "bold")
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(isBoldActive ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
            .cornerRadius(6)
            .help("Bold (⌘B)")

            // Italic
            Button(action: { toggleItalic() }) {
                Image(systemName: "italic")
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(isItalicActive ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
            .cornerRadius(6)
            .help("Italic (⌘I)")

            // Underline
            Button(action: { toggleUnderline() }) {
                Image(systemName: "underline")
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(isUnderlineActive ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
            .cornerRadius(6)
            .help("Underline (⌘U)")

            Divider()
                .frame(height: 16)

            // Insert Date
            Button(action: { insertDate() }) {
                Image(systemName: "calendar")
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
            .help("Insert Date")

            // Insert Time
            Button(action: { insertTime() }) {
                Image(systemName: "clock")
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
            .help("Insert Time")

            // Insert Clipboard
            Button(action: { insertClipboard() }) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
            .help("Insert Clipboard")

            Divider()
                .frame(height: 16)

            // Position Cursor
            Button(action: { positionCursor() }) {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
            .help("Position Cursor Here")

            // Insert Fill-In
            Button(action: { insertFillIn() }) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
            .help("Insert Fill-In")

            // Insert Link
            Button(action: { insertLink() }) {
                Image(systemName: "link")
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
            .help("Insert Link")

            // Insert Image
            Button(action: { insertImage() }) {
                Image(systemName: "photo")
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
            .help("Insert Image")

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            startUpdatingFormattingState()
        }
        .onDisappear {
            updateTimer?.invalidate()
        }
        .onChange(of: linkClickedAt) { clickedIndex in
            guard let index = clickedIndex,
                  let textView = textViewHolder.textView,
                  let storage = textView.textStorage else { return }

            // Find the full range of the link at this position
            var effectiveRange = NSRange()
            if let url = storage.attribute(.link, at: index, effectiveRange: &effectiveRange) as? URL {
                // Get the link text
                if let text = textView.string.substring(with: effectiveRange) {
                    linkText = text
                    linkURL = url.absoluteString
                    editingLinkRange = effectiveRange
                    showingLinkDialog = true
                }
            }

            // Reset the trigger
            linkClickedAt = nil
        }
        .sheet(isPresented: $showingLinkDialog) {
            LinkInputDialog(
                linkURL: $linkURL,
                linkText: $linkText,
                onInsert: {
                    insertLinkWithDetails()
                    showingLinkDialog = false
                },
                onCancel: {
                    showingLinkDialog = false
                }
            )
        }
    }

    private func startUpdatingFormattingState() {
        // Update immediately
        updateFormattingState()

        // Update periodically to catch cursor movements
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            updateFormattingState()
        }
    }

    private func updateFormattingState() {
        guard let textView = textViewHolder.textView else { return }

        let range = textView.selectedRange()
        let location = range.location

        // Check for zero-length selection (cursor position)
        if range.length == 0 && location > 0 {
            // Use typing attributes for cursor position
            if let font = textView.typingAttributes[.font] as? NSFont {
                isBoldActive = font.fontDescriptor.symbolicTraits.contains(.bold)
                isItalicActive = font.fontDescriptor.symbolicTraits.contains(.italic)
            } else {
                isBoldActive = false
                isItalicActive = false
            }

            let underlineStyle = (textView.typingAttributes[.underlineStyle] as? Int) ?? 0
            isUnderlineActive = underlineStyle > 0
        } else if range.length > 0 {
            // Check attributes of selected text
            guard let storage = textView.textStorage else { return }

            var hasBold = false
            var hasItalic = false
            var hasUnderline = false

            storage.enumerateAttribute(.font, in: range, options: []) { value, _, _ in
                if let font = value as? NSFont {
                    if font.fontDescriptor.symbolicTraits.contains(.bold) {
                        hasBold = true
                    }
                    if font.fontDescriptor.symbolicTraits.contains(.italic) {
                        hasItalic = true
                    }
                }
            }

            storage.enumerateAttribute(.underlineStyle, in: range, options: []) { value, _, _ in
                if let style = value as? Int, style > 0 {
                    hasUnderline = true
                }
            }

            isBoldActive = hasBold
            isItalicActive = hasItalic
            isUnderlineActive = hasUnderline
        }
    }

    private func toggleBold() {
        guard let textView = textViewHolder.textView else { return }

        // Get current font and selection
        let range = textView.selectedRange()

        if range.length > 0 {
            // Has selection - toggle bold for selected text
            guard let storage = textView.textStorage else { return }

            storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
                if let font = value as? NSFont {
                    let newFont: NSFont
                    if font.fontDescriptor.symbolicTraits.contains(.bold) {
                        // Remove bold
                        newFont = NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
                    } else {
                        // Add bold
                        newFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                    }
                    storage.addAttribute(.font, value: newFont, range: subrange)
                }
            }
        } else {
            // No selection - toggle bold for future typing
            if let font = textView.typingAttributes[.font] as? NSFont {
                let newFont: NSFont
                if font.fontDescriptor.symbolicTraits.contains(.bold) {
                    newFont = NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
                } else {
                    newFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                }
                textView.typingAttributes[.font] = newFont
            }
        }

        textView.window?.makeFirstResponder(textView)
        updateFormattingState()
    }

    private func toggleItalic() {
        guard let textView = textViewHolder.textView else { return }

        let range = textView.selectedRange()

        if range.length > 0 {
            // Has selection - toggle italic for selected text
            guard let storage = textView.textStorage else { return }

            storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
                if let font = value as? NSFont {
                    let newFont: NSFont
                    if font.fontDescriptor.symbolicTraits.contains(.italic) {
                        newFont = NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask)
                    } else {
                        newFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                    }
                    storage.addAttribute(.font, value: newFont, range: subrange)
                }
            }
        } else {
            // No selection - toggle italic for future typing
            if let font = textView.typingAttributes[.font] as? NSFont {
                let newFont: NSFont
                if font.fontDescriptor.symbolicTraits.contains(.italic) {
                    newFont = NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask)
                } else {
                    newFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                }
                textView.typingAttributes[.font] = newFont
            }
        }

        textView.window?.makeFirstResponder(textView)
        updateFormattingState()
    }

    private func toggleUnderline() {
        guard let textView = textViewHolder.textView else { return }

        let range = textView.selectedRange()

        if range.length > 0 {
            // Has selection - toggle underline for selected text
            guard let storage = textView.textStorage else { return }

            storage.enumerateAttribute(.underlineStyle, in: range, options: []) { value, subrange, _ in
                let currentStyle = (value as? Int) ?? 0
                let newStyle = currentStyle > 0 ? 0 : NSUnderlineStyle.single.rawValue
                storage.addAttribute(.underlineStyle, value: newStyle, range: subrange)
            }
        } else {
            // No selection - toggle underline for future typing
            let currentStyle = (textView.typingAttributes[.underlineStyle] as? Int) ?? 0
            let newStyle = currentStyle > 0 ? 0 : NSUnderlineStyle.single.rawValue
            textView.typingAttributes[.underlineStyle] = newStyle
        }

        textView.window?.makeFirstResponder(textView)
        updateFormattingState()
    }

    // Advanced feature placeholder functions
    private func insertDate() {
        // TODO: Implement date insertion
        print("Insert Date clicked")
    }

    private func insertTime() {
        // TODO: Implement time insertion
        print("Insert Time clicked")
    }

    private func insertClipboard() {
        guard let textView = textViewHolder.textView else { return }

        let range = textView.selectedRange()
        let token = PlaceholderToken.clipboard

        // Create pill attachment
        let pillString = PlaceholderPillRenderer.createDisplayString(for: token)

        // Insert the pill
        if textView.shouldChangeText(in: range, replacementString: pillString.string) {
            textView.textStorage?.replaceCharacters(in: range, with: pillString)
            textView.didChangeText()

            // Move cursor after the pill
            let newLocation = range.location + pillString.length
            textView.setSelectedRange(NSRange(location: newLocation, length: 0))

            // Ensure typing attributes are reset to default
            DispatchQueue.main.async {
                textView.typingAttributes = [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.labelColor
                ]
            }
        }

        textView.window?.makeFirstResponder(textView)
    }

    private func positionCursor() {
        // TODO: Implement cursor positioning
        print("Position Cursor clicked")
    }

    private func insertFillIn() {
        // TODO: Implement fill-in insertion
        print("Insert Fill-In clicked")
    }

    private func insertLink() {
        guard let textView = textViewHolder.textView else { return }

        let range = textView.selectedRange()

        // If there's selected text, check if it's already a link
        if range.length > 0 {
            linkText = textView.string.substring(with: range) ?? ""

            // Check if the selected text has a link attribute
            if let storage = textView.textStorage,
               let url = storage.attribute(.link, at: range.location, effectiveRange: nil) as? URL {
                // Pre-fill with existing link data
                linkURL = url.absoluteString
            } else {
                // New link
                linkURL = ""
            }
        } else {
            linkText = ""
            linkURL = ""
        }

        showingLinkDialog = true
    }

    private func insertLinkWithDetails() {
        guard let textView = textViewHolder.textView,
              let url = URL(string: linkURL),
              !linkText.isEmpty else { return }

        // Use the editing range if we're editing an existing link, otherwise use selection
        let range = editingLinkRange ?? textView.selectedRange()

        // Create attributed string with link
        let attributes: [NSAttributedString.Key: Any] = [
            .link: url,
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        let linkAttributedString = NSAttributedString(string: linkText, attributes: attributes)

        // Insert the link
        if textView.shouldChangeText(in: range, replacementString: linkText) {
            textView.textStorage?.replaceCharacters(in: range, with: linkAttributedString)
            textView.didChangeText()

            // Move cursor after the link
            let newLocation = range.location + linkText.count
            textView.setSelectedRange(NSRange(location: newLocation, length: 0))

            // Reset typing attributes to default (so next typed text is normal, not a link)
            textView.typingAttributes = [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor
            ]
        }

        // Clear editing range
        editingLinkRange = nil
        textView.window?.makeFirstResponder(textView)
    }

    private func insertImage() {
        // TODO: Implement image insertion
        print("Insert Image clicked")
    }

}

// Custom layout manager that draws pills over %clipboard% text
class ClipboardPillLayoutManager: NSLayoutManager {
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)

        guard let textStorage = self.textStorage else { return }

        // Find all %clipboard% occurrences in the visible range
        let charRange = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let text = textStorage.string as NSString

        var searchRange = charRange
        while searchRange.location < NSMaxRange(charRange) {
            let foundRange = text.range(of: "%clipboard%", options: [], range: searchRange)

            if foundRange.location == NSNotFound {
                break
            }

            // Draw pill over this text
            if let container = self.textContainer(forGlyphAt: self.glyphIndexForCharacter(at: foundRange.location), effectiveRange: nil) {
                let glyphRange = self.glyphRange(forCharacterRange: foundRange, actualCharacterRange: nil)
                let boundingRect = self.boundingRect(forGlyphRange: glyphRange, in: container)

                // Offset by origin
                var pillRect = boundingRect
                pillRect.origin.x += origin.x
                pillRect.origin.y += origin.y

                // Expand the rect to make a nice pill shape
                pillRect = pillRect.insetBy(dx: -6, dy: -2)
                pillRect.size.width = 80  // Fixed width for consistency
                pillRect.size.height = 18

                // Draw the pill
                let path = NSBezierPath(roundedRect: pillRect, xRadius: 9, yRadius: 9)

                // Fill with light blue background
                NSColor.systemBlue.withAlphaComponent(0.15).setFill()
                path.fill()

                // Draw blue border
                NSColor.systemBlue.withAlphaComponent(0.5).setStroke()
                path.lineWidth = 1.0
                path.stroke()

                // Draw "clipboard" text (hide the %clipboard% underneath)
                let displayText = "clipboard"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: NSColor.systemBlue
                ]
                let textSize = displayText.size(withAttributes: attrs)
                let textRect = NSRect(
                    x: pillRect.origin.x + (pillRect.width - textSize.width) / 2,
                    y: pillRect.origin.y + (pillRect.height - textSize.height) / 2 + 1,
                    width: textSize.width,
                    height: textSize.height
                )

                // First, draw a white/background rectangle to hide the %clipboard% text
                NSColor.textBackgroundColor.setFill()
                pillRect.fill()

                // Redraw the pill
                path.fill()
                NSColor.systemBlue.withAlphaComponent(0.5).setStroke()
                path.stroke()

                // Draw the label
                displayText.draw(in: textRect, withAttributes: attrs)
            }

            // Move to next search position
            searchRange.location = foundRange.location + foundRange.length
            searchRange.length = NSMaxRange(charRange) - searchRange.location
        }
    }
}

// Helper to access NSTextView from SwiftUI
class RichTextViewHolder: ObservableObject {
    @Published var textView: NSTextView?
}

// Helper extension for String to work with NSRange
extension String {
    func substring(with nsrange: NSRange) -> String? {
        guard let range = Range(nsrange, in: self) else { return nil }
        return String(self[range])
    }
}

// Custom text attachment cell for rendering the clipboard pill
class ClipboardAttachmentCell: NSTextAttachmentCell {
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

        // Draw "clipboard" text
        let text = "clipboard"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
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

// Custom text attachment for clipboard placeholder
class ClipboardAttachment: NSTextAttachment {
    // Use a special file wrapper to identify this as a clipboard attachment
    static let clipboardMarker = "{{CLIPBOARD_PLACEHOLDER}}"

    init() {
        super.init(data: nil, ofType: nil)

        // Create a file wrapper with our marker text so it survives RTF save/load
        let markerData = ClipboardAttachment.clipboardMarker.data(using: .utf8)!
        let wrapper = FileWrapper(regularFileWithContents: markerData)
        wrapper.preferredFilename = "clipboard.txt"
        self.fileWrapper = wrapper

        // Set the custom cell for rendering
        self.attachmentCell = ClipboardAttachmentCell()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.attachmentCell = ClipboardAttachmentCell()
    }

    override func attachmentBounds(for textContainer: NSTextContainer?, proposedLineFragment lineFrag: NSRect, glyphPosition position: CGPoint, characterIndex charIndex: Int) -> CGRect {
        return CGRect(x: 0, y: -3, width: 80, height: 18)
    }
}

// Link input dialog
struct LinkInputDialog: View {
    @Binding var linkURL: String
    @Binding var linkText: String
    let onInsert: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Insert Link")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Link Text")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g., Click here", text: $linkText)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("URL")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g., https://example.com", text: $linkURL)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Insert") {
                    onInsert()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(linkURL.isEmpty || linkText.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
