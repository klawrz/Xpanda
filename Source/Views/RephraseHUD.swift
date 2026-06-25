import AppKit

@MainActor
class RephraseHUD {
    static let shared = RephraseHUD()
    private var panel: NSPanel?

    private init() {}

    func show() {
        panel?.orderOut(nil)

        let width: CGFloat = 162
        let height: CGFloat = 36

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = HUDView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        let anchor = caretPosition() ?? NSEvent.mouseLocation
        var origin = NSPoint(x: anchor.x, y: anchor.y - height - 6)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.main {
            origin.x = min(max(origin.x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - width - 8)
            origin.y = max(origin.y, screen.visibleFrame.minY + 8)
        }
        p.setFrameOrigin(origin)
        p.orderFront(nil)
        self.panel = p
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Caret position via Accessibility API

    private func caretPosition() -> NSPoint? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedRaw: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRaw) == .success,
              let focused = focusedRaw else { return nil }
        let focusedEl = focused as! AXUIElement

        // Try to get the precise caret rect via the selected-text-range path.
        if let point = caretPointFromRange(focusedEl) { return point }

        // Fallback: use the focused element's own frame. This handles web content
        // (Chrome, Electron) where kAXBoundsForRangeParameterizedAttribute returns
        // zero or garbage. Positions the HUD at the top-left of the text field.
        return elementFramePoint(focusedEl)
    }

    private func caretPointFromRange(_ element: AXUIElement) -> NSPoint? {
        var rangeRaw: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRaw) == .success,
              let rangeVal = rangeRaw,
              CFGetTypeID(rangeVal as CFTypeRef) == AXValueGetTypeID() else { return nil }
        let rangeAXVal = rangeVal as! AXValue

        var boundsRaw: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeAXVal,
            &boundsRaw
        ) == .success,
              let boundsVal = boundsRaw,
              CFGetTypeID(boundsVal as CFTypeRef) == AXValueGetTypeID() else { return nil }
        let boundsAXVal = boundsVal as! AXValue

        var rect = CGRect.zero
        guard AXValueGetValue(boundsAXVal, .cgRect, &rect) else { return nil }
        guard rect.width > 0 || rect.height > 0 else { return nil }

        guard NSScreen.main != nil else { return nil }
        let point = NSPoint(x: rect.minX, y: NSScreen.screens[0].frame.height - rect.maxY)
        guard NSScreen.screens.contains(where: { $0.frame.contains(point) }) else { return nil }
        return point
    }

    /// Returns the top-left corner of the focused element's frame (Quartz → AppKit flipped).
    /// Used as a fallback when the precise caret rect is unavailable (e.g. Chrome web views).
    private func elementFramePoint(_ element: AXUIElement) -> NSPoint? {
        var posRaw: AnyObject?
        var sizeRaw: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRaw) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRaw) == .success,
              let posVal = posRaw, let sizeVal = sizeRaw,
              CFGetTypeID(posVal as CFTypeRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeVal as CFTypeRef) == AXValueGetTypeID() else { return nil }

        var pos = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posVal as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &size) else { return nil }

        // kAXPositionAttribute is in Quartz coordinates (top-left origin).
        // Flip Y and nudge to the bottom of the element so the HUD appears just below.
        guard NSScreen.main != nil else { return nil }
        let screenHeight = NSScreen.screens[0].frame.height
        let point = NSPoint(x: pos.x, y: screenHeight - pos.y - size.height)
        guard NSScreen.screens.contains(where: { $0.frame.contains(point) }) else { return nil }
        return point
    }
}

// MARK: - HUD View

private class HUDView: NSView {
    private let iconView = NSImageView()
    private let label    = NSTextField(labelWithString: "")
    private var colorTimer: Timer?
    private var colorOffset: CGFloat = 0

    private static let rainbowHues: [CGFloat] = [0.0, 0.08, 0.15, 0.33, 0.55, 0.70, 0.85]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor

        // Sparkles icon
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        iconView.contentTintColor = .white
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        // Rainbow label
        label.attributedStringValue = rainbowString("Rephrasing...", offset: 0)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        addSubview(label)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -11),
        ])

        // Animate rainbow shift
        colorTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.colorOffset += 0.03
            if self.colorOffset > 1 { self.colorOffset -= 1 }
            self.label.attributedStringValue = self.rainbowString("Rephrasing...", offset: self.colorOffset)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func removeFromSuperview() {
        colorTimer?.invalidate()
        colorTimer = nil
        super.removeFromSuperview()
    }

    private func rainbowString(_ text: String, offset: CGFloat) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let result = NSMutableAttributedString()
        let count = CGFloat(text.count)
        for (i, char) in text.enumerated() {
            let hue = (CGFloat(i) / count + offset).truncatingRemainder(dividingBy: 1.0)
            let color = NSColor(hue: hue, saturation: 0.85, brightness: 1.0, alpha: 1.0)
            result.append(NSAttributedString(string: String(char), attributes: [
                .font: font,
                .foregroundColor: color,
            ]))
        }
        return result
    }
}
