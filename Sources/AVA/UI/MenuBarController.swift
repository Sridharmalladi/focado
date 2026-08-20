import AppKit

protocol MenuBarDelegate: AnyObject {
    func makeVisible()
    func makeHidden()
}

/// The NSStatusItem: a tiny avocado glyph plus optional live countdown text.
/// Rebuilds its menu lazily (on click) rather than keeping one wired to live state,
/// so idle time costs nothing beyond the icon/text redraw already driven by the timer.
final class MenuBarController {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private weak var timer: TimerEngine?
    private weak var delegate: (AvocadoViewDelegate & MenuBarDelegate)?
    private var lastText = ""
    private var lastIconRunning: Bool?

    init(timer: TimerEngine, delegate: WindowController) {
        self.timer = timer
        self.delegate = delegate
        item.button?.imagePosition = .imageLeft
        item.button?.target = self
        item.button?.action = #selector(clicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        render(running: false, text: "")
    }

    func update(timer: TimerEngine) {
        let running = timer.isRunning
        let text = Settings.shared.menuBarCountdown && (running || timer.state == .paused)
            ? " " + timer.menuBarString : ""
        guard text != lastText || running != lastIconRunning else { return }
        render(running: running, text: text)
    }

    private func render(running: Bool, text: String) {
        lastText = text
        lastIconRunning = running
        let canvas = SpriteRenderer.menuBarIcon(running: running)
        guard let cg = canvas.cgImage() else { return }
        let img = NSImage(cgImage: cg, size: NSSize(width: 16, height: 16))
        img.isTemplate = false
        item.button?.image = img
        item.button?.title = text
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            popMenu()
            return
        }
        if event.modifierFlags.contains(.control) {
            popMenu()
            return
        }
        delegate?.makeVisible()
    }

    private func popMenu() {
        guard let timer = timer else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: timer.isRunning ? "Pause" : "Start", action: #selector(toggle), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Reset", action: #selector(reset), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Show AVA", action: #selector(show), keyEquivalent: "").target = self
        menu.addItem(.separator())

        let countdownItem = menu.addItem(
            withTitle: "Show Countdown in Menu Bar", action: #selector(toggleCountdown), keyEquivalent: "")
        countdownItem.target = self
        countdownItem.state = Settings.shared.menuBarCountdown ? .on : .off

        let topItem = menu.addItem(withTitle: "Always on Top", action: #selector(toggleOnTop), keyEquivalent: "")
        topItem.target = self
        topItem.state = Settings.shared.alwaysOnTop ? .on : .off

        menu.addItem(.separator())
        let stats = Stats.shared
        menu.addItem(withTitle: "Today: \(stats.todayCount) sessions · \(stats.todayMinutes) min", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Streak: \(stats.streakDays) day\(stats.streakDays == 1 ? "" : "s")", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit AVA", action: #selector(quit), keyEquivalent: "q").target = self

        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func toggle() { timer?.toggle() }
    @objc private func reset() { timer?.reset() }
    @objc private func show() { delegate?.makeVisible() }
    @objc private func toggleCountdown() {
        Settings.shared.menuBarCountdown.toggle()
        if let t = timer { update(timer: t) }
    }
    @objc private func toggleOnTop() { Settings.shared.alwaysOnTop.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
}
