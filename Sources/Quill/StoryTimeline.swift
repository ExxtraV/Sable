import Foundation
import QuillCore

/// A dramatic beat a heading in the Outline folder can be tagged with, by writing it in parentheses or
/// brackets at the end: "## Chapter 5 — The Break-In (Climax)".
public enum StoryBeat: String, CaseIterable, Sendable {
    case inciting = "Inciting Incident"
    case rising = "Rising Action"
    case midpoint = "Midpoint"
    case climax = "Climax"
    case falling = "Falling Action"
    case resolution = "Resolution"

    /// Its usual place on the dramatic arc, 0 (calm) to 1 (most tense).
    public var height: Double {
        switch self {
        case .inciting: return 0.32
        case .rising: return 0.6
        case .midpoint: return 0.68
        case .climax: return 1.0
        case .falling: return 0.5
        case .resolution: return 0.18
        }
    }

    /// Looks for a trailing `(Beat Name)` or `[Beat Name]` and returns it with the tag removed from the title.
    /// Matching ignores case, spacing, and punctuation, so "(climax)" and "(Climax!)" both work.
    public static func parse(from title: String) -> (beat: StoryBeat?, title: String) {
        guard let match = title.range(of: "[\\(\\[]\\s*([^()\\[\\]]+?)\\s*[\\)\\]]\\s*$", options: .regularExpression) else {
            return (nil, title)
        }
        let inner = String(title[match]).trimmingCharacters(in: CharacterSet(charactersIn: "()[] "))
        let clean = String(title[..<match.lowerBound]).trimmingCharacters(in: .whitespaces)
        func normalized(_ text: String) -> String {
            text.lowercased().filter { $0.isLetter }
        }
        let wanted = normalized(inner)
        guard let found = allCases.first(where: { normalized($0.rawValue) == wanted }) else { return (nil, title) }
        return (found, clean.isEmpty ? title : clean)
    }
}

/// One heading from the Outline folder, placed on the Story Timeline.
public struct StoryBeatPoint: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let level: Int
    public let beat: StoryBeat?
    /// 0 (calm) to 1 (most tense): the beat's own height, or an interpolated point on a classic rising-and-falling arc.
    public let height: Double
    public let url: URL
    public let range: NSRange

    public init(id: String, title: String, level: Int, beat: StoryBeat?, height: Double, url: URL, range: NSRange) {
        self.id = id; self.title = title; self.level = level; self.beat = beat; self.height = height; self.url = url; self.range = range
    }
}

public enum StoryTimeline {
    public static let folderName = "Outline"

    public static func folder(in project: URL) -> URL { project.appendingPathComponent(folderName, isDirectory: true) }

    /// Every Markdown file in the Outline folder, in a stable order.
    public static func files(in project: URL) -> [URL] { ProjectSearch.markdownFiles(in: folder(in: project)) }

    /// Every heading across the Outline folder's files, in file order then position, each placed on the arc.
    /// `texts` supplies the text of a file open with unsaved changes; every other file is read from disk.
    public static func points(project: URL, texts: [URL: String] = [:]) -> [StoryBeatPoint] {
        struct Raw { let url: URL; let heading: ChapterHeading; let beat: StoryBeat?; let title: String }
        var raw: [Raw] = []
        for url in files(in: project) {
            let standard = url.standardizedFileURL
            guard let text = texts[standard] ?? (try? String(contentsOf: url, encoding: .utf8)) else { continue }
            for heading in MarkdownSyntax.headings(in: text) {
                let (beat, clean) = StoryBeat.parse(from: heading.title)
                raw.append(Raw(url: url, heading: heading, beat: beat, title: clean))
            }
        }
        guard !raw.isEmpty else { return [] }
        let count = raw.count
        return raw.enumerated().map { index, item in
            let t = count > 1 ? Double(index) / Double(count - 1) : 0.5
            let height = item.beat?.height ?? defaultArc(t)
            return StoryBeatPoint(id: "\(item.url.path)#\(item.heading.range.location)", title: item.title, level: item.heading.level,
                                  beat: item.beat, height: height, url: item.url, range: item.heading.range)
        }
    }

    /// A classic Freytag shape for a heading with no explicit beat: a steady climb to a peak near the end,
    /// then a shorter fall. `t` is the heading's position from 0 (first) to 1 (last).
    public static func defaultArc(_ t: Double) -> Double {
        let t = min(1, max(0, t))
        let riseEnd = 0.78
        if t <= riseEnd {
            return 0.15 + 0.78 * pow(riseEnd > 0 ? t / riseEnd : 0, 1.5)
        }
        let tail = (t - riseEnd) / (1 - riseEnd)
        return 0.93 - 0.7 * tail
    }
}
