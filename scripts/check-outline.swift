import Foundation

@main enum OutlineChecks {
    static func main() throws {
        // Beat tag parsing
        precondition(StoryBeat.parse(from: "Chapter 5 (Climax)").beat == .climax, "Basic tag")
        precondition(StoryBeat.parse(from: "Chapter 5 (Climax)").title == "Chapter 5", "Tag stripped")
        precondition(StoryBeat.parse(from: "Chapter 3 [inciting incident]").beat == .inciting, "Brackets, lowercase")
        precondition(StoryBeat.parse(from: "Chapter 3 (Inciting  Incident!)").beat == .inciting, "Extra space and punctuation are ignored")
        precondition(StoryBeat.parse(from: "Chapter 9 (Falling Action)").beat == .falling)
        precondition(StoryBeat.parse(from: "Chapter 9 (Resolution)").beat == .resolution)
        precondition(StoryBeat.parse(from: "Chapter 9 (Rising Action)").beat == .rising)
        precondition(StoryBeat.parse(from: "Chapter 9 (Midpoint)").beat == .midpoint)
        let untagged = StoryBeat.parse(from: "Just a chapter")
        precondition(untagged.beat == nil && untagged.title == "Just a chapter", "No tag, title unchanged")
        let nonsense = StoryBeat.parse(from: "Chapter (a note to myself)")
        precondition(nonsense.beat == nil && nonsense.title == "Chapter (a note to myself)", "An unrecognized parenthetical is left alone")
        precondition(StoryBeat.climax.height == 1, "Climax is the peak")
        precondition(StoryBeat.resolution.height < StoryBeat.inciting.height, "Resolution settles lower than the opening")

        // The default arc: rises to near its peak, then falls, and never leaves 0...1
        precondition(StoryTimeline.defaultArc(0) < StoryTimeline.defaultArc(0.4), "Early on it's still rising")
        precondition(StoryTimeline.defaultArc(0.4) < StoryTimeline.defaultArc(0.78), "It keeps rising toward its peak")
        precondition(StoryTimeline.defaultArc(0.78) > StoryTimeline.defaultArc(1), "…then falls after the peak")
        precondition(StoryTimeline.defaultArc(-1) == StoryTimeline.defaultArc(0) && StoryTimeline.defaultArc(2) == StoryTimeline.defaultArc(1), "Out-of-range values clamp")
        for step in stride(from: 0.0, through: 1.0, by: 0.05) {
            let value = StoryTimeline.defaultArc(step)
            precondition(value >= 0 && value <= 1, "Always within 0...1: \(step) -> \(value)")
        }

        // Reading real files: order, depth, ids, defaults vs. explicit beats
        let fm = FileManager.default
        let project = fm.temporaryDirectory.appendingPathComponent("quill-outline-\(getpid())")
        let outline = project.appendingPathComponent("Outline")
        try fm.createDirectory(at: outline, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: project) }
        try "# Act One\n\n## Chapter 1 — Ordinary World\n\n## Chapter 3 (Inciting Incident)".write(to: outline.appendingPathComponent("1 Act One.md"), atomically: true, encoding: .utf8)
        try "## Chapter 9 (Midpoint)\n\n## Chapter 15 (Climax)\n\n## Chapter 17 (Resolution)".write(to: outline.appendingPathComponent("2 Act Two.md"), atomically: true, encoding: .utf8)
        try "Not an outline file".write(to: project.appendingPathComponent("Notes.txt"), atomically: true, encoding: .utf8)

        let points = StoryTimeline.points(project: project)
        precondition(points.count == 6, "Six headings across both files: \(points.count)")
        precondition(points.map(\.title) == ["Act One", "Chapter 1 — Ordinary World", "Chapter 3", "Chapter 9", "Chapter 15", "Chapter 17"], "File order, then heading order: \(points.map(\.title))")
        precondition(points[0].level == 1 && points[1].level == 2, "Heading levels are kept")
        precondition(Set(points.map(\.id)).count == points.count, "Every point has a unique id")
        precondition(points[2].beat == .inciting && points[2].height == StoryBeat.inciting.height, "An explicit beat uses its own height")
        precondition(points[3].beat == .midpoint && points[4].beat == .climax && points[5].beat == .resolution)
        precondition(points[0].beat == nil && points[0].height == StoryTimeline.defaultArc(0), "The first untagged heading sits at the start of the arc")
        precondition(points.allSatisfy { $0.url.lastPathComponent.hasSuffix(".md") }, "Only Markdown files from Outline are read")

        // Unsaved text is used in place of what's on disk
        let liveURL = outline.appendingPathComponent("1 Act One.md").standardizedFileURL
        let live = StoryTimeline.points(project: project, texts: [liveURL: "# Only This Heading Now"])
        precondition(live.filter { $0.url.standardizedFileURL == liveURL }.map(\.title) == ["Only This Heading Now"], "The open file's unsaved text is read instead of the saved one: \(live.map(\.title))")

        // No Outline folder, or nothing in it
        let bare = fm.temporaryDirectory.appendingPathComponent("quill-outline-bare-\(getpid())")
        try fm.createDirectory(at: bare, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: bare) }
        precondition(StoryTimeline.points(project: bare).isEmpty, "No Outline folder at all")
        try fm.createDirectory(at: StoryTimeline.folder(in: bare), withIntermediateDirectories: true)
        precondition(StoryTimeline.points(project: bare).isEmpty, "An empty Outline folder")

        print("Passed: beat tag parsing, the default dramatic arc, reading headings from the Outline folder (order, depth, ids, unsaved text), and empty projects.")
    }
}
