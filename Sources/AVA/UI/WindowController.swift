import AppKit
import Foundation

final class AVAWindow: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        self.level = .normal
        // Normal, non-intrusive by default — behaves like any other window (recedes
        // behind whatever's focused, stays off a full-screen app's Space entirely).
        // canJoinAllSpaces/fullScreenAuxiliary only get switched on for the moment
        // of the completion interrupt (see WindowController.bringToFrontForInterrupt),
        // never permanently — that was the bug: having it on all the time meant this
        // window would intrude into a full-screen app's Space even when not ringing.
        self.collectionBehavior = [.transient, .ignoresCycle]
        self.backgroundColor = NSColor.clear
        self.isOpaque = false
        self.isMovableByWindowBackground = false
        self.acceptsMouseMovedEvents = false
        self.hidesOnDeactivate = false
        self.canBecomeVisibleWithoutLogin = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class WindowController: NSWindowController {
    /// Device pixels per art pixel at 100% zoom. Deliberately smaller than a literal
    /// 1:1 art-grid render — at 100% the widget should already read as compact on a
    /// laptop screen; the 50/30/10% presets shrink further from there.
    static let baseScale: CGFloat = 1.6

    static func scaleFor(percent: Int) -> CGFloat { baseScale * CGFloat(percent) / 100 }

    let timer = TimerEngine()
    let avocadoView: AvocadoView
    private var menuBarController: MenuBarController?
    private var editingMode = EditMode.none
    private var editingBuffer = ""
    private var caretBlink: Timer?
    private var caretPhase = true
    private var grainTimer: Timer?
    private var motionPhase: Double = 0
    private var bellTimer: Timer?
    private var bellElapsed: TimeInterval = 0
    private let bellInterval: TimeInterval = 0.35
    private let bellDuration: TimeInterval = 30

    init() {
        let initialScale = WindowController.scaleFor(percent: Settings.shared.zoomPercent)
        let frame = NSRect(x: 100, y: 200,
                            width: CGFloat(Art.W) * initialScale, height: CGFloat(Art.H) * initialScale)
        let window = AVAWindow(frame: frame)
        window.delegate = nil

        let view = AvocadoView()
        view.scale = initialScale
        avocadoView = view
        window.contentView = view

        super.init(window: window)
        view.delegate = self

        if let origin = Settings.shared.windowOrigin {
            window.setFrameOrigin(origin)
        } else {
            window.center()
        }

        window.level = Settings.shared.alwaysOnTop ? .floating : .normal

        timer.onStateChange = { [weak self] in self?.updateDisplay() }
        timer.onTick = { [weak self] in self?.updateDisplay() }
        timer.onComplete = { [weak self] phase in
            self?.handleComplete(phase)
        }

        menuBarController = MenuBarController(timer: timer, delegate: self)

        // Event-driven visibility, no polling thread: the panel tells us exactly
        // when it stops being occluded (minimized, covered, another Space, closed).
        NotificationCenter.default.addObserver(
            self, selector: #selector(occlusionChanged),
            name: NSWindow.didChangeOcclusionStateNotification, object: window)
        timer.displayActive = window.isVisible

        // Caret blink only runs while something is actually being edited.
        updateDisplay()
    }

    @objc private func occlusionChanged() {
        timer.displayActive = window?.occlusionState.contains(.visible) ?? false
        updateDisplay()
    }

    /// The orbiting glint is the "you can see it's moving" cue — it only costs
    /// anything while a session is actually running AND the window is on screen,
    /// same discipline as the countdown display timer.
    private func syncGrainTimer() {
        let wanted = timer.isRunning && (window?.occlusionState.contains(.visible) ?? false)
        if wanted, grainTimer == nil {
            let t = Timer(timeInterval: 0.14, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.motionPhase = (self.motionPhase + 0.05).truncatingRemainder(dividingBy: 1.0)
                self.updateDisplay()
            }
            t.tolerance = 0.05
            RunLoop.main.add(t, forMode: .common)
            grainTimer = t
        } else if !wanted, grainTimer != nil {
            grainTimer?.invalidate()
            grainTimer = nil
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func makeVisible() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func makeHidden() {
        window?.orderOut(nil)
    }

    // MARK: - Display

    private func updateDisplay() {
        syncGrainTimer()
        if timer.state != .finished { stopBell() }

        var f = SpriteFrame()
        f.mood = mood()
        f.big = editingMode == .minutes ? (editingBuffer.isEmpty ? "0" : editingBuffer) : timer.displayString
        f.progress = timer.progress
        f.accent = timer.phase.isBreak ? Palette.accentBreak : Palette.accentFocus
        f.accentLit = timer.phase.isBreak ? Palette.accentBreakLit : Palette.accentFocusLit
        f.status = statusText()
        f.caret = editingMode == .minutes ? .big : .none
        f.caretOn = caretPhase
        f.showMotion = grainTimer != nil
        f.motionPhase = motionPhase

        avocadoView.apply(f)
        menuBarController?.update(timer: timer)
    }

    private func mood() -> Mood {
        switch timer.state {
        case .finished: return .happy
        case .running:
            if timer.phase.isBreak { return .resting }
            return .focused
        case .paused: return .paused
        case .idle: return .idle
        }
    }

    /// Always names the action a click on the pit performs right now — no FOCUS
    /// label, no task field, just start → pause → resume in sequence. Reset stays
    /// in the menu rather than fighting for space here.
    private func statusText() -> String {
        switch timer.state {
        case .idle:
            return "\u{21B5} START"
        case .running:
            return "PAUSE"
        case .paused:
            return "RESUME"
        case .finished:
            return "✓ DONE"
        }
    }

    // MARK: - Completion

    /// The whole point of the app: interrupt, wherever you are. Forces the window
    /// to the front regardless of the Always-on-Top setting, moves it to whatever
    /// screen you're currently looking at, then rings — each ring vibrates the
    /// window too — until acknowledged.
    private func handleComplete(_ phase: Phase) {
        bringToFrontForInterrupt()
        startBell()
        updateDisplay()
    }

    /// Only joins all Spaces / becomes full-screen-auxiliary for this moment — the
    /// normal, non-intrusive behavior resumes as soon as it's acknowledged (see the
    /// revert in updateDisplay). Permanently-on was the bug: it made the widget
    /// intrude into a full-screen app's Space even when nothing was ringing.
    private func bringToFrontForInterrupt() {
        guard let win = window else { return }
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        if let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main {
            let vf = targetScreen.visibleFrame
            let size = win.frame.size
            let origin = NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2)
            win.setFrameOrigin(origin)
        }
        makeVisible()
        savePosition()
    }

    /// A quick decaying wiggle — fires alongside every ring, not just the first one.
    private func vibrate() {
        guard let win = window else { return }
        let original = win.frame.origin
        let offsets: [CGFloat] = [5, -5, 3, -3, 0]
        var i = 0
        let t = Timer(timeInterval: 0.025, repeats: true) { [weak win] timer in
            guard let win else { timer.invalidate(); return }
            guard i < offsets.count else { timer.invalidate(); return }
            win.setFrameOrigin(NSPoint(x: original.x + offsets[i], y: original.y))
            i += 1
        }
        RunLoop.main.add(t, forMode: .common)
    }

    /// Rings on a loop for up to 30 seconds, or until the user acknowledges the
    /// finish (any click that moves the timer out of .finished stops it via
    /// updateDisplay's check below) — whichever comes first. Every ring vibrates
    /// the window in sync.
    private func startBell() {
        bellTimer?.invalidate()
        bellElapsed = 0
        ring()
        let t = Timer(timeInterval: bellInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.bellElapsed += self.bellInterval
            guard self.timer.state == .finished, self.bellElapsed < self.bellDuration else {
                self.stopBell()
                return
            }
            self.ring()
        }
        RunLoop.main.add(t, forMode: .common)
        bellTimer = t
    }

    private func ring() {
        // "Tink" is short and percussive — it stays a crisp, distinct ding at a
        // fast repeat rate. "Glass" has a long resonant decay that would smear
        // together into one blur at this cadence instead of reading as dings.
        if Settings.shared.soundEnabled { NSSound(named: "Tink")?.play() }
        vibrate()
    }

    /// The single place ringing actually ends — whether by the 30s timeout or by
    /// the user acknowledging it — so it's the single place the forced-to-front
    /// level/behavior reverts too. Tying the revert to timer-state change instead
    /// (as before) was the bug: clicking another app never changes timer state, so
    /// a floating window would stay glued on top indefinitely once the bell timed
    /// out with nobody having touched the pit.
    private func stopBell() {
        guard bellTimer != nil else { return }
        bellTimer?.invalidate()
        bellTimer = nil
        window?.level = Settings.shared.alwaysOnTop ? .floating : .normal
        window?.collectionBehavior = [.transient, .ignoresCycle]
    }

    // MARK: - Events

    func savePosition() {
        if let origin = window?.frame.origin {
            Settings.shared.windowOrigin = origin
        }
    }
}

extension WindowController: MenuBarDelegate {}

extension WindowController: AvocadoViewDelegate {
    func avocadoDidClick(region: HitRegion) {
        switch region {
        case .hint:
            timer.toggle()
            updateDisplay()
        case .bigTime:
            if editingMode == .minutes { stopEditing() } else { startEditing(.minutes) }
        default:
            break
        }
    }

    /// Double click is the "show me everything" gesture the app was designed
    /// around: start/pause/reset, phase picker, always-on-top, zoom, hide, quit.
    func avocadoDidDoubleClick(at point: NSPoint) {
        avocadoDidRightClick(at: point)
    }

    func avocadoDidScroll(minutes: Int) {
        timer.adjust(minutes: minutes)
    }

    func avocadoDidPressKey(_ event: NSEvent) -> Bool {
        guard editingMode != .none else { return false }
        guard let chars = event.characters else { return false }
        let ch = chars.first ?? " "
        switch ch {
        case "\u{1B}":
            stopEditing()
            return true
        case "\r", "\n":
            stopEditing()
            return true
        case "\u{7F}":
            if !editingBuffer.isEmpty {
                editingBuffer.removeLast()
                updateDisplay()
            }
            return true
        default:
            if ch.isNumber {
                editingBuffer.append(ch)
                updateDisplay()
                return true
            }
        }
        return false
    }

    func avocadoDidRightClick(at point: NSPoint) {
        guard let menu = buildContextMenu(), let view = window?.contentView,
              let event = NSEvent.mouseEvent(
                with: .rightMouseDown, location: point, modifierFlags: [],
                timestamp: Date().timeIntervalSince1970, windowNumber: window?.windowNumber ?? 0,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1.0)
        else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    func avocadoDidFinishDrag() {
        savePosition()
    }

    func avocadoDidPinch(scaleDelta: Int) {
        setZoom(percent: Settings.shared.zoomPercent + scaleDelta * 5)
    }

    /// Shared by the pinch gesture and the Zoom menu presets. Resizes around the
    /// window's current center so zooming feels anchored to where the widget is,
    /// not to its bottom-left corner.
    func setZoom(percent: Int) {
        let clamped = min(100, max(10, percent))
        let newScale = WindowController.scaleFor(percent: clamped)
        avocadoView.scale = newScale
        Settings.shared.zoomPercent = clamped
        guard let win = window else { return }
        let oldFrame = win.frame
        let center = NSPoint(x: oldFrame.midX, y: oldFrame.midY)
        let size = NSSize(width: CGFloat(Art.W) * newScale, height: CGFloat(Art.H) * newScale)
        let origin = NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        win.setFrame(NSRect(origin: origin, size: size), display: true)
        savePosition()
    }

    private func startEditing(_ mode: EditMode) {
        editingMode = mode
        editingBuffer = "\(timer.plannedMinutes)"
        caretPhase = true
        startCaretBlink()
        updateDisplay()
    }

    private func stopEditing() {
        if editingMode == .minutes, let m = Int(editingBuffer) {
            timer.setMinutes(m)
        }
        editingMode = .none
        stopCaretBlink()
        updateDisplay()
    }

    private func buildContextMenu() -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Start", action: #selector(menuStart), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Pause", action: #selector(menuPause), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Reset", action: #selector(menuReset), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let onTopItem = NSMenuItem(title: "Always on Top", action: #selector(menuToggleOnTop), keyEquivalent: "")
        onTopItem.state = Settings.shared.alwaysOnTop ? .on : .off
        menu.addItem(onTopItem)
        let zoomItem = NSMenuItem(title: "Zoom", action: nil, keyEquivalent: "")
        zoomItem.submenu = buildZoomMenu()
        menu.addItem(zoomItem)
        menu.addItem(NSMenuItem(title: "Hide", action: #selector(menuHide), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Focado", action: #selector(menuQuit), keyEquivalent: "q"))
        return menu
    }

    @objc private func menuHide() { makeHidden() }

    private func buildZoomMenu() -> NSMenu {
        let sub = NSMenu()
        let current = Settings.shared.zoomPercent
        for percent in [100, 50, 30, 10] {
            let item = NSMenuItem(title: "\(percent)%", action: #selector(menuZoom(_:)), keyEquivalent: "")
            item.tag = percent
            item.state = (percent == current) ? .on : .off
            sub.addItem(item)
        }
        return sub
    }

    @objc private func menuZoom(_ sender: NSMenuItem) {
        setZoom(percent: sender.tag)
    }

    @objc private func menuStart() { timer.start() }
    @objc private func menuPause() { timer.pause() }
    @objc private func menuReset() { timer.reset() }
    @objc private func menuToggleOnTop() {
        let newValue = !Settings.shared.alwaysOnTop
        Settings.shared.alwaysOnTop = newValue
        window?.level = newValue ? .floating : .normal
    }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: - Caret

    private func startCaretBlink() {
        guard caretBlink == nil else { return }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.caretPhase.toggle()
            self?.updateDisplay()
        }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        caretBlink = t
    }

    private func stopCaretBlink() {
        caretBlink?.invalidate()
        caretBlink = nil
    }
}
