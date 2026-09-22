import Foundation

@main enum WritingHistoryChecks {
    static func main() {
        let defaults = UserDefaults(suiteName: "quill-history-checks-\(getpid())")!
        defaults.removePersistentDomain(forName: "quill-history-checks-\(getpid())")
        let calendar = Calendar(identifier: .gregorian)
        func date(_ y: Int, _ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: y, month: m, day: d))! }

        precondition(WritingHistory.total(defaults: defaults) == 0, "Nothing recorded at first")
        precondition(WritingHistory.add(0, on: date(2026, 3, 1), calendar: calendar, defaults: defaults) == 0, "Zero does nothing")
        precondition(WritingHistory.add(-5, on: date(2026, 3, 1), calendar: calendar, defaults: defaults) == 0, "Negative does nothing")
        _ = WritingHistory.add(120, on: date(2026, 3, 1), calendar: calendar, defaults: defaults)
        let after = WritingHistory.add(80, on: date(2026, 3, 1), calendar: calendar, defaults: defaults)
        precondition(after == 200, "Same day adds up: \(after)")
        _ = WritingHistory.add(300, on: date(2026, 3, 3), calendar: calendar, defaults: defaults)
        precondition(WritingHistory.total(defaults: defaults) == 500, "Total across days")

        let recent = WritingHistory.recent(days: 5, today: date(2026, 3, 3), calendar: calendar, defaults: defaults)
        precondition(recent.count == 5, "Five days requested")
        precondition(recent.map(\.words) == [0, 0, 200, 0, 300], "Missing days are filled with zero, oldest first: \(recent.map(\.words))")
        precondition(recent.last?.date == date(2026, 3, 3), "The last day is today")
        precondition(WritingHistory.recent(days: 1, today: date(2026, 3, 3), calendar: calendar, defaults: defaults).map(\.words) == [300], "One day is just today")
        precondition(WritingHistory.recent(days: 0, today: date(2026, 3, 3), calendar: calendar, defaults: defaults).isEmpty)

        let best = WritingHistory.best(defaults: defaults, calendar: calendar)
        precondition(best?.words == 300 && best?.date == date(2026, 3, 3), "Best day: \(String(describing: best))")
        precondition(WritingHistory.activeDays(defaults: defaults) == 2, "Two days have anything on them")

        // The key format round-trips through a month and year boundary
        _ = WritingHistory.add(10, on: date(2025, 12, 31), calendar: calendar, defaults: defaults)
        _ = WritingHistory.add(10, on: date(2026, 1, 1), calendar: calendar, defaults: defaults)
        let wrap = WritingHistory.recent(days: 3, today: date(2026, 1, 1), calendar: calendar, defaults: defaults)
        precondition(wrap.map(\.words) == [0, 10, 10], "New Year's Eve and Day are both counted, in order: \(wrap.map(\.words))")

        WritingHistory.reset(defaults: defaults)
        precondition(WritingHistory.total(defaults: defaults) == 0 && WritingHistory.best(defaults: defaults) == nil, "Reset clears everything")

        defaults.removePersistentDomain(forName: "quill-history-checks-\(getpid())")
        print("Passed: writing history (adding, same-day totals, filled ranges, best day, active days, boundaries, reset).")
    }
}
