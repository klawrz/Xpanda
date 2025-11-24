import SwiftUI
import AppKit

struct RichTextEditor: NSViewRepresentable {
    @Binding var attributedString: NSAttributedString
    var isEditable: Bool = true

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)

        // Set initial content
        textView.textStorage?.setAttributedString(attributedString)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only update if content is different to avoid cursor jumping
        if textView.attributedString() != attributedString {
            let selectedRange = textView.selectedRange()
            textView.textStorage?.setAttributedString(attributedString)
            textView.setSelectedRange(selectedRange)
        }

        textView.isEditable = isEditable
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.attributedString = textView.attributedString()
        }
    }
}

// Formatting toolbar for rich text
struct RichTextToolbar: View {
    let textView: NSTextView?

    var body: some View {
        HStack(spacing: 12) {
            // Bold
            Button(action: { toggleBold() }) {
                Image(systemName: "bold")
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .help("Bold (⌘B)")

            // Italic
            Button(action: { toggleItalic() }) {
                Image(systemName: "italic")
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .help("Italic (⌘I)")

            // Underline
            Button(action: { toggleUnderline() }) {
                Image(systemName: "underline")
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .help("Underline (⌘U)")

            Divider()
                .frame(height: 16)

            // Text Color
            ColorPicker("", selection: Binding(
                get: { getCurrentTextColor() },
                set: { setTextColor($0) }
            ))
            .labelsHidden()
            .frame(width: 30)
            .help("Text Color")

            Spacer()

            Text("Rich Text")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func toggleBold() {
        guard let textView = textView else { return }
        NSFontManager.shared.modifyFont(textView)
        textView.window?.makeFirstResponder(textView)
    }

    private func toggleItalic() {
        guard let textView = textView else { return }
        NSFontManager.shared.modifyFont(textView)
        textView.window?.makeFirstResponder(textView)
    }

    private func toggleUnderline() {
        guard let textView = textView else { return }
        textView.underline(nil)
        textView.window?.makeFirstResponder(textView)
    }

    private func getCurrentTextColor() -> Color {
        guard let textView = textView,
              let textColor = textView.textColor else {
            return Color.primary
        }
        return Color(textColor)
    }

    private func setTextColor(_ color: Color) {
        guard let textView = textView else { return }
        let nsColor = NSColor(color)
        textView.textColor = nsColor

        // Apply color to selected text
        let range = textView.selectedRange()
        if range.length > 0 {
            textView.textStorage?.addAttribute(.foregroundColor, value: nsColor, range: range)
        }
        textView.window?.makeFirstResponder(textView)
    }
}

// Helper to access NSTextView from SwiftUI
class RichTextViewHolder: ObservableObject {
    @Published var textView: NSTextView?
}
