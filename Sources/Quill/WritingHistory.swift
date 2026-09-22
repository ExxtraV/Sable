import Foundation

/// A day-by-day record of words written, kept on this Mac. It is a log, not a streak: missing a day breaks
/// nothing, and there's nothing to lose by skipping one. Only forward progress counts — deleting words never
/// takes anything back off a day's total, the same spirit as the session word count already shown while you write.
enum WritingHistory {
    static let storageKey = "writingHistoryDaily"

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func date(from key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func load(defaults: UserDefaults = .standard) -> [String: Int] {
        (defaults.dictionary(forKey: storageKey) as? [String: Int]) ?? [:]
    }

    static func save(_ values: [String: Int], defaults: UserDefaults = .standard) {
        defaults.set(values, forKey: storageKey)
    }

    /// Adds words to a day's total. Zero or negative amounts do nothing, since only progress is recorded.
    @discardableResult
    static func add(_ words: Int, on date: Date = Date(), calendar: Calendar = .current, defaults: UserDefaults = .standard) -> Int {
        guard words > 0 else { return load(defaults: defaults)[dayKey(date, calendar: calendar)] ?? 0 }
        var values = load(defaults: defaults)
        let key = dayKey(date, calendar: calendar)
        values[key, default: 0] += words
        save(values, defaults: defaults)
        return values[key] ?? 0
    }

    struct Day: Identifiable, Equatable {
        var id: Date { date }
        let date: Date
        let words: Int
    }

    /// The last `days` calendar days ending on `today`, oldest first, with every missing day filled in as 0
    /// so a chart never has a gap.
    static func recent(days: Int, today: Date = Date(), calendar: Calendar = .current, defaults: UserDefaults = .standard) -> [Day] {
        guard days > 0 else { return [] }
        let values = load(defaults: defaults)
        let start = calendar.startOfDay(for: today)
        return (0..<days).reversed().compactMap { offset -> Day? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: start) else { return nil }
            return Day(date: date, words: values[dayKey(date, calendar: calendar)] ?? 0)
        }
    }

    static func total(defaults: UserDefaults = .standard) -> Int { load(defaults: defaults).values.reduce(0, +) }

    /// The single best day on record, if any words have been written.
    static func best(defaults: UserDefaults = .standard, calendar: Calendar = .current) -> Day? {
        load(defaults: defaults).compactMap { key, words -> Day? in
            date(from: key, calendar: calendar).map { Day(date: $0, words: words) }
        }.max { $0.words < $1.words }
    }

    /// How many distinct days have anything recorded, for an honest "average on days you wrote" figure.
    static func activeDays(defaults: UserDefaults = .standard) -> Int {
        load(defaults: defaults).filter { $0.value > 0 }.count
    }

    /// Clears the whole record. There's no undo, so callers confirm with the writer first.
    static func reset(defaults: UserDefaults = .standard) { defaults.removeObject(forKey: storageKey) }
}
