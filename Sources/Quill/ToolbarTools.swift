import SwiftUI

/// One button that can sit on the toolbar.
struct ToolbarTool: Identifiable, Equatable {
    enum Group: String, CaseIterable {
        case writing = "Writing"
        case format = "Text formatting"
        case blocks = "Lists and blocks"
        case aids = "Writing aids"
        case project = "Project and files"
    }
    let id: String
    let title: String
    let icon: String
    let detail: String
    let shortcut: String?
    let group: Group
    /// Buttons that change the text can't be used in Reading Mode.
    var editsText = false
}

/// Which tools are on the toolbar, and in what order. It starts minimal; writers add what they use.
enum ToolbarLayout {
    static let storageKey = "toolbarTools"
    /// What is stored until the writer changes anything: the minimal toolbar.
    static let defaultToken = "default"
    static let minimal = ["desk", "reading", "style", "focus"]
    static let writers = ["desk", "reading", "bold", "italic", "link", "heading", "bullets", "quote", "scenebreak", "style", "focus", "sentences", "revisions"]

    static let all: [ToolbarTool] = [
        ToolbarTool(id: "desk", title: "Writing desk", icon: "sidebar.left", detail: "Show or hide your files and outline.", shortcut: "⌃⌘S", group: .writing),
        ToolbarTool(id: "reading", title: "Reading mode", icon: "play", detail: "Read your work with the Markdown marks hidden.", shortcut: "⇧⌘R", group: .writing),
        ToolbarTool(id: "style", title: "Writing style", icon: "textformat", detail: "Change the font, size, theme, and page width.", shortcut: "⌥⌘,", group: .writing),
        ToolbarTool(id: "focus", title: "Paragraph focus", icon: "scope", detail: "Fade everything except the paragraph you’re writing.", shortcut: "⇧⌘F", group: .writing, editsText: true),

        ToolbarTool(id: "bold", title: "Bold", icon: "bold", detail: "Make the selected words bold.", shortcut: "⌘B", group: .format, editsText: true),
        ToolbarTool(id: "italic", title: "Italic", icon: "italic", detail: "Italicize the selected words.", shortcut: "⌘I", group: .format, editsText: true),
        ToolbarTool(id: "strike", title: "Strikethrough", icon: "strikethrough", detail: "Strike through the selected words.", shortcut: "⇧⌘X", group: .format, editsText: true),
        ToolbarTool(id: "code", title: "Inline code", icon: "chevron.left.forwardslash.chevron.right", detail: "Set the selection as code.", shortcut: "⇧⌘K", group: .format, editsText: true),
        ToolbarTool(id: "link", title: "Link", icon: "link", detail: "Turn the selection into a link. A copied address becomes its destination.", shortcut: "⌘K", group: .format, editsText: true),
        ToolbarTool(id: "heading", title: "Heading", icon: "textformat.size", detail: "Cycle the line through #, ##, ###, and plain.", shortcut: "⇧⌘H", group: .format, editsText: true),

        ToolbarTool(id: "quote", title: "Quote", icon: "text.quote", detail: "Make the lines a block quote.", shortcut: "⌥⌘Q", group: .blocks, editsText: true),
        ToolbarTool(id: "bullets", title: "Bulleted list", icon: "list.bullet", detail: "Make the lines a bulleted list.", shortcut: "⇧⌘8", group: .blocks, editsText: true),
        ToolbarTool(id: "numbers", title: "Numbered list", icon: "list.number", detail: "Make the lines a numbered list.", shortcut: "⇧⌘7", group: .blocks, editsText: true),
        ToolbarTool(id: "tasks", title: "Task list", icon: "checklist", detail: "Make the lines a checklist.", shortcut: "⇧⌘9", group: .blocks, editsText: true),
        ToolbarTool(id: "scenebreak", title: "Scene break", icon: "asterisk", detail: "Add a scene break (* * *) on its own line.", shortcut: "⇧⌘L", group: .blocks, editsText: true),

        ToolbarTool(id: "sentences", title: "Sentence colors", icon: "text.magnifyingglass", detail: "Color nouns, verbs, and other parts of speech.", shortcut: "⌥⌘J", group: .aids),
        ToolbarTool(id: "names", title: "Highlight names", icon: "highlighter", detail: "Make character, place, and world-note names stand out.", shortcut: nil, group: .aids),
        ToolbarTool(id: "prose", title: "Prose suggestions", icon: "text.badge.checkmark", detail: "Strike through words you might cut. Your text never changes.", shortcut: nil, group: .aids),
        ToolbarTool(id: "spelling", title: "Spelling & grammar", icon: "textformat.abc", detail: "Check spelling and grammar as you type.", shortcut: nil, group: .aids, editsText: true),

        ToolbarTool(id: "find", title: "Find & replace in project", icon: "magnifyingglass", detail: "Search every Markdown file, preview, replace, and undo.", shortcut: "⌥⇧⌘F", group: .project),
        ToolbarTool(id: "tag", title: "Tag scene", icon: "tag", detail: "Tag the location and characters in this chapter.", shortcut: "⌃⌘T", group: .project),
        ToolbarTool(id: "export", title: "Export", icon: "square.and.arrow.up", detail: "Export the manuscript, or this document, as PDF, EPUB, Word, or Markdown.", shortcut: nil, group: .project),
        ToolbarTool(id: "snapshot", title: "Save snapshot", icon: "camera", detail: "Keep a copy of your draft as it is now.", shortcut: "⌥⌘S", group: .project),
        ToolbarTool(id: "revisions", title: "Revision history", icon: "clock.arrow.circlepath", detail: "See what changed since a snapshot, and restore.", shortcut: "⌥⌘R", group: .project),
        ToolbarTool(id: "import", title: "Import document", icon: "square.and.arrow.down", detail: "Turn a Word, RTF, or HTML file into Markdown.", shortcut: nil, group: .project),
    ]

