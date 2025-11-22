import Cocoa
import ApplicationServices

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
            performExpansion(keyword: match.keyword, expansion: match.expansion, proxy: proxy)
        }
    }

    private func findMatch() -> XP? {
        // Check if any keyword matches the end of our buffer
        let manager = XPManager.shared

        for xp in manager.xps {
            let keyword = xp.keyword
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

    private func performExpansion(keyword: String, expansion: String, proxy: CGEventTapProxy) {
        // Clear the typed buffer
        typedBuffer = ""

        // Delete the keyword by simulating backspaces
        DispatchQueue.main.async {
            self.deleteText(count: keyword.count)

            // Wait a tiny bit for deletions to process
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.typeText(expansion)
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
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    private func checkAccessibilityPermissions() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options)
    }
}
