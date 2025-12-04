import SwiftUI
import AppKit

// Wrapper that includes both the toolbar and editor
struct FillInClickData: Equatable {
    let index: Int
    let label: String
    let defaultValue: String
    let isMultiLine: Bool
    let isSelect: Bool
    let options: [String]?
    let defaultIndex: Int?
}

struct DateClickData: Equatable {
    let index: Int
    let format: String
}

struct TimeClickData: Equatable {
    let index: Int
    let format: String
}

struct RichTextEditorWithToolbar: View {
    @Binding var attributedString: NSAttributedString
    @StateObject private var textViewHolder = RichTextViewHolder()
    @State private var linkClickedAt: Int? = nil
    @State private var fillInClickedData: FillInClickData? = nil
    @State private var dateClickedData: DateClickData? = nil
    @State private var timeClickedData: TimeClickData? = nil

    var body: some View {
        VStack(spacing: 0) {
            RichTextToolbar(textViewHolder: textViewHolder, linkClickedAt: $linkClickedAt, fillInClickedData: $fillInClickedData, dateClickedData: $dateClickedData, timeClickedData: $timeClickedData)
            RichTextEditor(
                attributedString: $attributedString,
                textViewHolder: textViewHolder,
                linkClickedAt: $linkClickedAt,
                fillInClickedData: $fillInClickedData,
                dateClickedData: $dateClickedData,
                timeClickedData: $timeClickedData
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

    // Callback for fill-in attachment clicks
    var onFillInClicked: ((Int, String, String, Bool, Bool, [String]?, Int?) -> Void)?

    // Callback for date attachment clicks
    var onDateClicked: ((Int, String) -> Void)?

    // Callback for time attachment clicks
    var onTimeClicked: ((Int, String) -> Void)?

    // Override to handle keyboard shortcuts
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Check for Cmd key
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        // Get the key pressed
        guard let characters = event.charactersIgnoringModifiers else {
            return super.performKeyEquivalent(with: event)
        }

        switch characters.lowercased() {
        case "b":
            // Toggle bold
            toggleBold(nil)
            return true
        case "i":
            // Toggle italic
            toggleItalic(nil)
            return true
        case "u":
            // Toggle underline
            toggleUnderline(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    // Custom toggle methods that work on selection or typing attributes
    func toggleBold(_ sender: Any?) {
        let range = selectedRange()
        if range.length > 0 {
            // Has selection - toggle bold on selection
            toggleTraitForSelection(.boldFontMask)
        } else {
            // No selection - toggle bold for future typing
            toggleTypingAttribute(.boldFontMask)
        }
    }

    func toggleItalic(_ sender: Any?) {
        let range = selectedRange()
        if range.length > 0 {
            // Has selection - toggle italic on selection
            toggleTraitForSelection(.italicFontMask)
        } else {
            // No selection - toggle italic for future typing
            toggleTypingAttribute(.italicFontMask)
        }
    }

    func toggleUnderline(_ sender: Any?) {
        let range = selectedRange()
        if range.length > 0 {
            // Has selection - toggle underline on selection
            toggleUnderlineForSelection()
        } else {
            // No selection - toggle underline for future typing
            toggleTypingUnderline()
        }
    }

    // Helper to toggle a font trait for selected text
    private func toggleTraitForSelection(_ trait: NSFontTraitMask) {
        guard let textStorage = textStorage else { return }
        let range = selectedRange()
        guard range.length > 0 else { return }

        // Check if the first character has the trait
        var hasTrait = false
        if range.location < textStorage.length,
           let font = textStorage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont {
            let symbolicTrait: NSFontDescriptor.SymbolicTraits = trait == .boldFontMask ? .bold : .italic
            hasTrait = font.fontDescriptor.symbolicTraits.contains(symbolicTrait)
        }

        // Apply or remove the trait
        textStorage.beginEditing()
        textStorage.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
            if let currentFont = value as? NSFont {
                let newFont: NSFont
                if hasTrait {
                    // Remove trait
                    newFont = NSFontManager.shared.convert(currentFont, toNotHaveTrait: trait)
                } else {
                    // Add trait
                    newFont = NSFontManager.shared.convert(currentFont, toHaveTrait: trait)
                }
                textStorage.addAttribute(.font, value: newFont, range: subRange)
            }
        }
        textStorage.endEditing()

        // Notify of change
        didChangeText()
    }

    // Helper to toggle underline for selected text
    private func toggleUnderlineForSelection() {
        guard let textStorage = textStorage else { return }
        let range = selectedRange()
        guard range.length > 0 else { return }

        // Check if the first character is underlined
        var hasUnderline = false
        if range.location < textStorage.length {
            let underlineStyle = textStorage.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int
            hasUnderline = (underlineStyle ?? 0) != 0
        }

        // Apply or remove underline
        textStorage.beginEditing()
        if hasUnderline {
            textStorage.removeAttribute(.underlineStyle, range: range)
        } else {
            textStorage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        textStorage.endEditing()

        // Notify of change
        didChangeText()
    }

    // Helper to toggle a font trait for typing attributes
    private func toggleTypingAttribute(_ trait: NSFontTraitMask) {
        var attrs = typingAttributes

        // Get current font or use default
        let currentFont = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: 13)

        // Check if trait is currently active
        let symbolicTrait: NSFontDescriptor.SymbolicTraits = trait == .boldFontMask ? .bold : .italic
        let hasTrait = currentFont.fontDescriptor.symbolicTraits.contains(symbolicTrait)

        // Toggle the trait
        let newFont: NSFont
        if hasTrait {
            newFont = NSFontManager.shared.convert(currentFont, toNotHaveTrait: trait)
        } else {
            newFont = NSFontManager.shared.convert(currentFont, toHaveTrait: trait)
        }

        attrs[.font] = newFont
        typingAttributes = attrs

        // Notify change for toolbar update
        didChangeText()
    }

    // Helper to toggle underline for typing attributes
    private func toggleTypingUnderline() {
        var attrs = typingAttributes

        // Check current underline state
        let currentUnderline = attrs[.underlineStyle] as? Int ?? 0

        // Toggle underline
        if currentUnderline != 0 {
            attrs.removeValue(forKey: .underlineStyle)
        } else {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }

        typingAttributes = attrs

        // Notify change for toolbar update
        didChangeText()
    }

    // Override to disable link clicking at the mouse event level
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // Check if clicking on a date pill
        if let (charIndex, format) = getDatePillAtPoint(point) {
            onDateClicked?(charIndex, format)
            return
        }

        // Check if clicking on a time pill
        if let (charIndex, format) = getTimePillAtPoint(point) {
            onTimeClicked?(charIndex, format)
            return
        }

        // Check if clicking on a fill-in pill using the same logic as cursor detection
        if let (charIndex, label, defaultValue, isMultiLine, isSelect, options, defaultIndex) = getFillInPillAtPoint(point) {
            onFillInClicked?(charIndex, label, defaultValue, isMultiLine, isSelect, options, defaultIndex)
            return
        }

        // Check if clicking on a link
        let charIndex = characterIndexForInsertion(at: point)
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

    // Helper to get fill-in pill data at a point
    private func getFillInPillAtPoint(_ point: NSPoint) -> (charIndex: Int, label: String, defaultValue: String, isMultiLine: Bool, isSelect: Bool, options: [String]?, defaultIndex: Int?)? {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer,
              let storage = textStorage else {
            return nil
        }

        // Convert point to text container coordinates
        let containerPoint = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )

        // Get the glyph index at this point
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer, fractionOfDistanceThroughGlyph: nil)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }

        // Get the character index for this glyph
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard charIndex < storage.length else { return nil }

        // Check if this character has a fill-in attachment
        if let attachment = storage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? NSTextAttachment,
           let fileWrapper = attachment.fileWrapper,
           let data = fileWrapper.regularFileContents,
           let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
           let type = json["type"] as? String,
           (type == "fillin_single" || type == "fillin_multi" || type == "fillin_select"),
           let label = json["label"] as? String {

            // Get the bounding rect for this glyph
            let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)

            // Adjust for text container insets
            let adjustedRect = NSRect(
                x: glyphRect.origin.x + textContainerInset.width,
                y: glyphRect.origin.y + textContainerInset.height,
                width: glyphRect.width,
                height: glyphRect.height
            )

            // Check if point is within the glyph bounds
            if adjustedRect.contains(point) {
                if type == "fillin_select" {
                    let options = json["options"] as? [String] ?? []
                    let defaultIndex = json["defaultIndex"] as? Int ?? 0
                    return (charIndex, label, "", false, true, options, defaultIndex)
                } else {
                    let defaultValue = json["default"] as? String ?? ""
                    let isMultiLine = (type == "fillin_multi")
                    return (charIndex, label, defaultValue, isMultiLine, false, nil, nil)
                }
            }
        }

        return nil
    }