    static func tool(_ id: String) -> ToolbarTool? { all.first { $0.id == id } }

    /// The tool ids in a stored setting: the minimal set until changed, unknown ids dropped, repeats ignored.
    static func ids(from stored: String) -> [String] {
        guard stored != defaultToken else { return minimal }
        var seen = Set<String>()
        return stored.split(separator: ",").map(String.init).filter { tool($0) != nil && seen.insert($0).inserted }
    }

    static func tools(from stored: String) -> [ToolbarTool] { ids(from: stored).compactMap(tool) }

    static func encode(_ ids: [String]) -> String { ids.joined(separator: ",") }
}

/// Choose which tools are on the toolbar and put them in order.
struct ToolbarCustomizer: View {
    @Binding var stored: String
    let close: () -> Void

    private var chosen: [String] { ToolbarLayout.ids(from: stored) }
    private func set(_ ids: [String]) { stored = ToolbarLayout.encode(ids) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Customize Toolbar").font(.title3.weight(.semibold))
            Text("It starts small. Add the tools you reach for, and drag to put them in order. The ⋯ button always stays, so you can come back here.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text("Start from").font(.caption).foregroundStyle(.secondary)
                Button("Minimal") { set(ToolbarLayout.minimal) }
                Button("Writer’s set") { set(ToolbarLayout.writers) }
                Button("Everything") { set(ToolbarLayout.all.map(\.id)) }
                Button("Empty") { set([]) }
            }.controlSize(.small)
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("On your toolbar (\(chosen.count))").font(.headline)
                    List {
                        ForEach(chosen, id: \.self) { id in
                            if let tool = ToolbarLayout.tool(id) {
                                HStack(spacing: 10) {
                                    Image(systemName: tool.icon).frame(width: 20).foregroundStyle(.secondary)
                                    Text(tool.title)
                                    Spacer()
                                    Button { set(chosen.filter { $0 != id }) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }
                                        .buttonStyle(.plain).help("Take it off the toolbar")
                                }.padding(.vertical, 1)
                            }
                        }
                        .onMove { from, to in var ids = chosen; ids.move(fromOffsets: from, toOffset: to); set(ids) }
                    }
                    .listStyle(.bordered)
                    .overlay { if chosen.isEmpty { Text("Nothing here yet.\nAdd tools from the right.").multilineTextAlignment(.center).foregroundStyle(.secondary) } }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Available").font(.headline)
                    List {
                        ForEach(ToolbarTool.Group.allCases, id: \.self) { group in
                            let tools = ToolbarLayout.all.filter { $0.group == group && !chosen.contains($0.id) }
                            if !tools.isEmpty {
                                Section(group.rawValue) {
                                    ForEach(tools) { tool in
                                        HStack(spacing: 10) {
                                            Image(systemName: tool.icon).frame(width: 20).foregroundStyle(.secondary)
                                            VStack(alignment: .leading, spacing: 0) {
                                                Text(tool.title)
                                                if let shortcut = tool.shortcut { Text(shortcut).font(.caption2).foregroundStyle(.tertiary) }
                                            }
                                            Spacer()
                                            Button { set(chosen + [tool.id]) } label: { Image(systemName: "plus.circle.fill").foregroundStyle(Color.accentColor) }
                                                .buttonStyle(.plain).help(tool.detail)
                                        }.padding(.vertical, 1)
                                    }
                                }
                            }
                        }
                    }.listStyle(.bordered)
                }
            }
            HStack { Spacer(); Button("Done", action: close).keyboardShortcut(.defaultAction) }
        }.padding(20).frame(width: 640, height: 560)
    }
}
