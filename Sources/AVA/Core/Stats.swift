import Foundation

struct CompletedSession: Codable {
    let end: Date
    let minutes: Int
}

/// Rolling log of finished focus sessions, capped so the defaults plist stays tiny.
final class Stats {
    static let shared = Stats()
    private let key = "sessionLog"
    private let cap = 300
    private(set) var log: [CompletedSession]

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([CompletedSession].self, from: data) {
            log = decoded
        } else {
            log = []
        }
    }

    func record(minutes: Int) {
        log.append(CompletedSession(end: Date(), minutes: minutes))
        if log.count > cap { log.removeFirst(log.count - cap) }
        persist()
    }

    func clear() {
        log.removeAll()
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(log) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    var todayCount: Int { today.count }
    var todayMinutes: Int { today.reduce(0) { $0 + $1.minutes } }

    private var today: [CompletedSession] {
        let start = Calendar.current.startOfDay(for: Date())
        return log.filter { $0.end >= start }
    }

    var streakDays: Int {
        let cal = Calendar.current
        var days = Set<Date>()
        for s in log { days.insert(cal.startOfDay(for: s.end)) }
        var n = 0
        var cursor = cal.startOfDay(for: Date())
        if !days.contains(cursor) {
            guard let y = cal.date(byAdding: .day, value: -1, to: cursor), days.contains(y) else { return 0 }
            cursor = y
        }
        while days.contains(cursor) {
            n += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return n
    }
}
