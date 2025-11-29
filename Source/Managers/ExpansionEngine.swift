import Cocoa
import ApplicationServices
import AppKit

class ExpansionEngine {
    static let shared = ExpansionEngine()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var typedBuffer: String = ""
    private let maxBufferLength = 50

    private var isEnabled = true

    func start() {
        // Check for accessibility permissions (will prompt automatically if needed)
        guard checkAccessibilityPermissions() else {
            print("❌ Accessibility permissions not granted")
            print("⚠️  To grant permissions, add this app to System Settings → Privacy & Security → Accessibility")
            print("📱 App Path: \(Bundle.main.bundlePath)")
            return
        }

        // Create event tap to monitor keyboard events
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let engine = Unmanaged<ExpansionEngine>.fromOpaque(refcon!).takeUnretainedValue()
                return engine.handleKeyEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("❌ Failed to create event tap")
            return
        }

        self.eventTap = eventTap

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        print("✅ Xpanda expansion engine started (\(XPManager.shared.xps.count) XPs loaded)")
    }

    func stop() {
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        print("Expansion engine stopped")
    }

    private func handleKeyEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isEnabled else {
            return Unmanaged.passRetained(event)
        }

        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            // Handle special keys first
            switch keyCode {
            case 51, 117: // Delete/Backspace
                if !typedBuffer.isEmpty {
                    typedBuffer.removeLast()
                }
                return Unmanaged.passRetained(event)
            case 36, 76: // Return/Enter - clear buffer
                typedBuffer = ""
                return Unmanaged.passRetained(event)
            case 48: // Tab - clear buffer
                typedBuffer = ""
                return Unmanaged.passRetained(event)
            case 53: // Escape - clear buffer
                typedBuffer = ""
                return Unmanaged.passRetained(event)
            default:
                break
            }

            // Get the character from the event
            if let nsEvent = NSEvent(cgEvent: event),
               let characters = nsEvent.characters,
               !characters.isEmpty {
                for char in characters {
                    handleCharacter(char, event: event, proxy: proxy)
                }
            }
        }

        return Unmanaged.passRetained(event)
    }

    private func handleCharacter(_ char: Character, event: CGEvent, proxy: CGEventTapProxy) {
        // Add character to buffer first
        typedBuffer.append(char)

        // Limit buffer size
        if typedBuffer.count > maxBufferLength {
            typedBuffer.removeFirst()
        }

        // Check for matches after every character
        if let match = findMatch() {
            performExpansion(xp: match, proxy: proxy)
        }
    }

    private func findMatch() -> XP? {
        // Check if any keyword matches the end of our buffer
        let manager = XPManager.shared

        for xp in manager.xps {
            let keyword = xp.keyword

            // Skip empty keywords
            guard !keyword.isEmpty else { continue }

            if typedBuffer.hasSuffix(keyword) {
                // Check if the character before the keyword is a word boundary (or start of buffer)
                let keywordStartIndex = typedBuffer.index(typedBuffer.endIndex, offsetBy: -keyword.count)

                if keywordStartIndex == typedBuffer.startIndex {
                    // Keyword is at the start of buffer - this is a match
                    return xp
                }

                let charBeforeIndex = typedBuffer.index(before: keywordStartIndex)
                let charBefore = typedBuffer[charBeforeIndex]

                // Check if it's a word boundary (space, newline, tab, etc.)
                if charBefore.isWhitespace || charBefore.isPunctuation {
                    return xp
                }
            }
        }

        return nil
    }

    private func performExpansion(xp: XP, proxy: CGEventTapProxy) {
        // Clear the typed buffer
        typedBuffer = ""

        // Temporarily disable the event tap during expansion to prevent interference
        isEnabled = false

        // Delete the keyword by simulating backspaces
        DispatchQueue.main.async {
            self.deleteText(count: xp.keyword.count)

            // Wait a bit for deletions to process
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Use paste method for all expansions (faster and more reliable)
                self.pasteExpansion(xp)

                // Re-enable event tap after expansion completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.isEnabled = true

                    // Add experience for using this XP
                    let leveledUp = XPManager.shared.addExperienceForExpansion()
                    if leveledUp {
                        // TODO: Show level-up notification
                        print("🎉 Level up! Now level \(XPManager.shared.progress.level)")
                    }
                }
            }
        }
    }

    private func deleteText(count: Int) {
        let deleteKey = CGKeyCode(51) // Backspace key code

        for _ in 0..<count {
            if let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: deleteKey, keyDown: true),
               let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: deleteKey, keyDown: false) {
                keyDownEvent.post(tap: .cghidEventTap)
                keyUpEvent.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.015)
            }
        }
    }

    private func typeText(_ text: String) {
        // Adjust typing speed based on text length
        // Longer text = slower to prevent system overload
        let delay: TimeInterval
        if text.count > 200 {
            delay = 0.02  // Very long text: 20ms per character
        } else if text.count > 50 {
            delay = 0.015 // Long text: 15ms per character
        } else {
            delay = 0.01  // Short text: 10ms per character
        }

        for char in text {
            // Type all characters (including newlines) as unicode strings
            // This prevents newlines from triggering form submissions
            let string = String(char)
            if let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
               let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                keyDownEvent.keyboardSetUnicodeString(stringLength: string.utf16.count, unicodeString: Array(string.utf16))
                keyUpEvent.keyboardSetUnicodeString(stringLength: string.utf16.count, unicodeString: Array(string.utf16))
                keyDownEvent.post(tap: .cghidEventTap)
                keyUpEvent.post(tap: .cghidEventTap)
            }
            Thread.sleep(forTimeInterval: delay)
        }
    }

    private func pasteExpansion(_ xp: XP) {
        let pasteboard = NSPasteboard.general

        // Save current clipboard contents before we clear it
        let savedClipboardString = pasteboard.string(forType: .string)

        print("📋 Pasting expansion for XP: \(xp.keyword)")
        print("   Saved clipboard: \(savedClipboardString ?? "nil")")
        print("   XP.expansion plain text: \(xp.expansion)")
        print("   XP.isRichText: \(xp.isRichText)")
        print("   XP.outputPlainText: \(xp.outputPlainText)")

        pasteboard.clearContents()

        if xp.outputPlainText {
            // Process placeholder replacement for plain text
            print("   → Using plain text output mode")
            let processedText = replacePlaceholders(in: xp.expansion, clipboardContent: savedClipboardString ?? "")
            pasteboard.setString(processedText, forType: .string)
        } else if xp.isRichText, let attributedString = xp.attributedString {
            // Process placeholder replacement for rich text
            print("   → Using rich text mode")
            let processedAttributedString = replacePlaceholders(in: attributedString, clipboardContent: savedClipboardString ?? "")
            pasteboard.writeObjects([processedAttributedString])
        } else {
            // Process placeholder replacement for plain text
            print("   → Using fallback plain text mode")
            let processedText = replacePlaceholders(in: xp.expansion, clipboardContent: savedClipboardString ?? "")
            pasteboard.setString(processedText, forType: .string)
        }

        // Simulate Cmd+V using CGEvent (more reliable than AppleScript)
        Thread.sleep(forTimeInterval: 0.05)

        let cmdKey = CGEventFlags.maskCommand
        let vKeyCode = CGKeyCode(9) // V key

        // Key down
        if let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true) {
            keyDownEvent.flags = cmdKey
            keyDownEvent.post(tap: .cghidEventTap)
        }

        Thread.sleep(forTimeInterval: 0.02)

        // Key up
        if let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) {
            keyUpEvent.flags = cmdKey
            keyUpEvent.post(tap: .cghidEventTap)
        }
    }

    private func checkAccessibilityPermissions() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Placeholder Replacement

    private func replacePlaceholders(in text: String, clipboardContent: String) -> String {
        var result = text

        print("🔍 Processing plain text for clipboard replacement")
        print("   Text: \(text)")

        // Replace {{clipboard}} with actual clipboard content
        result = result.replacingOccurrences(of: PlaceholderToken.clipboard.storageText, with: clipboardContent)

        print("   Result: \(result)")

        return result
    }

    private func replacePlaceholders(in attributedString: NSAttributedString, clipboardContent: String) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        let fullRange = NSRange(location: 0, length: mutableString.length)

        print("🔍 Processing attributed string for clipboard replacement")
        print("   String: \(mutableString.string)")
        print("   Length: \(mutableString.length)")

        // First, find and replace clipboard attachments (they appear as U+FFFC character)
        var indicesToReplace: [(range: NSRange, attributes: [NSAttributedString.Key: Any])] = []

        mutableString.enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, _ in
            if let _ = value as? NSTextAttachment {
                print("   ✓ Found attachment at range: \(range)")
                // Found an attachment, save its location and attributes
                var attributes = mutableString.attributes(at: range.location, effectiveRange: nil)
                // Remove the attachment attribute so we can replace with plain text
                attributes.removeValue(forKey: .attachment)
                indicesToReplace.append((range: range, attributes: attributes))
            }
        }

        print("   Found \(indicesToReplace.count) attachments to replace")

        // Replace attachments in reverse order to maintain correct ranges
        for item in indicesToReplace.reversed() {
            let replacement = NSAttributedString(string: clipboardContent, attributes: item.attributes)
            mutableString.replaceCharacters(in: item.range, with: replacement)
            print("   ✓ Replaced attachment with: \(clipboardContent)")
        }

        // Find U+FFFC characters (object replacement character) which indicate where attachments were
        let plainText = mutableString.string
        var replacementRanges: [(range: NSRange, attributes: [NSAttributedString.Key: Any])] = []

        for (index, char) in plainText.enumerated() {
            if char == "\u{FFFC}" {
                let nsRange = NSRange(location: index, length: 1)
                print("   ✓ Found U+FFFC character at index: \(index)")

                // Get attributes at this location
                var attributes: [NSAttributedString.Key: Any] = [:]
                if nsRange.location < mutableString.length {
                    attributes = mutableString.attributes(at: nsRange.location, effectiveRange: nil)
                    attributes.removeValue(forKey: .attachment)
                }
                replacementRanges.append((range: nsRange, attributes: attributes))
            }
        }

        // Replace U+FFFC characters in reverse order
        for item in replacementRanges.reversed() {
            let replacement = NSAttributedString(string: clipboardContent, attributes: item.attributes)
            mutableString.replaceCharacters(in: item.range, with: replacement)
            print("   ✓ Replaced U+FFFC with: \(clipboardContent)")
        }

        // Find and replace {{clipboard}} text placeholders
        let pattern = PlaceholderToken.clipboard.storageText
        var searchRange = NSRange(location: 0, length: mutableString.length)

        while searchRange.location < mutableString.length {
            let foundRange = (mutableString.string as NSString).range(of: pattern, options: [], range: searchRange)

            if foundRange.location == NSNotFound {
                break
            }

            print("   ✓ Found \(pattern) at range: \(foundRange)")

            // Get the attributes at this location (to preserve formatting around the placeholder)
            var attributes: [NSAttributedString.Key: Any] = [:]
            if foundRange.location < mutableString.length {
                attributes = mutableString.attributes(at: foundRange.location, effectiveRange: nil)
                // Use default text attributes
                attributes[.font] = NSFont.systemFont(ofSize: 13)
                attributes[.foregroundColor] = NSColor.labelColor
            }

            // Create replacement with normalized attributes
            let replacement = NSAttributedString(string: clipboardContent, attributes: attributes)
            mutableString.replaceCharacters(in: foundRange, with: replacement)

            print("   ✓ Replaced with: \(clipboardContent)")

            // Update search range
            searchRange.location = foundRange.location + clipboardContent.count
            searchRange.length = mutableString.length - searchRange.location
        }

        return mutableString
    }
}
