import Foundation

/// Thin typed wrapper over UserDefaults. No observers, no Combine — settings change
/// rarely and every consumer is notified explicitly.
final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    private init() {
        d.register(defaults: [
            K.focusMinutes: 25,
            K.shortBreakMinutes: 5,
            K.longBreakMinutes: 15,
            K.cyclesBeforeLongBreak: 4,
            K.autoStartBreaks: true,
            K.autoStartFocus: false,
            // Off by default — the widget should behave like a normal window most
            // of the time (recede when you click elsewhere) and only force itself
            // to the front for the completion interrupt, not sit glued on top always.
            K.alwaysOnTop: false,
            K.soundEnabled: true,
            K.menuBarCountdown: true,
            K.zoomPercent: 100,
            K.hotkeyEnabled: true,
        ])
    }

    enum K {
        static let focusMinutes = "focusMinutes"
        static let shortBreakMinutes = "shortBreakMinutes"
        static let longBreakMinutes = "longBreakMinutes"
        static let cyclesBeforeLongBreak = "cyclesBeforeLongBreak"
        static let autoStartBreaks = "autoStartBreaks"
        static let autoStartFocus = "autoStartFocus"
        static let alwaysOnTop = "alwaysOnTop"
        static let soundEnabled = "soundEnabled"
        static let menuBarCountdown = "menuBarCountdown"
        static let zoomPercent = "zoomPercent"
        static let hotkeyEnabled = "hotkeyEnabled"
        static let windowOrigin = "windowOrigin"
    }

    var focusMinutes: Int {
        get { clamp(d.integer(forKey: K.focusMinutes), 1, 180) }
        set { d.set(clamp(newValue, 1, 180), forKey: K.focusMinutes) }
    }
    var shortBreakMinutes: Int {
        get { clamp(d.integer(forKey: K.shortBreakMinutes), 1, 60) }
        set { d.set(clamp(newValue, 1, 60), forKey: K.shortBreakMinutes) }
    }
    var longBreakMinutes: Int {
        get { clamp(d.integer(forKey: K.longBreakMinutes), 1, 120) }
        set { d.set(clamp(newValue, 1, 120), forKey: K.longBreakMinutes) }
    }
    var cyclesBeforeLongBreak: Int {
        get { clamp(d.integer(forKey: K.cyclesBeforeLongBreak), 2, 12) }
        set { d.set(clamp(newValue, 2, 12), forKey: K.cyclesBeforeLongBreak) }
    }
    var autoStartBreaks: Bool {
        get { d.bool(forKey: K.autoStartBreaks) } set { d.set(newValue, forKey: K.autoStartBreaks) }
    }
    var autoStartFocus: Bool {
        get { d.bool(forKey: K.autoStartFocus) } set { d.set(newValue, forKey: K.autoStartFocus) }
    }
    var alwaysOnTop: Bool {
        get { d.bool(forKey: K.alwaysOnTop) } set { d.set(newValue, forKey: K.alwaysOnTop) }
    }
    var soundEnabled: Bool {
        get { d.bool(forKey: K.soundEnabled) } set { d.set(newValue, forKey: K.soundEnabled) }
    }
    var menuBarCountdown: Bool {
        get { d.bool(forKey: K.menuBarCountdown) } set { d.set(newValue, forKey: K.menuBarCountdown) }
    }
    var hotkeyEnabled: Bool {
        get { d.bool(forKey: K.hotkeyEnabled) } set { d.set(newValue, forKey: K.hotkeyEnabled) }
    }
    var zoomPercent: Int {
        get { clamp(d.integer(forKey: K.zoomPercent), 10, 100) }
        set { d.set(clamp(newValue, 10, 100), forKey: K.zoomPercent) }
    }
    var windowOrigin: CGPoint? {
        get {
            guard let a = d.array(forKey: K.windowOrigin) as? [Double], a.count == 2 else { return nil }
            return CGPoint(x: a[0], y: a[1])
        }
        set {
            guard let p = newValue else { return }
            d.set([Double(p.x), Double(p.y)], forKey: K.windowOrigin)
        }
    }

    private func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { min(hi, max(lo, v)) }
}
