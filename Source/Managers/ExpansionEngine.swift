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

    // Associated object keys for button handlers
    private static var cancelButtonPanelKey: UInt8 = 0
    private static var insertButtonWrapperKey: UInt8 = 0
    private static var previewUpdateKey: UInt8 = 0

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

        // Check if expansion contains fill-in fields
        let fillInFields = detectFillInFields(in: xp)

        if !fillInFields.isEmpty {
            // Show fill-in dialog on main thread
            DispatchQueue.main.async {
                self.showFillInDialog(for: xp, fields: fillInFields, proxy: proxy)
            }
        } else {
            // No fill-ins, proceed with normal expansion
            DispatchQueue.main.async {
                self.deleteText(count: xp.keyword.count)

                // Wait a bit for deletions to process
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // Paste the expansion (fast and reliable)
                    self.pasteExpansion(xp, fillInValues: [:])

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

    private func typeText(_ text: String) -> TimeInterval {
        // Use a consistent, slower typing speed for reliability
        // This prevents characters from being dropped or reordered
        let delay: TimeInterval = 0.02 // 20ms per character (50 chars/second)

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

        // Return total time taken to type
        return Double(text.count) * delay
    }

    private func typeExpansion(_ xp: XP, fillInValues: [String: String]) -> TimeInterval {
        // Read clipboard content (but don't modify it)
        let pasteboard = NSPasteboard.general
        let clipboardContent = pasteboard.string(forType: .string) ?? ""

        print("⌨️ Typing expansion for XP: \(xp.keyword)")
        print("   Clipboard content (read-only): \(clipboardContent)")
        print("   Fill-in values: \(fillInValues)")

        var cursorOffset: Int? = nil
        var textToType: String = ""

        if xp.outputPlainText {
            // Process placeholder replacement for plain text
            print("   → Using plain text output mode")
            let (processedText, offset) = replacePlaceholders(in: xp.expansion, clipboardContent: clipboardContent, fillInValues: fillInValues)
            cursorOffset = offset
            textToType = processedText
        } else if xp.isRichText, let attributedString = xp.attributedString {
            // Process placeholder replacement for rich text - convert to plain text
            print("   → Using rich text mode (converting to plain text)")
            let (processedAttributedString, offset) = replacePlaceholders(in: attributedString, clipboardContent: clipboardContent, fillInValues: fillInValues)
            cursorOffset = offset
            textToType = processedAttributedString.string
        } else {
            // Process placeholder replacement for plain text
            print("   → Using fallback plain text mode")
            let (processedText, offset) = replacePlaceholders(in: xp.expansion, clipboardContent: clipboardContent, fillInValues: fillInValues)
            cursorOffset = offset
            textToType = processedText
        }

        // Type the text and get timing
        let typingTime = typeText(textToType)
        print("   Typed \(textToType.count) characters in \(typingTime) seconds")

        // Reposition cursor if needed
        if let offset = cursorOffset {
            let stepsBack = textToType.count - offset

            print("🎯 Repositioning cursor:")
            print("   Text length: \(textToType.count)")
            print("   Cursor should be at: \(offset)")
            print("   Steps back from end: \(stepsBack)")

            // Move cursor left by the calculated steps
            moveCursorLeft(steps: stepsBack)
        }

        print("   ✓ Expansion typed (clipboard untouched)")
        return typingTime
    }

    private func pasteExpansion(_ xp: XP, fillInValues: [String: String]) {
        let pasteboard = NSPasteboard.general

        // Save current clipboard contents before we clear it
        let savedClipboardString = pasteboard.string(forType: .string)

        print("📋 Pasting expansion for XP: \(xp.keyword)")
        print("   Saved clipboard: \(savedClipboardString ?? "nil")")
        print("   XP.expansion plain text: \(xp.expansion)")
        print("   XP.isRichText: \(xp.isRichText)")
        print("   XP.outputPlainText: \(xp.outputPlainText)")
        print("   Fill-in values: \(fillInValues)")

        pasteboard.clearContents()

        var cursorOffset: Int? = nil

        if xp.outputPlainText {
            // Process placeholder replacement for plain text
            print("   → Using plain text output mode")
            let (processedText, offset) = replacePlaceholders(in: xp.expansion, clipboardContent: savedClipboardString ?? "", fillInValues: fillInValues)
            cursorOffset = offset
            pasteboard.setString(processedText, forType: .string)
        } else if xp.isRichText, let attributedString = xp.attributedString {
            // Process placeholder replacement for rich text
            print("   → Using rich text mode")
            let (processedAttributedString, offset) = replacePlaceholders(in: attributedString, clipboardContent: savedClipboardString ?? "", fillInValues: fillInValues)
            cursorOffset = offset
            pasteboard.writeObjects([processedAttributedString])
        } else {
            // Process placeholder replacement for plain text
            print("   → Using fallback plain text mode")
            let (processedText, offset) = replacePlaceholders(in: xp.expansion, clipboardContent: savedClipboardString ?? "", fillInValues: fillInValues)
            cursorOffset = offset
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

        // Wait for paste to complete before any further operations
        Thread.sleep(forTimeInterval: 0.1)

        // Reposition cursor if needed
        if let offset = cursorOffset {
            // Get the final text length from pasteboard to calculate cursor position
            if let pastedString = pasteboard.string(forType: .string) {
                let textLength = pastedString.count
                let stepsBack = textLength - offset

                print("🎯 Repositioning cursor:")
                print("   Text length: \(textLength)")
                print("   Cursor should be at: \(offset)")
                print("   Steps back from end: \(stepsBack)")

                // Move cursor left by the calculated steps
                moveCursorLeft(steps: stepsBack)
            }
        }

        // Restore original clipboard contents after a safe delay (2 seconds)
        // This gives all applications enough time to read from the clipboard
        // Use a background thread to avoid blocking
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 2.0) {
            let pasteboard = NSPasteboard.general
            if let savedClipboard = savedClipboardString {
                pasteboard.clearContents()
                pasteboard.setString(savedClipboard, forType: .string)
                print("   ✓ Restored original clipboard content after 2 second delay")
            } else {
                pasteboard.clearContents()
                print("   ✓ Cleared clipboard after 2 second delay (was empty before)")
            }
        }
    }

    private func moveCursorLeft(steps: Int) {
        guard steps > 0 else { return }

        let leftArrowKey = CGKeyCode(123) // Left arrow key code

        for _ in 0..<steps {
            if let keyDownEvent = CGEvent(keyboardEventSource: nil, virtualKey: leftArrowKey, keyDown: true),
               let keyUpEvent = CGEvent(keyboardEventSource: nil, virtualKey: leftArrowKey, keyDown: false) {
                keyDownEvent.post(tap: .cghidEventTap)
                keyUpEvent.post(tap: .cghidEventTap)
                Thread.sleep(forTimeInterval: 0.01) // Small delay between key presses
            }
        }

        print("   ✓ Moved cursor \(steps) positions to the left")
    }

    private func checkAccessibilityPermissions() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Placeholder Replacement

    private func replacePlaceholders(in text: String, clipboardContent: String, fillInValues: [String: String]) -> (text: String, cursorOffset: Int?) {
        var result = text
        var cursorOffset: Int? = nil

        print("🔍 Processing plain text for placeholder replacement")
        print("   Text: \(text)")

        // Find cursor position before removing it
        if let cursorRange = result.range(of: PlaceholderToken.cursor.storageText) {
            cursorOffset = result.distance(from: result.startIndex, to: cursorRange.lowerBound)
            print("   Found cursor at offset: \(cursorOffset!)")
        }

        // Remove {{cursor}} placeholder
        result = result.replacingOccurrences(of: PlaceholderToken.cursor.storageText, with: "")

        // Replace {{clipboard}} with actual clipboard content
        // Track changes to adjust cursor offset
        if let offset = cursorOffset {
            let clipboardToken = PlaceholderToken.clipboard.storageText
            var searchPos = result.startIndex

            while let range = result.range(of: clipboardToken, range: searchPos..<result.endIndex) {
                let rangeOffset = result.distance(from: result.startIndex, to: range.lowerBound)

                // Only adjust cursor if replacement is before cursor
                if rangeOffset < offset {
                    let lengthDiff = clipboardContent.count - clipboardToken.count
                    cursorOffset = offset + lengthDiff
                }

                result.replaceSubrange(range, with: clipboardContent)

                // Update search position
                let newPos = result.index(result.startIndex, offsetBy: rangeOffset + clipboardContent.count)
                if newPos >= result.endIndex { break }
                searchPos = newPos
            }
        } else {
            result = result.replacingOccurrences(of: PlaceholderToken.clipboard.storageText, with: clipboardContent)
        }

        // Replace fill-in fields (pattern: {{fillin_single|label|defaultValue}} and {{fillin_multi|label|defaultValue}})
        let singlePattern = "\\{\\{fillin_single\\|([^|]*)\\|([^}]*)\\}\\}"
        if let regex = try? NSRegularExpression(pattern: singlePattern, options: []) {
            let nsText = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsText.length))

            // Replace in reverse order to maintain correct indices
            for match in matches.reversed() {
                let labelRange = match.range(at: 1)
                let label = nsText.substring(with: labelRange)
                let replacement = fillInValues[label] ?? ""

                // Adjust cursor offset if replacement is before cursor
                if let offset = cursorOffset, match.range.location < offset {
                    let lengthDiff = replacement.count - match.range.length
                    cursorOffset = offset + lengthDiff
                }

                result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
            }
        }

        // Replace multi-line fill-in fields (pattern: {{fillin_multi|label|defaultValue}})
        let multiPattern = "\\{\\{fillin_multi\\|([^|]*)\\|([^}]*)\\}\\}"
        if let regex = try? NSRegularExpression(pattern: multiPattern, options: []) {
            let nsText = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsText.length))

            // Replace in reverse order to maintain correct indices
            for match in matches.reversed() {
                let labelRange = match.range(at: 1)
                let label = nsText.substring(with: labelRange)
                let replacement = fillInValues[label] ?? ""

                // Adjust cursor offset if replacement is before cursor
                if let offset = cursorOffset, match.range.location < offset {
                    let lengthDiff = replacement.count - match.range.length
                    cursorOffset = offset + lengthDiff
                }

                result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
            }
        }

        // Replace select fill-in fields (pattern: {{fillin_select|label|option1,option2|defaultIndex}})
        let selectPattern = "\\{\\{fillin_select\\|([^|]*)\\|([^|]*)\\|([^}]*)\\}\\}"
        if let regex = try? NSRegularExpression(pattern: selectPattern, options: []) {
            let nsText = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsText.length))

            // Replace in reverse order to maintain correct indices
            for match in matches.reversed() {
                let labelRange = match.range(at: 1)
                let label = nsText.substring(with: labelRange)
                let replacement = fillInValues[label] ?? ""

                // Adjust cursor offset if replacement is before cursor
                if let offset = cursorOffset, match.range.location < offset {
                    let lengthDiff = replacement.count - match.range.length
                    cursorOffset = offset + lengthDiff
                }

                result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
            }
        }

        print("   Result: \(result)")
        print("   Cursor offset: \(cursorOffset?.description ?? "none")")

        return (result, cursorOffset)
    }

    private func replacePlaceholders(in attributedString: NSAttributedString, clipboardContent: String, fillInValues: [String: String]) -> (attributedString: NSAttributedString, cursorOffset: Int?) {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        let fullRange = NSRange(location: 0, length: mutableString.length)
        var cursorOffset: Int? = nil

        print("🔍 Processing attributed string for clipboard and cursor replacement")
        print("   String: \(mutableString.string)")
        print("   Length: \(mutableString.length)")

        // First, find and process placeholder attachments (they appear as U+FFFC character)
        var indicesToReplace: [(range: NSRange, attributes: [NSAttributedString.Key: Any], replacementText: String)] = []

        mutableString.enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, _ in
            if let attachment = value as? NSTextAttachment,
               let fileWrapper = attachment.fileWrapper,
               let data = fileWrapper.regularFileContents {

                // Check if it's a fill-in attachment (JSON)
                if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let type = json["type"] as? String,
                   (type == "fillin_single" || type == "fillin_multi" || type == "fillin_select"),
                   let label = json["label"] as? String {
                    print("   ✓ Found \(type) attachment at range: \(range) with label: \(label)")

                    let replacementText = fillInValues[label] ?? ""
                    print("     → Replacing with value: \(replacementText)")

                    // Get attributes at this location to preserve formatting
                    var attributes: [NSAttributedString.Key: Any] = [:]
                    if range.location < mutableString.length {
                        attributes = mutableString.attributes(at: range.location, effectiveRange: nil)
                        attributes[.font] = NSFont.systemFont(ofSize: 13)
                        attributes[.foregroundColor] = NSColor.labelColor
                    }
                    indicesToReplace.append((range: range, attributes: attributes, replacementText: replacementText))
                }
                // Check if it's a placeholder token (plain text)
                else if let storageText = String(data: data, encoding: .utf8) {
                    print("   ✓ Found attachment at range: \(range) with text: \(storageText)")

                    // Determine replacement based on placeholder type
                    var replacementText = ""
                    if storageText == PlaceholderToken.clipboard.storageText {
                        replacementText = clipboardContent
                        print("     → Clipboard placeholder, replacing with clipboard content")
                    } else if storageText == PlaceholderToken.cursor.storageText {
                        replacementText = "" // Remove cursor placeholder
                        if cursorOffset == nil {
                            cursorOffset = range.location
                            print("     → Cursor placeholder found at offset: \(range.location)")
                        }
                    }

                    // Found a placeholder attachment
                    var attributes = mutableString.attributes(at: range.location, effectiveRange: nil)
                    attributes.removeValue(forKey: .attachment)
                    indicesToReplace.append((range: range, attributes: attributes, replacementText: replacementText))
                }
            }
        }

        print("   Found \(indicesToReplace.count) placeholder attachments")

        // Replace attachments in reverse order to maintain correct ranges
        // Track cursor offset adjustments
        for item in indicesToReplace.reversed() {
            // Adjust cursor offset if this replacement is before the cursor
            if let offset = cursorOffset, item.range.location < offset {
                let lengthDiff = item.replacementText.count - item.range.length
                cursorOffset = offset + lengthDiff
                print("   ✓ Adjusting cursor offset by \(lengthDiff) to \(cursorOffset!)")
            }

            let replacement = NSAttributedString(string: item.replacementText, attributes: item.attributes)
            mutableString.replaceCharacters(in: item.range, with: replacement)
            print("   ✓ Replaced attachment with: \"\(item.replacementText)\"")
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
            // Adjust cursor offset if this replacement is before the cursor
            if let offset = cursorOffset, item.range.location < offset {
                let lengthDiff = clipboardContent.count - item.range.length
                cursorOffset = offset + lengthDiff
                print("   ✓ Adjusting cursor offset by \(lengthDiff) to \(cursorOffset!)")
            }

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

            // Adjust cursor offset if this replacement is before the cursor
            if let offset = cursorOffset, foundRange.location < offset {
                let lengthDiff = clipboardContent.count - foundRange.length
                cursorOffset = offset + lengthDiff
                print("   ✓ Adjusting cursor offset by \(lengthDiff) to \(cursorOffset!)")
            }

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

        // Find and remove {{cursor}} text placeholders
        let cursorPattern = PlaceholderToken.cursor.storageText
        var cursorSearchRange = NSRange(location: 0, length: mutableString.length)

        while cursorSearchRange.location < mutableString.length {
            let foundRange = (mutableString.string as NSString).range(of: cursorPattern, options: [], range: cursorSearchRange)

            if foundRange.location == NSNotFound {
                break
            }

            print("   ✓ Found \(cursorPattern) at range: \(foundRange)")

            // Track cursor position if not already found
            if cursorOffset == nil {
                cursorOffset = foundRange.location
                print("   ✓ Cursor position tracked at offset: \(foundRange.location)")
            }

            // Get the attributes at this location (to preserve formatting)
            var attributes: [NSAttributedString.Key: Any] = [:]
            if foundRange.location < mutableString.length {
                attributes = mutableString.attributes(at: foundRange.location, effectiveRange: nil)
            }

            // Replace with empty string (remove the cursor placeholder)
            let replacement = NSAttributedString(string: "", attributes: attributes)
            mutableString.replaceCharacters(in: foundRange, with: replacement)

            print("   ✓ Removed cursor placeholder")

            // Update search range (since we removed text, location stays the same)
            cursorSearchRange.location = foundRange.location
            cursorSearchRange.length = mutableString.length - cursorSearchRange.location
        }

        print("   Final cursor offset: \(cursorOffset?.description ?? "none")")
        return (mutableString, cursorOffset)
    }

    // MARK: - Fill-In Field Handling

    struct FillInField {
        let label: String
        let defaultValue: String
        let isMultiLine: Bool
        let isSelect: Bool
        let options: [String]?
        let defaultIndex: Int?
    }

    // Wrapper class to store fill-in dialog data for associated objects
    class FillInDataWrapper {
        let fields: [(label: String, control: NSView, isMultiLine: Bool)]
        let panel: NSPanel
        let xp: XP
        let previousApp: NSRunningApplication?

        init(fields: [(label: String, control: NSView, isMultiLine: Bool)], panel: NSPanel, xp: XP, previousApp: NSRunningApplication?) {
            self.fields = fields
            self.panel = panel
            self.xp = xp
            self.previousApp = previousApp
        }
    }

    // Flipped view for top-to-bottom layout
    class FlippedView: NSView {
        override var isFlipped: Bool { return true }
    }

    private func detectFillInFields(in xp: XP) -> [FillInField] {
        var fields: [FillInField] = []

        // Get the text to search
        let textToSearch: String
        if xp.isRichText, let data = xp.richTextData,
           let loadedString = try? NSAttributedString(
               data: data,
               options: [NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            textToSearch = loadedString.string
        } else {
            textToSearch = xp.expansion
        }

        let nsText = textToSearch as NSString

        // Pattern: {{fillin_single|label|defaultValue}}
        let singlePattern = "\\{\\{fillin_single\\|([^|]*)\\|([^}]*)\\}\\}"
        if let regex = try? NSRegularExpression(pattern: singlePattern, options: []) {
            let matches = regex.matches(in: textToSearch, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                let labelRange = match.range(at: 1)
                let defaultRange = match.range(at: 2)
                let label = nsText.substring(with: labelRange)
                let defaultValue = nsText.substring(with: defaultRange)
                fields.append(FillInField(label: label, defaultValue: defaultValue, isMultiLine: false, isSelect: false, options: nil, defaultIndex: nil))
            }
        }

        // Pattern: {{fillin_multi|label|defaultValue}}
        let multiPattern = "\\{\\{fillin_multi\\|([^|]*)\\|([^}]*)\\}\\}"
        if let regex = try? NSRegularExpression(pattern: multiPattern, options: []) {
            let matches = regex.matches(in: textToSearch, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                let labelRange = match.range(at: 1)
                let defaultRange = match.range(at: 2)
                let label = nsText.substring(with: labelRange)
                let defaultValue = nsText.substring(with: defaultRange)
                fields.append(FillInField(label: label, defaultValue: defaultValue, isMultiLine: true, isSelect: false, options: nil, defaultIndex: nil))
            }
        }

        // Pattern: {{fillin_select|label|option1,option2,option3|defaultIndex}}
        let selectPattern = "\\{\\{fillin_select\\|([^|]*)\\|([^|]*)\\|([^}]*)\\}\\}"
        if let regex = try? NSRegularExpression(pattern: selectPattern, options: []) {
            let matches = regex.matches(in: textToSearch, options: [], range: NSRange(location: 0, length: nsText.length))
            for match in matches {
                let labelRange = match.range(at: 1)
                let optionsRange = match.range(at: 2)
                let defaultIndexRange = match.range(at: 3)
                let label = nsText.substring(with: labelRange)
                let optionsString = nsText.substring(with: optionsRange)
                let defaultIndexString = nsText.substring(with: defaultIndexRange)

                let options = optionsString.components(separatedBy: ",")
                let defaultIndex = Int(defaultIndexString) ?? 0

                fields.append(FillInField(label: label, defaultValue: "", isMultiLine: false, isSelect: true, options: options, defaultIndex: defaultIndex))
            }
        }

        return fields
    }

    private func showFillInDialog(for xp: XP, fields: [FillInField], proxy: CGEventTapProxy) {
        print("🎯 Showing fill-in dialog for \(fields.count) fields")

        // Get the expansion text
        let expansionText: String
        if xp.isRichText, let data = xp.richTextData,
           let loadedString = try? NSAttributedString(
               data: data,
               options: [NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            expansionText = loadedString.string
        } else {
            expansionText = xp.expansion
        }

        print("   Expansion text: \(expansionText)")

        // Create a panel
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Fill in values"
        panel.minSize = NSSize(width: 400, height: 300)
        panel.center()

        // Create main container with flipped coordinates
        let containerView = FlippedView(frame: panel.contentView!.bounds)
        containerView.autoresizingMask = [.width, .height]

        var yOffset: CGFloat = 16

        // Create preview section
        let previewLabel = NSTextField(labelWithString: "Preview:")
        previewLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        previewLabel.frame = NSRect(x: 16, y: yOffset, width: 468, height: 20)
        containerView.addSubview(previewLabel)
        yOffset += 24

        // Create preview text view (scrollable)
        let previewScrollView = NSScrollView(frame: NSRect(x: 16, y: yOffset, width: 468, height: 120))
        previewScrollView.hasVerticalScroller = true
        previewScrollView.autohidesScrollers = true
        previewScrollView.borderType = .bezelBorder
        previewScrollView.autoresizingMask = [.width]

        let previewTextView = NSTextView(frame: previewScrollView.bounds)
        previewTextView.isEditable = false
        previewTextView.isSelectable = true
        previewTextView.font = NSFont.systemFont(ofSize: 13)
        previewTextView.backgroundColor = NSColor.controlBackgroundColor
        previewTextView.textContainerInset = NSSize(width: 8, height: 8)
        previewTextView.autoresizingMask = [.width]

        previewScrollView.documentView = previewTextView
        containerView.addSubview(previewScrollView)
        yOffset += 128

        // Create divider
        let divider = NSBox(frame: NSRect(x: 0, y: yOffset, width: 500, height: 1))
        divider.boxType = .separator
        divider.autoresizingMask = [.width]
        containerView.addSubview(divider)
        yOffset += 12

        // Create fields section
        let fieldsLabel = NSTextField(labelWithString: "Fill in the fields:")
        fieldsLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        fieldsLabel.frame = NSRect(x: 16, y: yOffset, width: 468, height: 20)
        containerView.addSubview(fieldsLabel)
        yOffset += 24

        // Create text fields/text views for each fill-in
        var inputControls: [(label: String, control: NSView, isMultiLine: Bool)] = []

        for field in fields {
            // Add field label
            let label = NSTextField(labelWithString: field.label)
            label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 16, y: yOffset, width: 468, height: 16)
            containerView.addSubview(label)
            yOffset += 20

            if field.isSelect {
                // Add popup button for select field
                let popupButton = NSPopUpButton(frame: NSRect(x: 16, y: yOffset, width: 468, height: 26), pullsDown: false)
                popupButton.font = NSFont.systemFont(ofSize: 13)

                // Add options to popup
                if let options = field.options {
                    for option in options {
                        popupButton.addItem(withTitle: option)
                    }
                    // Select the default option
                    if let defaultIndex = field.defaultIndex, defaultIndex < options.count {
                        popupButton.selectItem(at: defaultIndex)
                    }
                }

                containerView.addSubview(popupButton)
                inputControls.append((label: field.label, control: popupButton, isMultiLine: false))
                yOffset += 34
            } else if field.isMultiLine {
                // Add multi-line text view (scrollable)
                let scrollView = NSScrollView(frame: NSRect(x: 16, y: yOffset, width: 468, height: 80))
                scrollView.hasVerticalScroller = true
                scrollView.autohidesScrollers = true
                scrollView.borderType = .bezelBorder
                scrollView.autoresizingMask = [.width]

                let textView = NSTextView(frame: scrollView.bounds)
                textView.isEditable = true
                textView.isSelectable = true
                textView.font = NSFont.systemFont(ofSize: 13)
                textView.textContainerInset = NSSize(width: 4, height: 4)
                textView.autoresizingMask = [.width]
                textView.string = field.defaultValue

                scrollView.documentView = textView
                containerView.addSubview(scrollView)
                inputControls.append((label: field.label, control: textView, isMultiLine: true))
                yOffset += 88
            } else {
                // Add single-line text field
                let textField = NSTextField(string: field.defaultValue)
                textField.placeholderString = field.label
                textField.font = NSFont.systemFont(ofSize: 13)
                textField.frame = NSRect(x: 16, y: yOffset, width: 468, height: 24)
                containerView.addSubview(textField)
                inputControls.append((label: field.label, control: textField, isMultiLine: false))
                yOffset += 32
            }
        }

        yOffset += 8

        print("   Created \(inputControls.count) input controls (\(inputControls.filter { $0.isMultiLine }.count) multi-line)")

        // Function to update preview
        let updatePreview = {
            var previewText = expansionText

            // Replace each fill-in pattern with its current value
            for (label, control, isMultiLine) in inputControls {
                // Determine the pattern type
                let patternType: String
                if control is NSPopUpButton {
                    patternType = "fillin_select"
                } else if isMultiLine {
                    patternType = "fillin_multi"
                } else {
                    patternType = "fillin_single"
                }

                let pattern = "\\{\\{\(patternType)\\|\(NSRegularExpression.escapedPattern(for: label))\\|[^}]*\\}\\}"
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let range = NSRange(location: 0, length: (previewText as NSString).length)

                    // Get the value based on control type
                    let value: String
                    if let textField = control as? NSTextField {
                        value = textField.stringValue
                    } else if let textView = control as? NSTextView {
                        value = textView.string
                    } else if let popupButton = control as? NSPopUpButton {
                        value = popupButton.titleOfSelectedItem ?? ""
                    } else {
                        value = ""
                    }

                    previewText = regex.stringByReplacingMatches(
                        in: previewText,
                        options: [],
                        range: range,
                        withTemplate: value
                    )
                }
            }

            previewTextView.string = previewText
        }

        // Initial preview update
        updatePreview()

        // Add observers to controls to update preview on change
        for (_, control, _) in inputControls {
            if let textField = control as? NSTextField {
                textField.target = nil
                textField.action = #selector(NSTextField.selectText(_:))

                // Use NotificationCenter to observe text changes
                NotificationCenter.default.addObserver(
                    forName: NSControl.textDidChangeNotification,
                    object: textField,
                    queue: .main
                ) { _ in
                    updatePreview()
                }
            } else if let textView = control as? NSTextView {
                // Use NotificationCenter to observe text changes
                NotificationCenter.default.addObserver(
                    forName: NSText.didChangeNotification,
                    object: textView,
                    queue: .main
                ) { _ in
                    updatePreview()
                }
            } else if let popupButton = control as? NSPopUpButton {
                // Add action to popup button to update preview on selection change
                popupButton.target = self
                popupButton.action = #selector(popupButtonChanged(_:))

                // Store the update closure in associated object
                objc_setAssociatedObject(popupButton, &ExpansionEngine.previewUpdateKey, updatePreview, .OBJC_ASSOCIATION_RETAIN)
            }
        }

        // Create buttons at bottom
        let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
        cancelButton.frame = NSRect(x: 20, y: yOffset + 8, width: 80, height: 30)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}" // Escape key
        containerView.addSubview(cancelButton)

        let insertButton = NSButton(title: "Insert", target: nil, action: nil)
        insertButton.frame = NSRect(x: 400, y: yOffset + 8, width: 80, height: 30)
        insertButton.bezelStyle = .rounded
        insertButton.keyEquivalent = "\r" // Return key
        containerView.addSubview(insertButton)

        yOffset += 50

        // Update container view size to fit all content
        containerView.frame.size.height = yOffset + 16

        // Adjust panel height to fit content
        var panelFrame = panel.frame
        panelFrame.size.height = min(max(yOffset + 16, 400), 700) // Min 400, max 700
        panel.setFrame(panelFrame, display: false)
        panel.center()

        panel.contentView = containerView

        // Handle button actions
        cancelButton.target = self
        cancelButton.action = #selector(handleFillInCancel(_:))

        // Store panel reference for cancel handler
        objc_setAssociatedObject(cancelButton, &ExpansionEngine.cancelButtonPanelKey, panel, .OBJC_ASSOCIATION_RETAIN)

        insertButton.target = self
        insertButton.action = #selector(handleFillInInsert(_:))

        // Make the insert button the default button (blue and responds to Return)
        panel.defaultButtonCell = insertButton.cell as? NSButtonCell

        // Capture the currently active application (the text editor)
        let previousApp = NSWorkspace.shared.frontmostApplication

        // Create a wrapper to store the data including the previous app
        let wrapper = FillInDataWrapper(fields: inputControls, panel: panel, xp: xp, previousApp: previousApp)
        objc_setAssociatedObject(insertButton, &ExpansionEngine.insertButtonWrapperKey, wrapper, .OBJC_ASSOCIATION_RETAIN)

        // Activate Xpanda and show the panel first
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        // Then hide all main windows (leaving only the panel visible)
        DispatchQueue.main.async {
            for window in NSApp.windows {
                if window != panel && window.isVisible {
                    window.orderOut(nil)
                }
            }
        }

        // Focus first control
        if let firstControl = inputControls.first?.control {
            panel.makeFirstResponder(firstControl)
        }

        print("   Showing fill-in dialog...")
    }

    @objc private func popupButtonChanged(_ sender: NSPopUpButton) {
        // Get the update closure from associated object
        if let updateClosure = objc_getAssociatedObject(sender, &ExpansionEngine.previewUpdateKey) as? () -> Void {
            updateClosure()
        }
    }

    @objc private func handleFillInCancel(_ sender: NSButton) {
        guard let panel = objc_getAssociatedObject(sender, &ExpansionEngine.cancelButtonPanelKey) as? NSPanel else {
            print("   ❌ Failed to get panel")
            return
        }

        print("   User cancelled")
        panel.close()

        // Restore main windows
        for window in NSApp.windows {
            if window != panel && window.canBecomeKey {
                window.orderFront(nil)
            }
        }

        self.isEnabled = true
    }

    @objc private func handleFillInInsert(_ sender: NSButton) {
        guard let wrapper = objc_getAssociatedObject(sender, &ExpansionEngine.insertButtonWrapperKey) as? FillInDataWrapper else {
            print("   ❌ Failed to get wrapper")
            return
        }

        // Collect values from controls
        var fillInValues: [String: String] = [:]
        for (label, control, _) in wrapper.fields {
            if let textField = control as? NSTextField {
                fillInValues[label] = textField.stringValue
            } else if let textView = control as? NSTextView {
                fillInValues[label] = textView.string
            } else if let popupButton = control as? NSPopUpButton {
                fillInValues[label] = popupButton.titleOfSelectedItem ?? ""
            }
        }

        print("   Collected values: \(fillInValues)")

        // Close panel
        wrapper.panel.close()

        // Restore main windows
        for window in NSApp.windows {
            if window != wrapper.panel && window.canBecomeKey {
                window.orderFront(nil)
            }
        }

        // Switch back to the previous application (text editor) before doing expansion
        if let previousApp = wrapper.previousApp {
            previousApp.activate(options: .activateIgnoringOtherApps)
        }

        // Wait for app switch to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Delete the keyword and perform expansion with fill-in values
            self.deleteText(count: wrapper.xp.keyword.count)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.pasteExpansion(wrapper.xp, fillInValues: fillInValues)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.isEnabled = true

                    let leveledUp = XPManager.shared.addExperienceForExpansion()
                    if leveledUp {
                        print("🎉 Level up! Now level \(XPManager.shared.progress.level)")
                    }
                }
            }
        }
    }

    private func parseTextSegments(_ text: String) -> [TextSegment] {
        var segments: [TextSegment] = []

        let pattern = "\\{\\{fillin_single\\|([^|]*)\\|([^}]*)\\}\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [TextSegment(text: text)]
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        var currentIndex = 0

        for match in matches {
            // Add text before this match
            if match.range.location > currentIndex {
                let beforeRange = NSRange(location: currentIndex, length: match.range.location - currentIndex)
                let beforeText = nsText.substring(with: beforeRange)
                if !beforeText.isEmpty {
                    segments.append(TextSegment(text: beforeText))
                }
            }

            // Add the fill-in field
            let labelRange = match.range(at: 1)
            let defaultRange = match.range(at: 2)
            let label = nsText.substring(with: labelRange)
            let defaultValue = nsText.substring(with: defaultRange)
            segments.append(TextSegment(label: label, defaultValue: defaultValue))

            currentIndex = match.range.location + match.range.length
        }

        // Add remaining text after last match
        if currentIndex < nsText.length {
            let remainingRange = NSRange(location: currentIndex, length: nsText.length - currentIndex)
            let remainingTextStr = nsText.substring(with: remainingRange)
            if !remainingTextStr.isEmpty {
                segments.append(TextSegment(text: remainingTextStr))
            }
        }

        return segments
    }

    struct TextSegment {
        let text: String
        let isField: Bool
        let label: String
        let defaultValue: String

        init(text: String) {
            self.text = text
            self.isField = false
            self.label = ""
            self.defaultValue = ""
        }

        init(label: String, defaultValue: String) {
            self.text = ""
            self.isField = true
            self.label = label
            self.defaultValue = defaultValue
        }
    }
}
