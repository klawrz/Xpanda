import SwiftUI
import AppKit

// Wrapper that includes both the toolbar and editor
struct RichTextEditorWithToolbar: View {
    @Binding var attributedString: NSAttributedString
    @StateObject private var textViewHolder = RichTextViewHolder()

    var body: some View {
        VStack(spacing: 0) {
            RichTextToolbar(textViewHolder: textViewHolder)
            RichTextEditor(attributedString: $attributedString, textViewHolder: textViewHolder)
                .border(Color.secondary.opacity(0.2))
        }
    }
}

struct RichTextEditor: NSViewRepresentable {
    @Binding var attributedString: NSAttributedString
    @ObservedObject var textViewHolder: RichTextViewHolder
    var isEditable: Bool = true

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

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

        // Set initial content
        textView.textStorage?.setAttributedString(attributedString)

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
    }
}

// Formatting toolbar for rich text
struct RichTextToolbar: View {
    @ObservedObject var textViewHolder: RichTextViewHolder
    @State private var isBoldActive = false
    @State private var isItalicActive = false
    @State private var isUnderlineActive = false
    @State private var updateTimer: Timer?

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

            Spacer()

            Text("Rich Text")
                .font(.caption)
                .foregroundColor(.secondary)
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
        var effectiveRange = NSRange()

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

}

// Helper to access NSTextView from SwiftUI
class RichTextViewHolder: ObservableObject {
    @Published var textView: NSTextView?
}