    // Helper to get date pill data at a point
    private func getDatePillAtPoint(_ point: NSPoint) -> (charIndex: Int, format: String)? {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer,
              let storage = textStorage else {
            return nil
        }

        // Convert point to text container coordinates
        let containerPoint = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )

        // Get the glyph index at this point
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer, fractionOfDistanceThroughGlyph: nil)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }

        // Get the character index for this glyph
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard charIndex < storage.length else { return nil }

        // Check if this character has a date attachment
        if let attachment = storage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? NSTextAttachment,
           let fileWrapper = attachment.fileWrapper,
           let data = fileWrapper.regularFileContents,
           let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
           let type = json["type"] as? String,
           type == "date",
           let format = json["format"] as? String {

            // Get the bounding rect for this glyph
            let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)

            // Adjust for text container insets
            let adjustedRect = NSRect(
                x: glyphRect.origin.x + textContainerInset.width,
                y: glyphRect.origin.y + textContainerInset.height,
                width: glyphRect.width,
                height: glyphRect.height
            )

            // Check if point is within the glyph bounds
            if adjustedRect.contains(point) {
                return (charIndex, format)
            }
        }

        return nil
    }

    // Helper to get time pill data at a point
    private func getTimePillAtPoint(_ point: NSPoint) -> (charIndex: Int, format: String)? {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer,
              let storage = textStorage else {
            return nil
        }

        // Convert point to text container coordinates
        let containerPoint = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )

        // Get the glyph index at this point
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer, fractionOfDistanceThroughGlyph: nil)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }

        // Get the character index for this glyph
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard charIndex < storage.length else { return nil }

        // Check if this character has a time attachment
        if let attachment = storage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? NSTextAttachment,
           let fileWrapper = attachment.fileWrapper,
           let data = fileWrapper.regularFileContents,
           let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
           let type = json["type"] as? String,
           type == "time",
           let format = json["format"] as? String {

            // Get the bounding rect for this glyph
            let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)

            // Adjust for text container insets
            let adjustedRect = NSRect(
                x: glyphRect.origin.x + textContainerInset.width,
                y: glyphRect.origin.y + textContainerInset.height,
                width: glyphRect.width,
                height: glyphRect.height
            )

            // Check if point is within the glyph bounds
            if adjustedRect.contains(point) {
                return (charIndex, format)
            }
        }

        return nil
    }
}

struct RichTextEditor: NSViewRepresentable {
    @Binding var attributedString: NSAttributedString
    @ObservedObject var textViewHolder: RichTextViewHolder
    @Binding var linkClickedAt: Int?
    @Binding var fillInClickedData: FillInClickData?
    @Binding var dateClickedData: DateClickData?
    @Binding var timeClickedData: TimeClickData?
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

