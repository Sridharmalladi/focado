import AppKit
import Foundation

enum Phase {
    case focus, shortBreak, longBreak

    var isBreak: Bool { self != .focus }
    var label: String {
        switch self {
        case .focus: return "FOCUS"
        case .shortBreak: return "BREAK"
        case .longBreak: return "LONG BREAK"
        }
    }
    var shortLabel: String {
        switch self {
        case .focus: return "FOCUS"
        case .shortBreak: return "BREAK"
        case .longBreak: return "LONG"
        }
    }
}

enum RunState { case idle, running, paused, finished }

/// Deadline-based clock.
///
/// The engine never accumulates ticks; it stores an absolute `endDate` and derives the
/// remaining time from the wall clock. That makes it immune to timer coalescing, App Nap,
/// and sleep/wake — a display tick that arrives late or never simply means one skipped
/// repaint, not a wrong countdown.
final class TimerEngine {
    private(set) var phase: Phase = .focus
    private(set) var state: RunState = .idle
    private(set) var completedFocus = 0

    /// Planned length of the current session, seconds.
    private(set) var duration: TimeInterval
    private var endDate: Date?
    private var pausedRemaining: TimeInterval = 0

    var onTick: (() -> Void)?
    var onComplete: ((Phase) -> Void)?
    var onStateChange: (() -> Void)?

    private var fireTimer: Timer?
    private var displayTimer: Timer?
    private var activity: NSObjectProtocol?
    /// Display ticks are only produced when something is actually on screen.
    var displayActive = false { didSet { syncDisplayTimer() } }

    init() {
        duration = TimeInterval(Settings.shared.focusMinutes * 60)
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.resync() }
    }

    // MARK: - Derived values

    var remaining: TimeInterval {
        switch state {
        case .running:
            guard let end = endDate else { return duration }
            return max(0, end.timeIntervalSinceNow)
        case .paused:
            return pausedRemaining
        case .finished:
            return 0
        case .idle:
            return duration
        }
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / duration))
    }

    var isRunning: Bool { state == .running }

    /// H:MM:SS while there's an hour or more left; once it drops under an hour the
    /// hour placeholder disappears entirely and it reads as a plain M:SS countdown.
    var displayString: String {
        let totalSeconds = state == .idle ? Int(round(duration)) : Int(ceil(remaining))
        let h = totalSeconds / 3600, m = (totalSeconds % 3600) / 60, s = totalSeconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    var menuBarString: String { displayString }

    var plannedMinutes: Int { Int(round(duration / 60)) }

    // MARK: - Transport

    func start() {
        guard state != .running else { return }
        let secs = state == .paused ? pausedRemaining : duration
        endDate = Date().addingTimeInterval(secs)
        state = .running
        armFireTimer()
        beginActivity()
        syncDisplayTimer()
        onStateChange?()
    }

    func pause() {
        guard state == .running else { return }
        pausedRemaining = remaining
        state = .paused
        fireTimer?.invalidate(); fireTimer = nil
        endActivity()
        syncDisplayTimer()
        onStateChange?()
    }

    func toggle() {
        switch state {
        case .running: pause()
        case .idle, .paused: start()
        case .finished: advance(auto: false)
        }
    }

    /// Back to the start of the current phase.
    func reset() {
        fireTimer?.invalidate(); fireTimer = nil
        endDate = nil
        pausedRemaining = 0
        state = .idle
        duration = TimeInterval(defaultMinutes(for: phase) * 60)
        endActivity()
        syncDisplayTimer()
        onStateChange?()
    }

    /// Abandon the current session and move to the next phase without crediting it.
    func skip() {
        fireTimer?.invalidate(); fireTimer = nil
        endActivity()
        advance(auto: false, credit: false)
    }

    /// Scroll / typing adjustment. Idle changes the planned length; running stretches
    /// or shortens the live deadline.
    /// Idle only, on purpose — once a session is running or paused, an accidental
    /// scroll must never silently change what you're counting down. The only way
    /// back to an adjustable state is pause then reset.
    func adjust(minutes delta: Int) {
        guard state == .idle else { return }
        setMinutes(plannedMinutes + delta)
    }

    func setMinutes(_ m: Int) {
        let clamped = min(180, max(1, m))
        duration = TimeInterval(clamped * 60)
        if state == .idle {
            if phase == .focus { Settings.shared.focusMinutes = clamped }
            else if phase == .shortBreak { Settings.shared.shortBreakMinutes = clamped }
            else { Settings.shared.longBreakMinutes = clamped }
        }
        onTick?()
        onStateChange?()
    }

    // MARK: - Completion

    private func complete() {
        fireTimer?.invalidate(); fireTimer = nil
        endActivity()
        let finished = phase
        state = .finished
        if finished == .focus {
            completedFocus += 1
            Stats.shared.record(minutes: plannedMinutes)
        }
        syncDisplayTimer()
        onComplete?(finished)
        onStateChange?()
    }

    /// Move to the next phase in the cycle.
    func advance(auto: Bool, credit: Bool = true) {
        let previous = phase
        if previous == .focus {
            if credit && state != .finished { completedFocus += 1 }
            let n = Settings.shared.cyclesBeforeLongBreak
            phase = (completedFocus % n == 0 && completedFocus > 0) ? .longBreak : .shortBreak
        } else {
            phase = .focus
        }
        duration = TimeInterval(defaultMinutes(for: phase) * 60)
        endDate = nil
        pausedRemaining = 0
        state = .idle

        let shouldAutoStart = phase.isBreak ? Settings.shared.autoStartBreaks : Settings.shared.autoStartFocus
        if auto && shouldAutoStart {
            start()
        } else {
            syncDisplayTimer()
            onStateChange?()
        }
    }

    private func defaultMinutes(for p: Phase) -> Int {
        switch p {
        case .focus: return Settings.shared.focusMinutes
        case .shortBreak: return Settings.shared.shortBreakMinutes
        case .longBreak: return Settings.shared.longBreakMinutes
        }
    }

    // MARK: - Timers

    private func armFireTimer() {
        fireTimer?.invalidate()
        guard let end = endDate else { return }
        let t = Timer(fireAt: end, interval: 0, target: self,
                      selector: #selector(fireTimerHit), userInfo: nil, repeats: false)
        t.tolerance = 0
        RunLoop.main.add(t, forMode: .common)
        fireTimer = t
    }

    @objc private func fireTimerHit() {
        // Guard against an early fire after a clock change.
        if remaining > 0.75 { armFireTimer(); return }
        complete()
    }

    /// The readout shows seconds now, so it needs a real 1Hz tick while visible.
    private func syncDisplayTimer() {
        let wanted = state == .running && (displayActive || Settings.shared.menuBarCountdown)
        if wanted, displayTimer == nil {
            let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.onTick?() }
            t.tolerance = 0.1
            RunLoop.main.add(t, forMode: .common)
            displayTimer = t
        } else if !wanted, displayTimer != nil {
            displayTimer?.invalidate()
            displayTimer = nil
        }
    }

    /// After sleep, the fire timer may have been suspended past its deadline.
    private func resync() {
        guard state == .running else { return }
        if remaining <= 0 { complete() } else { armFireTimer(); onTick?() }
    }

    // MARK: - Power

    /// Keep App Nap from suspending the process while a session is live, but never
    /// block idle sleep — the deadline survives sleep on its own.
    private func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Focado pomodoro session running")
    }

    private func endActivity() {
        if let a = activity { ProcessInfo.processInfo.endActivity(a) }
        activity = nil
    }
}
