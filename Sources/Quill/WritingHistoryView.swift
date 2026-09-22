import SwiftUI
import Charts

/// A quiet record of how much you've written, day by day. Not a streak — missing a day changes nothing here.
struct WritingRecordSection: View {
    private let span = 30
    @State private var days: [WritingHistory.Day] = []
    @State private var total = 0
    @State private var best: WritingHistory.Day?
    @State private var confirmReset = false

    private var monthWords: Int { days.reduce(0) { $0 + $1.words } }
    private var todayWords: Int { days.last?.words ?? 0 }
    private var hasAnything: Bool { total > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasAnything {
                Chart(days) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Words", day.words))
                        .foregroundStyle(Calendar.current.isDateInToday(day.date) ? Color.accentColor : Color.accentColor.opacity(0.55))
                        .cornerRadius(2)
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .frame(height: 130)
                .padding(.top, 4)

                HStack(spacing: 22) {
                    stat("Today", todayWords)
                    stat("Last \(span) days", monthWords)
                    stat("All time", total)
                }
                if let best, best.words > 0 {
                    Text("Best day: \(best.words.formatted()) words, \(best.date.formatted(date: .abbreviated, time: .omitted)).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Nothing recorded yet. Write a little, and today will show up here.").font(.callout).foregroundStyle(.secondary)
            }
            Text("Counts words you add as you write, never words you remove. Kept only on this Mac.")
                .font(.caption).foregroundStyle(.secondary)
            if hasAnything {
                Button("Clear Writing Record…") { confirmReset = true }.font(.caption)
            }
        }
        .task { reload() }
        .confirmationDialog("Clear your writing record?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Clear It", role: .destructive) { WritingHistory.reset(); reload() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("This can't be undone. Your files and their word counts are untouched — only this record of days and totals is removed.") }
    }

    private func stat(_ label: String, _ words: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(words.formatted()).font(.callout.weight(.medium)).monospacedDigit()
        }
    }

    private func reload() {
        days = WritingHistory.recent(days: span)
        total = WritingHistory.total()
        best = WritingHistory.best()
    }
}