        // Set up fill-in click handler
        let coordinator = context.coordinator
        textView.onFillInClicked = { charIndex, label, defaultValue, isMultiLine, isSelect, options, defaultIndex in
            coordinator.handleFillInClick(at: charIndex, label: label, defaultValue: defaultValue, isMultiLine: isMultiLine, isSelect: isSelect, options: options, defaultIndex: defaultIndex)
        }

        // Set up date click handler
        textView.onDateClicked = { charIndex, format in
            coordinator.handleDateClick(at: charIndex, format: format)
        }

        // Set up time click handler
        textView.onTimeClicked = { charIndex, format in
            coordinator.handleTimeClick(at: charIndex, format: format)
        }

        // Store reference to textView
        DispatchQueue.main.async {
            textViewHolder.textView = textView
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? XpandaTextView else { return }

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

        // Handle fill-in pill clicks
        func handleFillInClick(at index: Int, label: String, defaultValue: String, isMultiLine: Bool, isSelect: Bool, options: [String]?, defaultIndex: Int?) {
            parent.fillInClickedData = FillInClickData(index: index, label: label, defaultValue: defaultValue, isMultiLine: isMultiLine, isSelect: isSelect, options: options, defaultIndex: defaultIndex)
        }

        func handleDateClick(at index: Int, format: String) {
            parent.dateClickedData = DateClickData(index: index, format: format)
        }

        func handleTimeClick(at index: Int, format: String) {
            parent.timeClickedData = TimeClickData(index: index, format: format)
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
    @Binding var fillInClickedData: FillInClickData?
    @Binding var dateClickedData: DateClickData?
    @Binding var timeClickedData: TimeClickData?
    @State private var isBoldActive = false
    @State private var isItalicActive = false
    @State private var isUnderlineActive = false
    @State private var updateTimer: Timer?
    @State private var showingLinkDialog = false
    @State private var linkURL = ""
    @State private var linkText = ""
    @State private var editingLinkRange: NSRange? = nil
    @State private var showingFillInDialog = false
    @State private var fillInLabel = ""
    @State private var fillInDefault = ""
    @State private var editingFillInRange: NSRange? = nil
    @State private var showingMultiLineFillInDialog = false
    @State private var multiLineFillInLabel = ""
    @State private var multiLineFillInDefault = ""
    @State private var editingMultiLineFillInRange: NSRange? = nil
    @State private var showingSelectFillInDialog = false
    @State private var selectFillInLabel = ""
    @State private var selectFillInOptions: [String] = []
    @State private var selectFillInDefaultIndex = 0
    @State private var editingSelectFillInRange: NSRange? = nil
    @State private var showingDateConfigDialog = false
    @State private var dateYearFormat = ""
    @State private var dateMonthFormat = ""
    @State private var dateDayFormat = ""
    @State private var dateWeekdayFormat = ""
    @State private var dateSeparator = " "
    @State private var editingDateRange: NSRange? = nil
    @State private var showingTimeConfigDialog = false
    @State private var timeHourFormat = ""
    @State private var timeMinuteFormat = ""
    @State private var timeSecondFormat = ""
    @State private var timeAMPMFormat = ""
    @State private var timeSeparator = ""
    @State private var editingTimeRange: NSRange? = nil

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
            Button(action: {
                // Clear form and show dialog
                dateYearFormat = ""
                dateMonthFormat = ""
                dateDayFormat = ""
                dateWeekdayFormat = ""
                dateSeparator = ""  // Will be set from parsed preview
                editingDateRange = nil
                showingDateConfigDialog = true
            }) {
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
            Button(action: {
                // Clear form and show dialog
                timeHourFormat = ""
                timeMinuteFormat = ""
                timeSecondFormat = ""
                timeAMPMFormat = ""
                timeSeparator = ""  // Will be set from parsed preview
                editingTimeRange = nil
                showingTimeConfigDialog = true
            }) {
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
                CursorIconView()
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(6)
            .help("Position Cursor Here")

            // Insert Fill-In Menu
            Menu {
                Button("Single") {
                    insertFillIn(type: .single)
                }
                Button("Multi") {
                    insertFillIn(type: .multi)
                }
                Button("Select") {
                    insertFillIn(type: .select)
                }
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
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
        .onChange(of: fillInClickedData) { clickedData in
            guard let data = clickedData,
                  let textView = textViewHolder.textView,
                  let storage = textView.textStorage else { return }

            // Find the fill-in attachment at this position
            let charIndex = data.index
            if charIndex < storage.length {
                if data.isSelect {
                    // Select fill-in
                    editingSelectFillInRange = NSRange(location: charIndex, length: 1)
                    selectFillInLabel = data.label
                    selectFillInOptions = data.options ?? [""]
                    selectFillInDefaultIndex = data.defaultIndex ?? 0
                    showingSelectFillInDialog = true
                } else if data.isMultiLine {
                    // Multi-line fill-in
                    editingMultiLineFillInRange = NSRange(location: charIndex, length: 1)
                    multiLineFillInLabel = data.label
                    multiLineFillInDefault = data.defaultValue
                    showingMultiLineFillInDialog = true
                } else {
                    // Single-line fill-in
                    editingFillInRange = NSRange(location: charIndex, length: 1)
                    fillInLabel = data.label
                    fillInDefault = data.defaultValue
                    showingFillInDialog = true
                }
            }

            // Reset the trigger
            fillInClickedData = nil
        }
        .onChange(of: dateClickedData) { clickedData in
            guard let data = clickedData,
                  let textView = textViewHolder.textView,
                  let storage = textView.textStorage else { return }

            // Find the date attachment at this position
            let charIndex = data.index
            if charIndex < storage.length {
                // Parse the format and populate the dialog
                parseFormatToComponents(data.format)
                editingDateRange = NSRange(location: charIndex, length: 1)
                showingDateConfigDialog = true
            }

            // Reset the trigger
            dateClickedData = nil
        }
        .onChange(of: timeClickedData) { clickedData in
            guard let data = clickedData,
                  let textView = textViewHolder.textView,
                  let storage = textView.textStorage else { return }

            // Find the time attachment at this position
            let charIndex = data.index
            if charIndex < storage.length {
                // Parse the format and populate the dialog
                parseTimeFormatToComponents(data.format)
                editingTimeRange = NSRange(location: charIndex, length: 1)
                showingTimeConfigDialog = true
            }

            // Reset the trigger
            timeClickedData = nil
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
        .sheet(isPresented: $showingFillInDialog) {
            FillInInputDialog(
                label: $fillInLabel,
                defaultValue: $fillInDefault,
                onInsert: {
                    insertFillInWithDetails()
                    showingFillInDialog = false
                },
                onCancel: {
                    showingFillInDialog = false
                }
            )
        }
        .sheet(isPresented: $showingMultiLineFillInDialog) {
            MultiLineFillInDialog(
                label: $multiLineFillInLabel,
                defaultValue: $multiLineFillInDefault,
                onInsert: {
                    insertMultiLineFillInWithDetails()
                    showingMultiLineFillInDialog = false
                },
                onCancel: {
                    showingMultiLineFillInDialog = false
                }
            )
        }
        .sheet(isPresented: $showingSelectFillInDialog) {
            SelectFillInDialog(
                label: $selectFillInLabel,
                options: $selectFillInOptions,
                defaultIndex: $selectFillInDefaultIndex,
                onInsert: {
                    insertSelectFillInWithDetails()
                    showingSelectFillInDialog = false
                },
                onCancel: {
                    showingSelectFillInDialog = false
                }
            )
        }
        .sheet(isPresented: $showingDateConfigDialog) {
            DateConfigDialog(
                yearFormat: $dateYearFormat,
                monthFormat: $dateMonthFormat,
                dayFormat: $dateDayFormat,
                weekdayFormat: $dateWeekdayFormat,
                separator: $dateSeparator,
                onInsert: {
                    insertDateWithConfig()
                    showingDateConfigDialog = false
                },
                onCancel: {
                    showingDateConfigDialog = false
                }
            )
        }
        .sheet(isPresented: $showingTimeConfigDialog) {
            TimeConfigDialog(
                hourFormat: $timeHourFormat,
                minuteFormat: $timeMinuteFormat,
                secondFormat: $timeSecondFormat,
                ampmFormat: $timeAMPMFormat,
                separator: $timeSeparator,
                onInsert: {
                    insertTimeWithConfig()
                    showingTimeConfigDialog = false
                },
                onCancel: {
                    showingTimeConfigDialog = false
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

        // Check for zero-length selection (cursor position or empty document)
        if range.length == 0 {
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
    private func insertDateWithConfig() {
        guard let textView = textViewHolder.textView else { return }

        // Use the editing range if we're editing an existing date, otherwise use selection
        let range = editingDateRange ?? textView.selectedRange()

        // The separator now contains the complete format string (parsed from preview)
        let format = dateSeparator

        // Create date pill
        let pillString = PlaceholderPillRenderer.createDateDisplayString(format: format)

        // Insert the pill
        if textView.shouldChangeText(in: range, replacementString: pillString.string) {
            textView.textStorage?.replaceCharacters(in: range, with: pillString)
            textView.didChangeText()

            // Move cursor after the pill
            let newLocation = range.location + pillString.length
            textView.setSelectedRange(NSRange(location: newLocation, length: 0))

            // Reset typing attributes to default
            DispatchQueue.main.async {
                textView.typingAttributes = [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.labelColor
                ]
            }
        }

        // Clear editing range
        editingDateRange = nil
        textView.window?.makeFirstResponder(textView)
    }

    private func parseFormatToComponents(_ format: String) {
        // Parse a date format string back into components
        // Look for common format codes and set the corresponding variables

        // Year
        if format.contains("yyyy") {
            dateYearFormat = "yyyy"
        } else if format.contains("yy") {
            dateYearFormat = "yy"
        } else {
            dateYearFormat = ""
        }

        // Month
        if format.contains("MMMM") {
            dateMonthFormat = "MMMM"
        } else if format.contains("MMM") {
            dateMonthFormat = "MMM"
        } else if format.contains("MM") {
            dateMonthFormat = "MM"
        } else if format.contains("M") {
            dateMonthFormat = "M"
        } else {
            dateMonthFormat = ""
        }

        // Day
        if format.contains("dd") {
            dateDayFormat = "dd"
        } else if format.contains("d") {
            dateDayFormat = "d"
        } else {
            dateDayFormat = ""
        }

        // Weekday
        if format.contains("EEEE") {
            dateWeekdayFormat = "EEEE"
        } else if format.contains("EEE") {
            dateWeekdayFormat = "EEE"
        } else {
            dateWeekdayFormat = ""
        }

        // Store the full format in separator (we'll use it to reconstruct the preview)
        dateSeparator = format
    }

    private func insertTimeWithConfig() {
        guard let textView = textViewHolder.textView else { return }

        // Use the editing range if we're editing an existing time, otherwise use selection
        let range = editingTimeRange ?? textView.selectedRange()

        // The separator now contains the complete format string (parsed from preview)
        let format = timeSeparator

        // Create time pill
        let pillString = PlaceholderPillRenderer.createTimeDisplayString(format: format)

        // Insert the pill
        if textView.shouldChangeText(in: range, replacementString: pillString.string) {
            textView.textStorage?.replaceCharacters(in: range, with: pillString)
            textView.didChangeText()

            // Move cursor after the pill
            let newLocation = range.location + pillString.length
            textView.setSelectedRange(NSRange(location: newLocation, length: 0))

            // Reset typing attributes to default
            DispatchQueue.main.async {
                textView.typingAttributes = [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.labelColor
                ]
            }
        }

        // Clear editing range
        editingTimeRange = nil
        textView.window?.makeFirstResponder(textView)
    }

    private func parseTimeFormatToComponents(_ format: String) {
        // Parse a time format string back into components
        // Look for common format codes and set the corresponding variables

        // Hour - check longer patterns first
        if format.contains("HH") {
            timeHourFormat = "HH"  // 24-hour, 2 digits
        } else if format.contains("H") {
            timeHourFormat = "H"   // 24-hour, 1-2 digits
        } else if format.contains("hh") {
            timeHourFormat = "hh"  // 12-hour, 2 digits
        } else if format.contains("h") {
            timeHourFormat = "h"   // 12-hour, 1-2 digits
        } else {
            timeHourFormat = ""
        }

        // Minute
        if format.contains("mm") {
            timeMinuteFormat = "mm"  // 2 digits
        } else if format.contains("m") {
            timeMinuteFormat = "m"   // 1-2 digits
        } else {
            timeMinuteFormat = ""
        }

        // Second
        if format.contains("ss") {
            timeSecondFormat = "ss"  // 2 digits
        } else if format.contains("s") {
            timeSecondFormat = "s"   // 1-2 digits
        } else {
            timeSecondFormat = ""
        }

        // AM/PM
        if format.contains("a") {
            timeAMPMFormat = "a"
        } else {
            timeAMPMFormat = ""
        }

        // Store the full format in separator (we'll use it to reconstruct the preview)
        timeSeparator = format
    }

    private func insertDate(format: String) {
        guard let textView = textViewHolder.textView else { return }

        let range = textView.selectedRange()

        // Create date pill
        let pillString = PlaceholderPillRenderer.createDateDisplayString(format: format)

        // Insert the pill
        if textView.shouldChangeText(in: range, replacementString: pillString.string) {
            textView.textStorage?.replaceCharacters(in: range, with: pillString)
            textView.didChangeText()

            // Move cursor after the pill
            let newLocation = range.location + pillString.length
            textView.setSelectedRange(NSRange(location: newLocation, length: 0))

            // Reset typing attributes to default
            DispatchQueue.main.async {
                textView.typingAttributes = [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.labelColor
                ]
            }
        }

        textView.window?.makeFirstResponder(textView)
    }

    private func insertTime(format: String) {
        guard let textView = textViewHolder.textView else { return }

        let range = textView.selectedRange()

        // Create time pill
        let pillString = PlaceholderPillRenderer.createTimeDisplayString(format: format)

        // Insert the pill
        if textView.shouldChangeText(in: range, replacementString: pillString.string) {
            textView.textStorage?.replaceCharacters(in: range, with: pillString)
            textView.didChangeText()

            // Move cursor after the pill
            let newLocation = range.location + pillString.length
            textView.setSelectedRange(NSRange(location: newLocation, length: 0))

            // Reset typing attributes to default
            DispatchQueue.main.async {
                textView.typingAttributes = [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.labelColor
                ]
            }
        }

        textView.window?.makeFirstResponder(textView)
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
        guard let textView = textViewHolder.textView else { return }

        let range = textView.selectedRange()
        let token = PlaceholderToken.cursor

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

    enum FillInType {
        case single
        case multi
        case select
    }

    private func insertFillIn(type: FillInType) {
        switch type {
        case .single:
            // Clear form and show dialog
            fillInLabel = ""
            fillInDefault = ""
            editingFillInRange = nil
            showingFillInDialog = true
        case .multi:
            // Clear form and show dialog
            multiLineFillInLabel = ""
            multiLineFillInDefault = ""
            editingMultiLineFillInRange = nil
            showingMultiLineFillInDialog = true
        case .select:
            // Clear form and show dialog
            selectFillInLabel = ""
            selectFillInOptions = [""]
            selectFillInDefaultIndex = 0
            editingSelectFillInRange = nil
            showingSelectFillInDialog = true
        }
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

    private func insertFillInWithDetails() {
        guard let textView = textViewHolder.textView,
              !fillInLabel.isEmpty else { return }

        // Use the editing range if we're editing an existing fill-in, otherwise use selection
        let range = editingFillInRange ?? textView.selectedRange()

        // Create fill-in pill
        let pillString = PlaceholderPillRenderer.createFillInDisplayString(
            label: fillInLabel,
            defaultValue: fillInDefault
        )

        // Insert the pill
        if textView.shouldChangeText(in: range, replacementString: pillString.string) {
            textView.textStorage?.replaceCharacters(in: range, with: pillString)
            textView.didChangeText()

            // Move cursor after the pill
            let newLocation = range.location + pillString.length
            textView.setSelectedRange(NSRange(location: newLocation, length: 0))

            // Reset typing attributes to default
            DispatchQueue.main.async {
                textView.typingAttributes = [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.labelColor
                ]
            }
        }

        // Clear editing range
        editingFillInRange = nil
        textView.window?.makeFirstResponder(textView)
    }

    private func insertMultiLineFillInWithDetails() {
        guard let textView = textViewHolder.textView,
              !multiLineFillInLabel.isEmpty else { return }

        // Use the editing range if we're editing an existing fill-in, otherwise use selection
        let range = editingMultiLineFillInRange ?? textView.selectedRange()

        // Create multi-line fill-in pill
        let pillString = PlaceholderPillRenderer.createMultiLineFillInDisplayString(
            label: multiLineFillInLabel,
            defaultValue: multiLineFillInDefault
        )

        // Insert the pill
        if textView.shouldChangeText(in: range, replacementString: pillString.string) {
            textView.textStorage?.replaceCharacters(in: range, with: pillString)
            textView.didChangeText()

            // Move cursor after the pill
            let newLocation = range.location + pillString.length
            textView.setSelectedRange(NSRange(location: newLocation, length: 0))

            // Reset typing attributes to default
            DispatchQueue.main.async {
                textView.typingAttributes = [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.labelColor
                ]
            }
        }

        // Clear editing range
        editingMultiLineFillInRange = nil
        textView.window?.makeFirstResponder(textView)
    }

    private func insertSelectFillInWithDetails() {
        guard let textView = textViewHolder.textView,
              !selectFillInLabel.isEmpty,
              !selectFillInOptions.allSatisfy({ $0.isEmpty }) else { return }

        // Filter out empty options
        let validOptions = selectFillInOptions.filter { !$0.isEmpty }
        guard !validOptions.isEmpty else { return }

        // Adjust default index if needed
        let safeDefaultIndex = min(selectFillInDefaultIndex, validOptions.count - 1)

        // Use the editing range if we're editing an existing fill-in, otherwise use selection
        let range = editingSelectFillInRange ?? textView.selectedRange()

        // Create select fill-in pill
        let pillString = PlaceholderPillRenderer.createSelectFillInDisplayString(
            label: selectFillInLabel,
            options: validOptions,
            defaultIndex: safeDefaultIndex
        )

        // Insert the pill
        if textView.shouldChangeText(in: range, replacementString: pillString.string) {
            textView.textStorage?.replaceCharacters(in: range, with: pillString)
            textView.didChangeText()

            // Move cursor after the pill
            let newLocation = range.location + pillString.length
            textView.setSelectedRange(NSRange(location: newLocation, length: 0))

            // Reset typing attributes to default
            DispatchQueue.main.async {
                textView.typingAttributes = [
                    .font: NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor.labelColor
                ]
            }
        }

        // Clear editing range
        editingSelectFillInRange = nil
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

// Fill-in input dialog
struct FillInInputDialog: View {
    @Binding var label: String
    @Binding var defaultValue: String
    let onInsert: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Single Fill-In")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Label")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g., Name", text: $label)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Default Value")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Optional", text: $defaultValue)
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
                .disabled(label.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

struct MultiLineFillInDialog: View {
    @Binding var label: String
    @Binding var defaultValue: String
    let onInsert: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Multi-Line Fill-In")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Label")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g., Message", text: $label)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Default Value")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $defaultValue)
                    .font(.system(size: 13))
                    .frame(height: 100)
                    .border(Color.secondary.opacity(0.2))
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
                .disabled(label.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

struct SelectFillInDialog: View {
    @Binding var label: String
    @Binding var options: [String]
    @Binding var defaultIndex: Int
    let onInsert: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Select Fill-In")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Label")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g., Priority", text: $label)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Options")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(options.indices, id: \.self) { index in
                    HStack {
                        TextField("Option \(index + 1)", text: $options[index])
                            .textFieldStyle(.roundedBorder)

                        // Radio button for default selection
                        Button(action: {
                            defaultIndex = index
                        }) {
                            Image(systemName: defaultIndex == index ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(defaultIndex == index ? .blue : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Set as default")

                        // Remove button
                        if options.count > 1 {
                            Button(action: {
                                if defaultIndex >= options.count - 1 && defaultIndex > 0 {
                                    defaultIndex -= 1
                                }
                                options.remove(at: index)
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button(action: {
                    options.append("")
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Option")
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
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
                .disabled(label.isEmpty || options.allSatisfy { $0.isEmpty })
            }
        }
        .padding(20)
        .frame(width: 450)
    }
}

// Custom cursor icon view showing "abc" with I-beam between a and bc
struct CursorIconView: View {
    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 1) {
                Text("a")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.primary)
                Text("bc")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.primary)
                    .offset(x: 2)
            }

            // I-beam cursor
            VStack(spacing: 0) {
                // Top serif
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 5, height: 1)

                // Vertical bar
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 1, height: 12)

                // Bottom serif
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 5, height: 1)
            }
            .offset(x: 6.0, y: 0.5)
        }
    }
}

// Custom fill-in field icon
struct FillInFieldIcon: View {
    var body: some View {
        VStack {
            ZStack {
                // Rectangle border representing a text field
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.primary, lineWidth: 1.5)
                    .frame(width: 30, height: 16)

                // Placeholder lines inside (like empty text field)
                HStack(spacing: 3) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.4))
                        .frame(width: 10, height: 2)
                    Rectangle()
                        .fill(Color.primary.opacity(0.4))
                        .frame(width: 8, height: 2)
                }
            }
        }
    }
}

// Date configuration dialog
struct DateConfigDialog: View {
    @Binding var yearFormat: String
    @Binding var monthFormat: String
    @Binding var dayFormat: String
    @Binding var weekdayFormat: String
    @Binding var separator: String
    let onInsert: () -> Void
    let onCancel: () -> Void

    @State private var previewText: String = ""
    @State private var isEditingPreview = false

    private func updatePreviewFromFormats() {
        // Build an array of selected components in logical order
        var components: [String] = []

        if !weekdayFormat.isEmpty {
            components.append(weekdayFormat)
        }
        if !monthFormat.isEmpty {
            components.append(monthFormat)
        }
        if !dayFormat.isEmpty {
            components.append(dayFormat)
        }
        if !yearFormat.isEmpty {
            components.append(yearFormat)
        }

        if components.isEmpty {
            previewText = "No format selected"
        } else {
            // Join with space by default, or use the existing separator structure if it has custom text
            let format = components.joined(separator: " ")
            let formatter = DateFormatter()
            formatter.dateFormat = format
            previewText = formatter.string(from: Date())
        }
    }

    private func parsePreviewToFormat() -> String {
        // Try to reverse-engineer the format from the preview text
        let format = previewText
        let now = Date()

        // Track what parts we've replaced so we can escape the rest
        var replacements: [(range: Range<String.Index>, formatCode: String)] = []

        // Find and collect all date component positions
        if !weekdayFormat.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = weekdayFormat
            let weekdayValue = formatter.string(from: now)
            if let range = format.range(of: weekdayValue) {
                replacements.append((range, weekdayFormat))
            }
        }

        if !monthFormat.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = monthFormat
            let monthValue = formatter.string(from: now)
            if let range = format.range(of: monthValue) {
                replacements.append((range, monthFormat))
            }
        }

        if !dayFormat.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = dayFormat
            let dayValue = formatter.string(from: now)
            if let range = format.range(of: dayValue) {
                replacements.append((range, dayFormat))
            }
        }

        if !yearFormat.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = yearFormat
            let yearValue = formatter.string(from: now)
            if let range = format.range(of: yearValue) {
                replacements.append((range, yearFormat))
            }
        }

        // Sort replacements by position
        replacements.sort { format.distance(from: format.startIndex, to: $0.range.lowerBound) < format.distance(from: format.startIndex, to: $1.range.lowerBound) }

        // Build the format string with literal text escaped in single quotes
        var result = ""
        var currentIndex = format.startIndex

        for (range, formatCode) in replacements {
            // Add any literal text before this date component (wrapped in quotes)
            if currentIndex < range.lowerBound {
                let literalText = String(format[currentIndex..<range.lowerBound])
                if !literalText.isEmpty {
                    result += "'\(literalText)'"
                }
            }

            // Add the format code
            result += formatCode
            currentIndex = range.upperBound
        }

        // Add any remaining literal text after the last date component
        if currentIndex < format.endIndex {
            let literalText = String(format[currentIndex..<format.endIndex])
            if !literalText.isEmpty {
                result += "'\(literalText)'"
            }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Configure Date Format")
                .font(.headline)

            // Editable Preview
            VStack(alignment: .leading, spacing: 4) {
                Text("Preview (editable - type to add custom text)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("", text: $previewText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
            }
            .onAppear {
                // If we have a dateSeparator (editing existing date), use it to generate preview
                if !separator.isEmpty {
                    let formatter = DateFormatter()
                    formatter.dateFormat = separator
                    previewText = formatter.string(from: Date())
                } else {
                    // New date, build from components
                    updatePreviewFromFormats()
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Year format
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Year")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            Button(action: {
                                yearFormat = ""
                                updatePreviewFromFormats()
                            }) {
                                Text("None")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(yearFormat.isEmpty ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)

                            Button(action: {
                                yearFormat = "yy"
                                updatePreviewFromFormats()
                            }) {
                                Text("2-digit (25)")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(yearFormat == "yy" ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)

                            Button(action: {
                                yearFormat = "yyyy"
                                updatePreviewFromFormats()
                            }) {
                                Text("4-digit (2025)")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(yearFormat == "yyyy" ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                        }
                    }

                    // Month format
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Month")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            Button(action: {
                                monthFormat = ""
                                updatePreviewFromFormats()
                            }) {
                                Text("None")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(monthFormat.isEmpty ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)

                            Button(action: {
                                monthFormat = "M"
                                updatePreviewFromFormats()
                            }) {
                                Text("1-2 (12)")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(monthFormat == "M" ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                        }

                        HStack(spacing: 8) {
                            Button(action: {
                                monthFormat = "MM"
                                updatePreviewFromFormats()
                            }) {
                                Text("2-digit (12)")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(monthFormat == "MM" ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)

                            Button(action: {
                                monthFormat = "MMM"
                                updatePreviewFromFormats()
                            }) {
                                Text("Short (Dec)")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(monthFormat == "MMM" ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)

                            Button(action: {
                                monthFormat = "MMMM"
                                updatePreviewFromFormats()
                            }) {
                                Text("Full (December)")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(monthFormat == "MMMM" ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                        }
                    }

                    // Day format
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Day")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            Button(action: {
                                dayFormat = ""
                                updatePreviewFromFormats()
                            }) {
                                Text("None")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(dayFormat.isEmpty ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)

                            Button(action: {
                                dayFormat = "d"
                                updatePreviewFromFormats()
                            }) {
                                Text("1-2 (4)")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(dayFormat == "d" ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)

                            Button(action: {
                                dayFormat = "dd"
                                updatePreviewFromFormats()
                            }) {
                                Text("2-digit (04)")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(dayFormat == "dd" ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                        }
                    }

                    // Weekday format
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Weekday")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            Button(action: {
                                weekdayFormat = ""
                                updatePreviewFromFormats()
                            }) {
                                Text("None")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(weekdayFormat.isEmpty ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)

                            Button(action: {
                                weekdayFormat = "EEE"
                                updatePreviewFromFormats()
                            }) {
                                Text("Short (Wed)")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(weekdayFormat == "EEE" ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)

                            Button(action: {
                                weekdayFormat = "EEEE"
                                updatePreviewFromFormats()
                            }) {
                                Text("Full (Wednesday)")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(weekdayFormat == "EEEE" ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                        }
                    }
                }
            }
            .frame(height: 350)

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Insert") {
                    // Update separator to store the final format
                    separator = parsePreviewToFormat()
                    onInsert()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(previewText.isEmpty || previewText == "No format selected")
            }
        }
        .padding(20)
        .frame(width: 500)
    }
}

// Time configuration dialog
struct TimeConfigDialog: View {
    @Binding var hourFormat: String
    @Binding var minuteFormat: String
    @Binding var secondFormat: String
    @Binding var ampmFormat: String
    @Binding var separator: String
    let onInsert: () -> Void
    let onCancel: () -> Void

    @State private var previewText: String = ""

    private func updatePreviewFromFormats() {
        // Build an array of selected components in logical order
        var components: [String] = []

        if !hourFormat.isEmpty {
            components.append(hourFormat)
        }
        if !minuteFormat.isEmpty {
            components.append(minuteFormat)
        }
        if !secondFormat.isEmpty {
            components.append(secondFormat)
        }
        if !ampmFormat.isEmpty {
            components.append(ampmFormat)
        }

        if components.isEmpty {
            previewText = "No format selected"
        } else {
            // Join with colon by default
            let format = components.joined(separator: ":")
            let formatter = DateFormatter()
            formatter.dateFormat = format
            previewText = formatter.string(from: Date())
        }
    }

    private func parsePreviewToFormat() -> String {
        // Try to reverse-engineer the format from the preview text
        let format = previewText
        let now = Date()

        // Track what parts we've replaced so we can escape the rest
        var replacements: [(range: Range<String.Index>, formatCode: String)] = []

        // Find and collect all time component positions
        if !hourFormat.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = hourFormat
            let hourValue = formatter.string(from: now)
            if let range = format.range(of: hourValue) {
                replacements.append((range, hourFormat))
            }
        }

        if !minuteFormat.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = minuteFormat
            let minuteValue = formatter.string(from: now)
            if let range = format.range(of: minuteValue) {
                replacements.append((range, minuteFormat))
            }
        }

        if !secondFormat.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = secondFormat
            let secondValue = formatter.string(from: now)
            if let range = format.range(of: secondValue) {
                replacements.append((range, secondFormat))
            }
        }

        if !ampmFormat.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = ampmFormat
            let ampmValue = formatter.string(from: now)
            if let range = format.range(of: ampmValue) {
                replacements.append((range, ampmFormat))
            }
        }

        // Sort replacements by position
        replacements.sort { format.distance(from: format.startIndex, to: $0.range.lowerBound) < format.distance(from: format.startIndex, to: $1.range.lowerBound) }

        // Build the format string with literal text escaped in single quotes
        var result = ""
        var currentIndex = format.startIndex

        for (range, formatCode) in replacements {
            // Add any literal text before this time component (wrapped in quotes)
            if currentIndex < range.lowerBound {
                let literalText = String(format[currentIndex..<range.lowerBound])
                if !literalText.isEmpty {
                    result += "'\(literalText)'"
                }
            }

            // Add the format code
            result += formatCode
            currentIndex = range.upperBound
        }

        // Add any remaining literal text after the last time component
        if currentIndex < format.endIndex {
            let literalText = String(format[currentIndex..<format.endIndex])
            if !literalText.isEmpty {
                result += "'\(literalText)'"
            }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Configure Time Format")
                .font(.headline)

            // Editable Preview
            VStack(alignment: .leading, spacing: 4) {
                Text("Preview (editable - type to add custom text)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("", text: $previewText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(6)
            }
            .onAppear {
                // If we have a timeSeparator (editing existing time), use it to generate preview
                if !separator.isEmpty {
                    let formatter = DateFormatter()
                    formatter.dateFormat = separator
                    previewText = formatter.string(from: Date())
                } else {
                    // New time, build from components
                    updatePreviewFromFormats()
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Hour format
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Hour")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            Button(action: {
                                hourFormat = ""
                                updatePreviewFromFormats()
                            }) {
                                Text("None")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(hourFormat.isEmpty ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)

                            Button(action: {
                                hourFormat = "H"
                                updatePreviewFromFormats()
                            }) {
                                Text("24hr 1-2 (0-23)")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(hourFormat == "H" ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                        }

                        HStack(spacing: 8) {
                            Button(action: {
                                hourFormat = "HH"
                                updatePreviewFromFormats()
                            }) {
                                Text("24hr 2-digit (00-23)")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(hourFormat == "HH" ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)

                            Button(action: {
                                hourFormat = "h"
                                updatePreviewFromFormats()
                            }) {
                                Text("12hr 1-2 (1-12)")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(hourFormat == "h" ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)

                            Button(action: {
                                hourFormat = "hh"
                                updatePreviewFromFormats()
                            }) {
                                Text("12hr 2-digit (01-12)")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(hourFormat == "hh" ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                        }
                    }

                    // Minute format
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Minute")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            Button(action: {
                                minuteFormat = ""
                                updatePreviewFromFormats()
                            }) {
                                Text("None")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(minuteFormat.isEmpty ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)

                            Button(action: {
                                minuteFormat = "m"
                                updatePreviewFromFormats()
                            }) {
                                Text("1-2 digits (0-59)")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(minuteFormat == "m" ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)

                            Button(action: {
                                minuteFormat = "mm"
                                updatePreviewFromFormats()
                            }) {
                                Text("2 digits (00-59)")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(minuteFormat == "mm" ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                        }
                    }

                    // Second format
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Second")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            Button(action: {
                                secondFormat = ""
                                updatePreviewFromFormats()
                            }) {
                                Text("None")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(secondFormat.isEmpty ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)

                            Button(action: {
                                secondFormat = "s"
                                updatePreviewFromFormats()
                            }) {
                                Text("1-2 digits (0-59)")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(secondFormat == "s" ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)

                            Button(action: {
                                secondFormat = "ss"
                                updatePreviewFromFormats()
                            }) {
                                Text("2 digits (00-59)")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(secondFormat == "ss" ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                        }
                    }

                    // AM/PM
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AM/PM")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            Button(action: {
                                ampmFormat = ""
                                updatePreviewFromFormats()
                            }) {
                                Text("None")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(ampmFormat.isEmpty ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)

                            Button(action: {
                                ampmFormat = "a"
                                updatePreviewFromFormats()
                            }) {
                                Text("Show AM/PM")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .background(ampmFormat == "a" ? Color.blue.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                        }
                    }
                }
            }
            .frame(height: 300)

            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Insert") {
                    // Update separator to store the final format
                    separator = parsePreviewToFormat()
                    onInsert()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(previewText.isEmpty || previewText == "No format selected")
            }
        }
        .padding(20)
        .frame(width: 500)
    }
}
