import AppKit

enum HitRegion { case bigTime, hint, body, outside }
enum EditMode { case none, minutes }

protocol AvocadoViewDelegate: AnyObject {
    func avocadoDidClick(region: HitRegion)
    func avocadoDidDoubleClick(at point: NSPoint)
    func avocadoDidScroll(minutes: Int)
    func avocadoDidPressKey(_ event: NSEvent) -> Bool
    func avocadoDidRightClick(at point: NSPoint)
    func avocadoDidFinishDrag()
    func avocadoDidPinch(scaleDelta: Int)
}

/// Draws the sprite and owns all direct manipulation. The body is a nearest-neighbor
/// pixel-art raster; the readout text is drawn separately with Core Text (Sans,
/// antialiased) straight onto the view, so digits/words are real vector glyphs at
/// any zoom level, never bitmap pixels.
final class AvocadoView: NSView {
    weak var delegate: AvocadoViewDelegate?

    var scale: CGFloat = 1.6 {
        didSet { invalidateIntrinsicContentSize(); needsDisplay = true }
    }

    private var frameState = SpriteFrame()
    private var cachedImage: CGImage?
    private var dragOrigin: NSPoint?
    private var didDrag = false
    private var scrollAccumulator: CGFloat = 0
    private var pinchAccumulator: CGFloat = 0

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: CGFloat(Art.W) * scale, height: CGFloat(Art.H) * scale)
    }
    override var mouseDownCanMoveWindow: Bool { false }

    func apply(_ f: SpriteFrame) {
        guard f != frameState || cachedImage == nil else { return }
        frameState = f
        cachedImage = SpriteRenderer.image(f)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let img = cachedImage, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .none
        ctx.setShouldAntialias(false)
        ctx.draw(img, in: bounds)
        drawText()
    }

    // MARK: - Text (Core Text, not the pixel raster)

    private func artToView(_ x: Double, _ y: Double) -> NSPoint {
        NSPoint(x: x * Double(scale), y: bounds.height - y * Double(scale))
    }

    private func drawText() {
        let f = frameState
        let s = Double(scale)

        var bigString = f.big
        if f.caret == .big, f.caretOn { bigString += "\u{2502}" }
        // "MM:SS" gets the roomy default size; the rarer "H:MM:SS" shrinks to fit
        // the plaque rather than forcing the plaque itself to bulge for it.
        let maxBigWidth = Double(Art.plaqueR) * 1.6 * s
        let bigFont = fittingFont(bigString, maxWidth: maxBigWidth, base: 22 * s, min: 13 * s, weight: .semibold)
        drawCentered(bigString, font: bigFont, color: Palette.ink,
                     center: artToView(Double(Art.plaqueC.x), Double(Art.bigCenterY)))

        let statusFont = NSFont.systemFont(ofSize: 11 * s, weight: .semibold)
        drawCentered(f.status, font: statusFont, color: Palette.inkDim, tracking: 0.6 * s,
                     center: artToView(Double(Art.plaqueC.x), Double(Art.statusCenterY)))
    }

    private func fittingFont(_ text: String, maxWidth: Double, base: Double, min minSize: Double,
                              weight: NSFont.Weight) -> NSFont {
        var size = base
        while size > minSize {
            let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            let w = NSAttributedString(string: text, attributes: [.font: font]).size().width
            if Double(w) <= maxWidth { break }
            size -= 1
        }
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    private func drawCentered(_ text: String, font: NSFont, color: RGBA, tracking: CGFloat = 0, center: NSPoint) {
        guard !text.isEmpty else { return }
        let nsColor = NSColor(srgbRed: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255,
                              blue: CGFloat(color.b) / 255, alpha: CGFloat(color.a) / 255)
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: nsColor]
        if tracking != 0 { attrs[.kern] = tracking }
        let attr = NSAttributedString(string: text, attributes: attrs)
        let size = attr.size()
        let origin = NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        attr.draw(at: origin)
    }

    // MARK: - Coordinates

    private func artPoint(_ p: NSPoint) -> (Int, Int) {
        (Int(p.x / scale), Int((bounds.height - p.y) / scale))
    }

    func region(at viewPoint: NSPoint) -> HitRegion {
        let (x, y) = artPoint(viewPoint)
        guard x >= 0, y >= 0, x < Art.W, y < Art.H else { return .outside }
        guard AvocadoArt.shared.depth(x, y) > 0 else { return .outside }
        if AvocadoArt.shared.inPlaque(x, y) {
            let boundary = (Art.bigCenterY + Art.statusCenterY) / 2
            return y < boundary ? .bigTime : .hint
        }
        return .body
    }

    /// Only opaque sprite pixels are clickable, so clicks pass through the transparent
    /// corners of the window to whatever is behind it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let sp = superview else { return nil }
        let local = convert(point, from: sp)
        let (x, y) = artPoint(local)
        guard x >= 0, y >= 0, x < Art.W, y < Art.H else { return nil }
        return AvocadoArt.shared.depth(x, y) > 0 ? self : nil
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        dragOrigin = NSEvent.mouseLocation
        didDrag = false
        window?.makeFirstResponder(self)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragOrigin, let win = window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - start.x, dy = now.y - start.y
        if !didDrag && (abs(dx) + abs(dy)) < 3 { return }
        didDrag = true
        var origin = win.frame.origin
        origin.x += dx
        origin.y += dy
        win.setFrameOrigin(origin)
        dragOrigin = now
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragOrigin = nil }
        if didDrag {
            delegate?.avocadoDidFinishDrag()
            return
        }
        if event.clickCount >= 2 {
            delegate?.avocadoDidDoubleClick(at: event.locationInWindow)
            return
        }
        let r = region(at: convert(event.locationInWindow, from: nil))
        delegate?.avocadoDidClick(region: r)
    }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.avocadoDidRightClick(at: event.locationInWindow)
    }

    override func otherMouseDown(with event: NSEvent) {
        delegate?.avocadoDidDoubleClick(at: event.locationInWindow)
    }

    // MARK: - Scroll & pinch

    override func scrollWheel(with event: NSEvent) {
        let raw = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 6
        scrollAccumulator += raw
        let threshold: CGFloat = 9
        var steps = 0
        while scrollAccumulator >= threshold { scrollAccumulator -= threshold; steps += 1 }
        while scrollAccumulator <= -threshold { scrollAccumulator += threshold; steps -= 1 }
        guard steps != 0 else { return }
        let unit = event.modifierFlags.contains(.shift) ? 5 : 1
        delegate?.avocadoDidScroll(minutes: steps * unit)
        if event.phase == .ended || event.momentumPhase == .ended { scrollAccumulator = 0 }
    }

    override func magnify(with event: NSEvent) {
        pinchAccumulator += event.magnification
        if pinchAccumulator > 0.2 { pinchAccumulator = 0; delegate?.avocadoDidPinch(scaleDelta: 1) }
        if pinchAccumulator < -0.2 { pinchAccumulator = 0; delegate?.avocadoDidPinch(scaleDelta: -1) }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if delegate?.avocadoDidPressKey(event) == true { return }
        super.keyDown(with: event)
    }
}
