import SwiftUI
import AppKit

/// The Outline folder's headings laid out along a dramatic arc, so a story's shape is visible at a glance.
/// Untagged headings are spread evenly along a classic rise-and-fall curve; tagged ones (Climax, Midpoint…)
/// sit at their usual place on it. Clicking a point jumps straight to that heading.
struct StoryTimelineWindow: View {
    let project: URL
    let open: (URL, NSRange) -> Void
    let close: () -> Void
    @State private var points: [StoryBeatPoint] = []
    @State private var loading = true

    private let columnWidth: CGFloat = 128
    private let chartHeight: CGFloat = 260

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Story Timeline").font(.title3.weight(.semibold))
                Spacer()
                Button("Done", action: close).keyboardShortcut(.cancelAction)
            }
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if points.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal) {
                    chart.padding(.top, 10).padding(.bottom, 4)
                }
                legend
            }
        }
        .padding(20)
        .frame(width: 780, height: 480)
        .task { await load() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 32)).foregroundStyle(.tertiary)
            Text("Nothing in the Outline folder yet.").foregroundStyle(.secondary)
            Text("Add headings there — chapters, acts, or beats — and they'll show up here. Tag one in parentheses, like “(Climax)”, to pin it to its place on the arc.")
                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center).frame(maxWidth: 420)
            Spacer()
        }.frame(maxWidth: .infinity)
    }

    private var chart: some View {
        let width = max(560, CGFloat(points.count) * columnWidth)
        return ZStack(alignment: .bottomLeading) {
            Path { path in
                for (index, point) in points.enumerated() {
                    let position = self.position(index, point, width: width)
                    if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
                }
            }
            .stroke(Color.accentColor.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                let position = self.position(index, point, width: width)
                VStack(spacing: 6) {
                    Text(point.title).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        .frame(width: columnWidth - 14).multilineTextAlignment(.center)
                    if let beat = point.beat { Text(beat.rawValue).font(.system(size: 9, weight: .semibold)).foregroundStyle(color(for: beat)) }
                }
                .fixedSize()
                .position(x: position.x, y: max(20, position.y - 34))

                Button {} label: {
                    Circle().fill(point.beat != nil ? color(for: point.beat!) : Color.accentColor)
                        .frame(width: point.beat != nil ? 11 : 7, height: point.beat != nil ? 11 : 7)
                        .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .position(position)
                .help(point.beat != nil ? "\(point.title) — \(point.beat!.rawValue)" : point.title)
                .onTapGesture { open(point.url, point.range) }
            }
        }
        .frame(width: width, height: chartHeight, alignment: .bottomLeading)
    }

    private func position(_ index: Int, _ point: StoryBeatPoint, width: CGFloat) -> CGPoint {
        let x = points.count > 1 ? CGFloat(index) / CGFloat(points.count - 1) * (width - columnWidth) + columnWidth / 2 : width / 2
        let y = chartHeight - 16 - CGFloat(point.height) * (chartHeight - 60)
        return CGPoint(x: x, y: y)
    }

    private func color(for beat: StoryBeat) -> Color {
        switch beat {
        case .inciting: return .yellow
        case .rising: return .orange
        case .midpoint: return .teal
        case .climax: return .red
        case .falling: return .purple
        case .resolution: return .green
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            ForEach(StoryBeat.allCases, id: \.self) { beat in
                Label(beat.rawValue, systemImage: "circle.fill").font(.caption2).foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon).imageScale(.small)
                    .foregroundColor(color(for: beat))
            }
            Spacer()
            Text("Click a point to jump to it.").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func load() async {
        let target = project
        let found = await Task.detached(priority: .userInitiated) { StoryTimeline.points(project: target) }.value
        points = found
        loading = false
    }
}
