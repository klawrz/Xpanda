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
        // TODO: Implement clipboard insertion
        print("Insert Clipboard clicked")
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
