import Foundation

// Fiction Projects are ordinary folders of ordinary files. The only thing that makes a folder a
// project is one small hidden file, `.sable-project.json`; deleting it turns the folder back into a
// regular folder and touches nothing else. Cards read plain YAML front matter at the top of a
// Markdown file, so any other editor can open, read, and edit every file in a project.

enum CardKind: String, CaseIterable, Codable, Sendable {
    case character, location, lore

    var title: String {
        switch self { case .character: return "Character"; case .location: return "Location"; case .lore: return "World note" }
    }
    var folderName: String {
        switch self { case .character: return "Characters"; case .location: return "Locations"; case .lore: return "World" }
    }
    /// How this kind is labelled in pickers and settings.
    var pickerTitle: String {
        switch self { case .location: return "Locations"; case .character: return "Characters"; case .lore: return "World notes" }
    }
    var symbol: String {
        switch self { case .character: return "person.crop.rectangle"; case .location: return "map"; case .lore: return "book.closed" }
    }
    /// The front-matter key that best describes an item of this kind ("role", "region", …).
    var subtitleKeys: [String] {
        switch self { case .character: return ["role", "occupation"]; case .location: return ["region", "kind"]; case .lore: return ["category", "kind"] }
    }

    /// Accepts the words people naturally type after `type:`.
    static func named(_ word: String) -> CardKind? {
        switch word.trimmingCharacters(in: .whitespaces).lowercased() {
        case "character", "characters", "person", "people": return .character
        case "location", "locations", "place", "places", "setting": return .location
        case "lore", "world", "background", "world note": return .lore
        default: return nil
        }
    }
}

/// Things a writer creates inside a project from the desk's + menu.
enum NewProjectItem: CaseIterable, Sendable {
    case chapter, character, location, lore
    var title: String {
        switch self { case .chapter: return "New Chapter"; case .character: return "New Character"; case .location: return "New Location"; case .lore: return "New World Note" }
    }
    var folderName: String {
        switch self { case .chapter: return FictionProject.manuscriptFolder; case .character: return "Characters"; case .location: return "Locations"; case .lore: return "World" }
    }
    var cardKind: CardKind? {
        switch self { case .chapter: return nil; case .character: return .character; case .location: return .location; case .lore: return .lore }
    }
    /// Tooltip for the "+" on a folder of this kind.
    var addHelp: String {
        switch self { case .chapter: return "Add the next chapter"; case .character: return "Add a character"; case .location: return "Add a location"; case .lore: return "Add a world note" }
    }
    var prompt: String {
        switch self { case .chapter: return "Chapter name"; case .character: return "Character name"; case .location: return "Location name"; case .lore: return "Title" }
    }
    func template(named name: String) -> String {
        switch self {
        case .chapter: return "# \(name)\n\n"
        case .character:
            return "---\ntype: character\nrole:\nimage:\ntags:\n---\n\n# \(name)\n\n## Appearance\n\n## Personality\n\n## Backstory\n\n## Relationships\n\n"
        case .location:
            return "---\ntype: location\nregion:\nimage:\ntags:\n---\n\n# \(name)\n\n## Description\n\n## History\n\n## Who is here\n\n"
        case .lore:
            return "---\ntype: lore\ncategory:\nimage:\ntags:\n---\n\n# \(name)\n\n"
        }
    }
}

enum FictionProjectError: LocalizedError {
    case alreadyProject, notProject, badImage(String)
    var errorDescription: String? {
        switch self {
        case .alreadyProject: return "This folder is already a Fiction Project."
        case .notProject: return "This folder isn’t a Fiction Project."
        case let .badImage(name): return "“\(name)” isn’t an image Sable can use. Try a PNG, JPEG, HEIC, GIF, or TIFF."
        }
    }
}

/// The "Start Here" note every new project begins with: how the project works and how to bend it to your needs.
enum ProjectGuide {
    static let fileName = "Start Here.md"

    static func text(projectName: String) -> String {
        """
        # Start here: \(projectName)

        Welcome to your Fiction Project. This note explains how it works and how to make it your own. It's an ordinary file, so delete it whenever you like. You can bring it back any time from the project's ⋯ menu → **Start Here Guide**.

        ## What's in this project

        - **Manuscript** holds your chapters, one file each. It's pinned to the top and colored red because it's where you'll spend most of your time.
        - **Characters**, **Locations**, and **World** hold the people, places, and ideas of your story. Each file can show up as a floating card while you write.
        - **Outline** is for planning: headings become chapters or beats you can see laid out on the **Story Timeline** (File menu). See below.
        - **Notes** is for anything else: research, scraps, loose ideas.
        - **Images** holds the pictures you attach to cards.

        There's also a **Concept.md** file at the top level, pre-filled with a few questions (logline, themes, your own pitch) to help you think the story through before you draft. Delete what you don't need; it's scratch paper.

        Everything here is plain Markdown and ordinary folders. Any other editor can open it, and your cloud service syncs it like any other folder.

        ## Planning with Outline and the Story Timeline

        The **Outline** folder holds plain Markdown files of your own headings — acts, chapters, beats, whatever fits how you plan. Tag any heading with a beat in parentheses and it's placed on the **Story Timeline** (File menu → Story Timeline…, or the toolbar): `(Inciting Incident)`, `(Rising Action)`, `(Midpoint)`, `(Climax)`, `(Falling Action)`, or `(Resolution)`. Untagged headings are spread evenly along the arc, so a rough outline still shows a shape. Click a point on the chart to jump straight to that heading.

        ## Writing the manuscript

        Use the **+** button → **New Chapter**. Sable numbers it for you. Your `#` headings appear in the **Outline** tab, and you can rename that tab to Chapters, Scenes, or anything else from its sliders button. Press ⇧⌘F for paragraph focus, or use the toolbar for reading mode and themes.

        Open the **Manuscript** tab at the top of the desk for your total word count, an optional goal with a progress bar, and every chapter with its length. Drag chapters to rearrange them; the order is saved in the project and your files are never renamed or changed. Other editors will still list them alphabetically.

        ## Cards for characters, places, and ideas

        Use **+** → **New Character** (or Location, or World Note). Each one starts from a template you can rewrite freely. Then hover the file in the desk and click the card icon, or Control-click → **Show as Card**.

        - **Move it.** Drag a card and it snaps to the nearest corner of your page.
        - **Keep or tuck it.** The pin keeps a card open. Unpinned, it shrinks to a small tab and opens when you point at it.
        - **Resize it.** Drag the grip on its outer corner. Double-click the grip to reset.
        - **Add a portrait.** Click the portrait square (or drop an image on the card), then drag and zoom to frame it. **Adjust Crop…** in the card's ⋯ menu changes it later.

        ## Tagging scenes

        In a chapter, a quiet strip of small chips at the bottom of the page shows the location and characters in that scene. Click **Tag this scene** (or press ⌃⌘T) to choose them from your cards. Click a chip to open its card without leaving the page, so you can check a detail and get back to writing. A dashed chip means there's no card with that name yet; click it to create one.

        The strip fades almost away while you type and returns when you pause. In **Writing Style** you can move it to a corner or turn it off. Tags are saved at the top of the chapter's file, so any editor can read them:

        ```
        ---
        location: The Pier
        characters: Marren Vale, Old Tam
        world: Bell Law
        ---
        ```

        A name matches a card by its file name, its title, or a line like `aliases: Mara, The Pilot` in the card. Chips take the card's color, so you can tell people and places apart at a glance. In paragraph focus, the strip and any collapsed card tabs dim until you point at them.

        ## Adding things quickly

        Point at the **Manuscript**, **Characters**, **Locations**, or **World** folder in the desk and click the **+** that appears. Manuscript adds the next chapter; the others ask for a name. It works on folders inside them, too: a **+** on Characters/Villains adds a character there.

        ## What a card reads from the file

        The block at the very top of a card file, between the two `---` lines, holds its details:

        ```
        ---
        type: character
        role: Harbor pilot
        tags: protagonist, pilot
        image: Images/marren.png
        image-crop: 0.10,0.05,0.70,0.88
        color: blue
        ---
        ```

        - **type** says what kind of card it is: `character`, `location`, or `lore` (world notes).
        - **role** (characters), **region** (locations), or **category** (world notes) appears under the name.
        - **tags** appear as small labels. Separate them with commas.
        - **image** and **image-crop** are set for you when you add a portrait.
        - **color** (`red`, `orange`, `yellow`, `green`, `blue`, `purple`, `gray`, or a hex value like `#8A6A34`) tints the card and its scene-tag chip. Pick one from the card's ⋯ menu → **Color**.

        The card's title is the file's first `# Heading`, and the rest of the file is shown below it.

        ## Making it your own

        - **Add folders.** Make a folder called Factions, Magic, or Timeline. A file becomes a card if it sits in a folder named Characters, Locations, or World, or whenever it has a `type:` line. Put `type: lore` at the top of any file in the project, then Control-click it → **Show as Card**.
        - **Add your own fields.** Write any `key: value` line in the block, like `age: 34` or `home: Saltmarsh`. Sable leaves lines it doesn't use untouched, so they're yours to keep.
        - **Rewrite the templates.** The sections in a new character (Appearance, Personality…) are just Markdown. Delete, rename, or add your own.
        - **Color and pin.** Control-click any file or folder for **Color** and **Pin to Top**. Name your colors (Draft, Revised, Final…) from the sliders button at the top of the file list.
        - **Sort and search.** The sliders button also sets sorting, word counts, and compact rows. The search box searches every folder in the project by name.

        ## Leaving, and changing your mind

        The **Leave** button at the top of the desk takes you back to all your files. To stop treating this folder as a project, use the ⋯ menu → **Convert to Regular Folder…**. That removes only a small hidden file named `.sable-project.json`; every file and folder stays exactly as it is.

        Happy writing.
        """
    }
}

/// A pre-filled scratchpad for thinking a story through before drafting it: not a card, not a chapter, just questions.
enum ConceptDocument {
    static let fileName = "Concept.md"

    static func text(projectName: String) -> String {
        """
        # \(projectName): Concept

        A place to think before you draft. Answer what's useful and delete the rest; this is scratch paper, not a form.

        ## Logline

        One or two sentences: who wants what, and what stands in the way?

        ## Writer's pitch

        Why this story, why you, why now? What made you want to write it?

        ## Genre & tone

        ## Major themes

        What is this story really about, underneath the plot?

        ## Comparable titles

        Books, shows, or films this sits near on a shelf, and how yours is different.

        ## Who is this for?

        ## Central question

        The question the story asks that its ending answers.

        ## Notes

        """
    }
}

/// A starting point for the Outline folder, showing the beat-tagging syntax the Story Timeline reads.
enum OutlineStarter {
    static let fileName = "Outline.md"

    static let text = """
    # Story Outline

    Use headings for acts, chapters, or beats — however you like to plan. Tag any heading with a beat in
    parentheses and it takes its place on the Story Timeline (File menu → Story Timeline…): (Inciting Incident),
    (Rising Action), (Midpoint), (Climax), (Falling Action), or (Resolution). Untagged headings are spread evenly
    along the arc, so even a rough outline shows a shape.

    ## Chapter 1 — Ordinary World

    ## Chapter 3 — The Door Opens (Inciting Incident)

    ## Chapter 9 — Everything Changes (Midpoint)

    ## Chapter 15 — The Reckoning (Climax)

    ## Chapter 17 — After (Resolution)
    """
}

struct FictionProject: Codable, Equatable, Sendable {
    static let markerName = ".sable-project.json"
    /// The name projects made before the app was renamed use. Still recognized, and replaced on the next save.
    static let legacyMarkerName = ".quill-project.json"
    static let manuscriptFolder = "Manuscript"
    static let imagesFolder = "Images"
    static let outlineFolder = "Outline"
    static let standardFolders = [manuscriptFolder, "Characters", "Locations", "World", outlineFolder, "Notes", imagesFolder]

    var kind = "fiction"
    var title: String
    var created: Date? = nil
    var version = 1
    /// Optional target for the whole manuscript, in words.
    var wordGoal: Int? = nil
    /// Chapter file names in the order the writer arranged them. Kept here, not in the files, so chapters are never touched.
    var chapterOrder: [String]? = nil

    // MARK: Detecting and reading

    static func guideURL(in project: URL) -> URL { project.appendingPathComponent(ProjectGuide.fileName) }
    static func conceptURL(in project: URL) -> URL { project.appendingPathComponent(ConceptDocument.fileName) }

    /// The project's Start Here note, written if it isn't there (an existing one is never overwritten).
    @discardableResult
    static func ensureGuide(in project: URL) throws -> URL {
        let url = guideURL(in: project)
        if !FileManager.default.fileExists(atPath: url.path) {
            try Data(ProjectGuide.text(projectName: load(project)?.title ?? project.lastPathComponent).utf8).write(to: url, options: .withoutOverwriting)
        }
        return url
    }

    /// The project's Concept note, written if it isn't there (an existing one is never overwritten).
    @discardableResult
    static func ensureConcept(in project: URL) throws -> URL {
        let url = conceptURL(in: project)
        if !FileManager.default.fileExists(atPath: url.path) {
            try Data(ConceptDocument.text(projectName: load(project)?.title ?? project.lastPathComponent).utf8).write(to: url, options: .withoutOverwriting)
        }
        return url
    }

    /// Where the project's marker is now: the current file, or the older-named one if that's all there is.
    static func markerURL(in folder: URL) -> URL {
        let current = folder.appendingPathComponent(markerName)
        let legacy = folder.appendingPathComponent(legacyMarkerName)
        return !FileManager.default.fileExists(atPath: current.path) && FileManager.default.fileExists(atPath: legacy.path) ? legacy : current
    }
    static func isProject(_ folder: URL) -> Bool { FileManager.default.fileExists(atPath: markerURL(in: folder).path) }

    /// A damaged marker still counts as a project, named after its folder, so a stray edit never locks anyone out.
    static func load(_ folder: URL) -> FictionProject? {
        guard isProject(folder) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: markerURL(in: folder)), let project = try? decoder.decode(FictionProject.self, from: data), !project.title.isEmpty {
            return project
        }
        return FictionProject(title: folder.lastPathComponent)
    }

    /// The project that contains `url` (or `url` itself, if it is a project folder), searching upward
    /// but never above `root`.
    static func projectRoot(containing url: URL, within root: URL) -> URL? {
        var directory = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        if !(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) && isDirectory.boolValue) {
            directory = directory.deletingLastPathComponent()
        }
        while FolderMove.isInside(directory, of: root) {
            if isProject(directory) { return directory }
            if directory == root.standardizedFileURL { return nil }
            let parent = directory.deletingLastPathComponent()
            if parent == directory { return nil }
            directory = parent
        }
        return nil
    }

    /// Changes the project's settings in place, keeping everything else in the marker.
    static func update(_ folder: URL, _ change: (inout FictionProject) -> Void) throws {
        guard isProject(folder) else { throw FictionProjectError.notProject }
        var project = load(folder) ?? FictionProject(title: folder.lastPathComponent)
        change(&project)
        try writeMarker(project, in: folder)
    }
    static func setChapterOrder(_ names: [String], in folder: URL) throws { try update(folder) { $0.chapterOrder = names } }
    static func setWordGoal(_ goal: Int?, in folder: URL) throws { try update(folder) { $0.wordGoal = (goal ?? 0) > 0 ? goal : nil } }

    // MARK: Creating, adopting, converting

    static func writeMarker(_ project: FictionProject, in folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(project).write(to: folder.appendingPathComponent(markerName), options: .atomic)
        // An older marker is migrated rather than left behind beside the new one.
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(legacyMarkerName))
    }

    /// Creates a project folder with the standard structure. Starter files give an empty project something to open.
    @discardableResult
    static func create(named raw: String, in parent: URL, starterFiles: Bool) throws -> URL {
        guard let name = FolderCreation.fileName(for: raw, kind: .folder) else { throw FolderCreationError.invalidName }
        let folder = parent.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: folder.path) else { throw FolderCreationError.exists(name) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        do {
            try writeMarker(FictionProject(title: name, created: Date()), in: folder)
            for standard in standardFolders {
                try FileManager.default.createDirectory(at: folder.appendingPathComponent(standard, isDirectory: true), withIntermediateDirectories: true)
            }
            try ensureGuide(in: folder)
            try ensureConcept(in: folder)
            if starterFiles {
                _ = try createItem(.chapter, named: "Chapter 1", in: folder)
                _ = try createItem(.character, named: "Example Character", in: folder)
                _ = try createItem(.location, named: "Example Location", in: folder)
                try Data(OutlineStarter.text.utf8).write(to: folder.appendingPathComponent(outlineFolder).appendingPathComponent(OutlineStarter.fileName), options: .withoutOverwriting)
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return folder
    }

    /// Turns an existing folder into a project in place. Nothing that is already there is moved or changed.
    static func adopt(_ folder: URL, addStandardFolders: Bool) throws {
        guard !isProject(folder) else { throw FictionProjectError.alreadyProject }
        try writeMarker(FictionProject(title: folder.lastPathComponent, created: Date()), in: folder)
        guard addStandardFolders else { return }
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.map { $0.lowercased() } ?? [])
        for standard in standardFolders where !existing.contains(standard.lowercased()) {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(standard, isDirectory: true), withIntermediateDirectories: true)
        }
    }

    /// Back to a regular folder: removes only the marker. Every file and folder stays exactly as it was.
    static func convertToRegularFolder(_ folder: URL) throws {
        guard isProject(folder) else { throw FictionProjectError.notProject }
        try FileManager.default.removeItem(at: markerURL(in: folder))
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(markerName))
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(legacyMarkerName))
    }

    // MARK: Items

    /// The existing folder for an item type (matched without regard to case), or the standard name.
    static func folder(for item: NewProjectItem, in project: URL) -> URL {
        let wanted = item.folderName.lowercased()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: project.path)) ?? []
        return project.appendingPathComponent(names.first { $0.lowercased() == wanted } ?? item.folderName, isDirectory: true)
    }

    /// Creates a chapter, character, location, or world note. `folder` puts it in a particular folder of the
    /// project (like Characters/Villains) instead of the standard one.
    @discardableResult
    static func createItem(_ item: NewProjectItem, named raw: String, in project: URL, folder chosen: URL? = nil) throws -> URL {
        guard let fileName = FolderCreation.fileName(for: raw, kind: .file) else { throw FolderCreationError.invalidName }
        if let chosen, !FolderMove.isInside(chosen, of: project) { throw FolderMoveError.outsideRoot }
        let folder = chosen ?? folder(for: item, in: project)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw FolderCreationError.exists(fileName) }
        let title = (fileName as NSString).deletingPathExtension
        try Data(item.template(named: title).utf8).write(to: url, options: .withoutOverwriting)
        return url
    }

    /// "Chapter 4" when Chapter 1–3 exist.
    static func nextChapterName(in project: URL) -> String {
        let folder = folder(for: .chapter, in: project)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let numbers = names.compactMap { name -> Int? in
            let stem = (name as NSString).deletingPathExtension
            guard stem.lowercased().hasPrefix("chapter ") else { return nil }
            return Int(stem.dropFirst("chapter ".count).trimmingCharacters(in: .whitespaces))
        }
        return "Chapter \((numbers.max() ?? 0) + 1)"
    }
}

// MARK: - Manuscript overview

struct ChapterStat: Equatable, Sendable, Identifiable {
    let url: URL
    let words: Int
    let modified: Date?
    let size: Int
    var id: URL { url }
    var name: String { url.lastPathComponent }
    var title: String { url.deletingPathExtension().lastPathComponent }
}

enum ManuscriptStats {
    static let fileExtensions = ["md", "markdown", "txt"]

    /// Words in a chapter, not counting a front-matter block or stray Markdown punctuation.
    static func wordCount(in text: String) -> Int { FolderListing.wordCount(in: FrontMatter.parse(text).body) }

    /// Names in the writer's order, followed by anything not yet placed (new or renamed elsewhere) in natural order.
    static func orderedNames(_ names: [String], order: [String]?) -> [String] {
        let present = Set(names)
        var seen = Set<String>()
        let placed = (order ?? []).filter { present.contains($0) && seen.insert($0).inserted }
        let rest = names.filter { !seen.contains($0) }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return placed + rest
    }

    /// The full order after dragging `name` onto `target`'s position.
    static func moved(_ names: [String], _ name: String, to target: String) -> [String] {
        guard let from = names.firstIndex(of: name), let to = names.firstIndex(of: target), from != to else { return names }
        var result = names
        result.insert(result.remove(at: from), at: to)
        return result
    }

    /// Reads the chapters in a folder. Files unchanged since `previous` (same date and size) reuse their old count.
    static func load(folder: URL, order: [String]?, reusing previous: [ChapterStat] = []) -> [ChapterStat] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        let files = urls.filter { fileExtensions.contains($0.pathExtension.lowercased()) && (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
        let byName = Dictionary(uniqueKeysWithValues: files.map { ($0.lastPathComponent, $0) })
        let cache = Dictionary(previous.map { ($0.url.lastPathComponent, $0) }, uniquingKeysWith: { first, _ in first })
        return orderedNames(Array(byName.keys), order: order).compactMap { name in
            guard let url = byName[name] else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let modified = values?.contentModificationDate, size = values?.fileSize ?? 0
            if let old = cache[name], old.modified == modified, old.size == size { return ChapterStat(url: url, words: old.words, modified: modified, size: size) }
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            return ChapterStat(url: url, words: wordCount(in: text), modified: modified, size: size)
        }
    }
}

// MARK: - Front matter

/// Just enough YAML to read and write the handful of simple `key: value` lines cards use.
/// Everything else in the block (lists, comments, keys we don't know) is left untouched.
struct FrontMatter: Sendable {
    var fields: [(key: String, value: String)] = []
    var body = ""
    var hasBlock = false

    func value(for key: String) -> String? {
        let found = fields.first { $0.key.lowercased() == key.lowercased() }?.value
        return (found?.isEmpty ?? true) ? nil : found
    }

    static func parse(_ text: String) -> FrontMatter {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let close = lines.indices.dropFirst().first(where: { ["---", "..."].contains(lines[$0].trimmingCharacters(in: .whitespaces)) }) else {
            return FrontMatter(fields: [], body: text, hasBlock: false)
        }
        var fields: [(String, String)] = []
        var openList: Int?   // a key with no value on its line, whose "- item" lines follow
        for line in lines[1..<close] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // "- item" lines under an empty key belong to that key, the way YAML writes a list.
            if trimmed.hasPrefix("- "), let index = openList {
                let item = unquote(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                fields[index].1 += (fields[index].1.isEmpty ? "" : ", ") + item
                continue
            }
            guard let first = line.first, first != " ", first != "\t", first != "-", first != "#", let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = unquote(String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
            if !key.isEmpty { fields.append((key, value)); openList = value.isEmpty ? fields.count - 1 : nil } else { openList = nil }
        }
        let body = lines[(close + 1)...].joined(separator: "\n").trimmingCharacters(in: CharacterSet.newlines)
        return FrontMatter(fields: fields, body: body, hasBlock: true)
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" else { return value }
        let inner = String(value.dropFirst().dropLast())
        return first == "\"" ? inner.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\") : inner.replacingOccurrences(of: "''", with: "'")
    }

    private static func format(_ value: String) -> String {
        guard !value.isEmpty else { return "" }
        let needsQuotes = value != value.trimmingCharacters(in: .whitespaces) || value.contains(": ") || value.contains(" #")
            || value.contains("\n") || "[]{}&*!|>'\"%@`#,-?".contains(value.first!)
        guard needsQuotes else { return value }
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }

    /// Returns `text` with `key` set, adding a front-matter block if the file doesn't have one.
    static func setting(_ key: String, to value: String, in text: String) -> String {
        let line = value.isEmpty ? "\(key):" : "\(key): \(format(value))"
        var lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let close = lines.indices.dropFirst().first(where: { ["---", "..."].contains(lines[$0].trimmingCharacters(in: .whitespaces)) }) else {
            return "---\n\(line)\n---\n\n" + text
        }
        if let existing = (1..<close).first(where: { lines[$0].lowercased().hasPrefix(key.lowercased() + ":") }) {
            // A key that held a list ("- item" lines) is replaced whole, so no orphaned items are left behind.
            lines.removeSubrange(existing...continuationEnd(after: existing, in: lines, before: close))
            lines.insert(line, at: existing)
        } else {
            lines.insert(line, at: close)
        }
        return lines.joined(separator: "\n")
    }

    /// The last line belonging to the key that starts at `index`: any indented or "- item" lines that follow it.
    private static func continuationEnd(after index: Int, in lines: [String], before close: Int) -> Int {
        var end = index
        while end + 1 < close, let first = lines[end + 1].first, first == " " || first == "\t" || lines[end + 1].hasPrefix("- ") { end += 1 }
        return end
    }

    /// Returns `text` without `key`. A front-matter block left empty is removed along with its blank line.
    static func removing(_ key: String, in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              var close = lines.indices.dropFirst().first(where: { ["---", "..."].contains(lines[$0].trimmingCharacters(in: .whitespaces)) }),
              let existing = (1..<close).first(where: { lines[$0].lowercased().hasPrefix(key.lowercased() + ":") }) else { return text }
        let end = continuationEnd(after: existing, in: lines, before: close)
        lines.removeSubrange(existing...end)
        close -= end - existing + 1
        if close == 1 {
            lines.removeSubrange(0...1)
            if lines.first?.isEmpty == true { lines.removeFirst() }
        }
        return lines.joined(separator: "\n")
    }

    static func tags(from raw: String?) -> [String] {
        guard var raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return [] }
        if raw.hasPrefix("["), raw.hasSuffix("]") { raw = String(raw.dropFirst().dropLast()) }
        return raw.split(separator: ",").map { unquote($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty }
    }
}

// MARK: - Scene tags

/// Who and what appears in a chapter, kept in its front matter (`location:`, `characters:`, `world:`) so any
/// editor can read and change it. Names refer to cards by file name, title, or alias.
struct SceneTags: Equatable, Sendable {
    var locations: [String] = []
    var characters: [String] = []
    var world: [String] = []
    var isEmpty: Bool { locations.isEmpty && characters.isEmpty && world.isEmpty }

    static let kinds: [CardKind] = [.location, .character, .lore]
    static func key(for kind: CardKind) -> String {
        switch kind { case .location: return "locations"; case .character: return "characters"; case .lore: return "world" }
    }
    /// Other spellings that are read, and cleaned up when tags are saved.
    private static func alternateKeys(for kind: CardKind) -> [String] {
        switch kind { case .location: return ["location", "place", "places", "setting"]; case .character: return ["character", "cast"]; case .lore: return ["lore", "items"] }
    }
    func names(for kind: CardKind) -> [String] {
        switch kind { case .location: return locations; case .character: return characters; case .lore: return world }
    }

    static func parse(_ text: String) -> SceneTags {
        let front = FrontMatter.parse(text)
        func list(_ kind: CardKind) -> [String] {
            var seen = Set<String>()
            return ([key(for: kind)] + alternateKeys(for: kind)).flatMap { FrontMatter.tags(from: front.value(for: $0)) }
                .filter { seen.insert(CardIndex.normalize($0)).inserted }
        }
        return SceneTags(locations: list(.location), characters: list(.character), world: list(.lore))
    }

    /// The text with this kind's names set (or the key removed when there are none).
    static func setting(_ names: [String], for kind: CardKind, in text: String) -> String {
        var result = text
        for alternate in alternateKeys(for: kind) { result = FrontMatter.removing(alternate, in: result) }
        let clean = names.map { $0.replacingOccurrences(of: ",", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return clean.isEmpty ? FrontMatter.removing(key(for: kind), in: result) : FrontMatter.setting(key(for: kind), to: clean.joined(separator: ", "), in: result)
    }

    /// Names after switching `card` on or off for this kind.
    func toggling(_ card: IndexedCard, kind: CardKind) -> [String] {
        let current = names(for: kind)
        let mine = Set(card.names.map(CardIndex.normalize))
        let without = current.filter { !mine.contains(CardIndex.normalize($0)) }
        return without.count == current.count ? current + [card.stem] : without
    }
    func removing(_ name: String, kind: CardKind) -> [String] {
        names(for: kind).filter { CardIndex.normalize($0) != CardIndex.normalize(name) }
    }
}

struct IndexedCard: Equatable, Sendable, Identifiable {
    let url: URL
    let kind: CardKind
    let stem: String
    let title: String
    let subtitle: String
    let aliases: [String]
    let modified: Date?
    var color: String? = nil
    var id: URL { url }
    /// Every name this card answers to.
    var names: [String] { [stem, title] + aliases }
}

/// A quick list of the project's cards, so tags can be matched to them and offered in a picker.
enum CardIndex {
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reads just the top of each card file (files unchanged since `previous` are not read again).
    static func load(project: URL, reusing previous: [IndexedCard] = []) -> [IndexedCard] {
        let manuscript = FictionProject.folder(for: .chapter, in: project).standardizedFileURL.path
        let cache = Dictionary(previous.map { ($0.url.standardizedFileURL.path, $0) }, uniquingKeysWith: { first, _ in first })
        guard let walker = FileManager.default.enumerator(at: project, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var cards: [IndexedCard] = []
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            if values?.isDirectory == true {
                let path = url.standardizedFileURL.path
                if path == manuscript || url.lastPathComponent == FictionProject.imagesFolder { walker.skipDescendants() }
                continue
            }
            guard ["md", "markdown"].contains(url.pathExtension.lowercased()),
                  url.lastPathComponent != ProjectGuide.fileName, url.lastPathComponent != ConceptDocument.fileName else { continue }
            let modified = values?.contentModificationDate
            if let old = cache[url.standardizedFileURL.path], old.modified == modified { cards.append(old); continue }
            guard let handle = try? FileHandle(forReadingFrom: url), let head = try? handle.read(upToCount: 4096) else { continue }
            try? handle.close()
            let text = String(decoding: head, as: UTF8.self)
            guard let info = CardParsing.info(for: url, text: text, projectRoot: project) else { continue }
            let aliases = FrontMatter.tags(from: FrontMatter.parse(text).value(for: "aliases"))
            cards.append(IndexedCard(url: url, kind: info.kind, stem: url.deletingPathExtension().lastPathComponent, title: info.title,
                                     subtitle: info.subtitle, aliases: aliases, modified: modified, color: info.color))
        }
        return cards.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The card a tag refers to, preferring one of the same kind.
    static func match(_ name: String, kind: CardKind, in cards: [IndexedCard]) -> IndexedCard? {
        let wanted = normalize(name)
        let named = cards.filter { $0.names.contains { normalize($0) == wanted } }
        return named.first { $0.kind == kind } ?? named.first
    }
}

// MARK: - Name highlighting

/// Finds the names of a project's characters, places, and world notes in a chapter, so the editor can make them
/// stand out. It matches full names, single names taken from them (a first name, a last name), file names, and
/// aliases, but never everyday words: small words and titles like "Captain" are ignored, and a single word only
/// matches when it is capitalized, so a character called Rose doesn't light up every "rose".
final class NameHighlighter: Equatable, @unchecked Sendable {
    struct Entry: Equatable, Sendable {
        let text: String
        let kind: CardKind
        let exactCase: Bool
    }
    let entries: [Entry]
    /// Changes whenever the set of names does, so callers know when to restyle.
    let signature: String
    private let looseKinds: [String: CardKind]   // lowercased text → kind
    private let exactKinds: [String: CardKind]
    private let looseExpression: NSRegularExpression?
    private let exactExpression: NSRegularExpression?

    static let empty = NameHighlighter(entries: [])
    static func == (lhs: NameHighlighter, rhs: NameHighlighter) -> Bool { lhs.signature == rhs.signature }

    /// Words that are never names on their own.
    static let ignoredWords: Set<String> = [
        "the", "and", "for", "with", "from", "into", "onto", "over", "under", "old", "new", "young", "little", "great", "grand", "big", "small",
        "of", "in", "on", "at", "to", "a", "an", "captain", "commander", "lord", "lady", "sir", "dame", "king", "queen", "prince", "princess",
        "duke", "duchess", "baron", "baroness", "count", "countess", "mister", "mrs", "miss", "doctor", "professor", "father", "mother",
        "brother", "sister", "master", "mistress", "saint", "st", "mr", "ms", "dr", "north", "south", "east", "west", "city", "town", "house",
    ]

    init(entries: [Entry]) {
        // If two cards claim the same text, a character wins over a place, and a place over a world note.
        func rank(_ kind: CardKind) -> Int { kind == .character ? 0 : (kind == .location ? 1 : 2) }
        var loose: [String: CardKind] = [:], exact: [String: CardKind] = [:]
        for entry in entries.sorted(by: { rank($0.kind) > rank($1.kind) }) {
            if entry.exactCase { exact[entry.text] = entry.kind } else { loose[entry.text.lowercased()] = entry.kind }
        }
        self.entries = entries
        self.staysOnOneLine = !entries.contains { $0.text.contains("\n") }
        self.looseKinds = loose
        self.exactKinds = exact
        self.signature = entries.map { "\($0.kind.rawValue):\($0.exactCase ? "=" : "~")\($0.text)" }.sorted().joined(separator: "|")
        func expression(_ names: [String], options: NSRegularExpression.Options) -> NSRegularExpression? {
            guard !names.isEmpty else { return nil }
            let alternatives = names.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
            return try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_])(?:\(alternatives))(?![\\p{L}\\p{N}_])", options: options)
        }
        self.looseExpression = expression(Array(loose.keys), options: [.caseInsensitive])
        self.exactExpression = expression(Array(exact.keys), options: [])
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Every way a card can be named in prose.
    static func build(from cards: [IndexedCard]) -> NameHighlighter {
        var entries: [Entry] = []
        var seen = Set<String>()
        func add(_ text: String, _ kind: CardKind, exactCase: Bool) {
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard clean.count >= 2, seen.insert("\(kind.rawValue)|\(exactCase)|\(exactCase ? clean : clean.lowercased())").inserted else { return }
            entries.append(Entry(text: clean, kind: kind, exactCase: exactCase))
        }
        for card in cards {
            for name in card.names {
                let words = name.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                guard !words.isEmpty else { continue }
                // A whole name of several words is specific enough to match in any capitalization ("the pier").
                add(name, card.kind, exactCase: words.count == 1)
                guard words.count > 1 else { continue }
                // Only a character is also known by a first or last name on its own (capitalized, and never a small word or a title).
                // A place or world note is matched by its whole phrase, so "Academy" alone doesn't light up "Highlandsburg Academy".
                guard card.kind == .character else { continue }
                for word in [words.first, words.last].compactMap({ $0 }) {
                    let trimmed = word.trimmingCharacters(in: .punctuationCharacters)
                    guard trimmed.count >= 3, trimmed.first?.isUppercase == true, !ignoredWords.contains(trimmed.lowercased()) else { continue }
                    add(trimmed, card.kind, exactCase: true)
                }
            }
        }
        return NameHighlighter(entries: Array(entries.prefix(4000)))
    }

    /// Where names occur in `text`, longest first and never overlapping. A front-matter block is skipped.
    func matches(in text: String, kinds: Set<CardKind> = Set(CardKind.allCases)) -> [(range: NSRange, kind: CardKind)] {
        matches(in: text, kinds: kinds, range: NSRange(location: 0, length: (text as NSString).length))
    }

    /// No name holds a line break, so the names in a run of whole lines are the same whether the whole text is searched or
    /// just those lines. The editor relies on this to restyle only the paragraph being written.
    let staysOnOneLine: Bool

    /// The names a whole-text search finds inside `range`, which must be whole lines (see `TextLines`).
    func matches(in text: String, kinds: Set<CardKind>, range: NSRange) -> [(range: NSRange, kind: CardKind)] {
        guard !isEmpty, !kinds.isEmpty else { return [] }
        let ns = text as NSString
        let start = NameHighlighter.frontMatterLength(in: ns)
        let area = NSIntersectionRange(NSRange(location: start, length: ns.length - start), range)
        guard area.length > 0 else { return [] }
        let bounds: NSRegularExpression.MatchingOptions = [.withTransparentBounds, .withoutAnchoringBounds]
        var found: [(range: NSRange, kind: CardKind)] = []
        looseExpression?.enumerateMatches(in: text, options: bounds, range: area) { match, _, _ in
            guard let range = match?.range, let kind = looseKinds[ns.substring(with: range).lowercased()], kinds.contains(kind) else { return }
            found.append((range, kind))
        }
        exactExpression?.enumerateMatches(in: text, options: bounds, range: area) { match, _, _ in
            guard let range = match?.range, let kind = exactKinds[ns.substring(with: range)], kinds.contains(kind) else { return }
            found.append((range, kind))
        }
        found.sort { $0.range.location != $1.range.location ? $0.range.location < $1.range.location : $0.range.length > $1.range.length }
        var result: [(range: NSRange, kind: CardKind)] = []
        var end = 0
        for item in found where item.range.location >= end {
            result.append(item)
            end = NSMaxRange(item.range)
        }
        return result
    }

    /// Length of a leading `---` block (including its closing line), or 0.
    static func frontMatterLength(in text: NSString) -> Int {
        guard text.hasPrefix("---\n") else { return 0 }
        let rest = NSRange(location: 4, length: text.length - 4)
        let close = text.range(of: "\n---", options: [], range: rest)
        guard close.location != NSNotFound else { return 0 }
        return min(text.length, NSMaxRange(close))
    }
}

// MARK: - Cards

/// Which part of a picture a card shows, as fractions of the picture (origin top-left). Stored as
/// `image-crop: x, y, width, height` in the file, so the original picture is never altered.
struct CropRect: Equatable, Sendable {
    var x: Double, y: Double, width: Double, height: Double
    /// Width over height of the portrait a card shows.
    static let portraitAspect = 0.8
    static let maxZoom = 4.0

    var formatted: String { String(format: "%.4f,%.4f,%.4f,%.4f", x, y, width, height) }

    init(x: Double, y: Double, width: Double, height: Double) { (self.x, self.y, self.width, self.height) = (x, y, width, height) }

    init?(parsing raw: String?) {
        guard let raw else { return nil }
        let numbers = raw.split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0) }
        guard numbers.count == 4, numbers[2] > 0.02, numbers[3] > 0.02,
              numbers[0] >= -0.001, numbers[1] >= -0.001, numbers[0] + numbers[2] <= 1.001, numbers[1] + numbers[3] <= 1.001 else { return nil }
        self.init(x: max(0, numbers[0]), y: max(0, numbers[1]), width: numbers[2], height: numbers[3])
    }

    /// Size of the crop window at zoom 1: the largest rectangle of `aspect` that fits the picture.
    static func baseSize(imageSize: CGSize, aspect: Double = portraitAspect) -> (width: Double, height: Double) {
        let imageAspect = Double(imageSize.width / imageSize.height)
        return imageAspect > aspect ? (Double(imageSize.height) * aspect / Double(imageSize.width), 1) : (1, Double(imageSize.width) / aspect / Double(imageSize.height))
    }

    /// The crop for a zoom level and a center point (both in picture fractions), kept inside the picture.
    static func make(imageSize: CGSize, aspect: Double = portraitAspect, zoom: Double, centerX: Double, centerY: Double) -> CropRect {
        let base = baseSize(imageSize: imageSize, aspect: aspect)
        let z = min(maxZoom, max(1, zoom))
        let w = base.width / z, h = base.height / z
        return CropRect(x: min(1 - w, max(0, centerX - w / 2)), y: min(1 - h, max(0, centerY - h / 2)), width: w, height: h)
    }

    /// The zoom level this crop represents for a picture of `imageSize`.
    func zoom(imageSize: CGSize, aspect: Double = CropRect.portraitAspect) -> Double {
        max(1, CropRect.baseSize(imageSize: imageSize, aspect: aspect).width / width)
    }
    var centerX: Double { x + width / 2 }
    var centerY: Double { y + height / 2 }
}

/// A card's color, written in its front matter as `color: blue` (or a hex value like `#8A6A34`).
enum CardColor {
    static let names = ["red", "orange", "yellow", "green", "blue", "purple", "gray"]
    /// A recognized name or "#RRGGBB" (lowercased), else nil, so a typo never breaks a card.
    static func normalized(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !value.isEmpty else { return nil }
        if names.contains(value) { return value }
        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        return hex.count == 6 && hex.allSatisfy(\.isHexDigit) ? "#" + hex : nil
    }
}

struct CardInfo: Equatable, Sendable {
    var url: URL
    var kind: CardKind
    var title: String
    var subtitle: String
    var tags: [String]
    var imageRef: String?
    var imageCrop: CropRect?
    var color: String?
    var body: String
}

enum CardParsing {
    static let imageExtensions = ["png", "jpg", "jpeg", "gif", "heic", "tif", "tiff", "webp"]

    /// A file is a card when its front matter says so (`type: character`), or when it lives in a
    /// folder named for one (Characters, Locations, World).
    static func kind(of url: URL, frontMatter: FrontMatter, projectRoot: URL) -> CardKind? {
        if let declared = frontMatter.value(for: "type") ?? frontMatter.value(for: "card") { return CardKind.named(declared) }
        return kindByLocation(url, projectRoot: projectRoot)
    }

    static func kindByLocation(_ url: URL, projectRoot: URL) -> CardKind? {
        var folder = url.deletingLastPathComponent().standardizedFileURL
        while FolderMove.isInside(folder, of: projectRoot), folder != projectRoot.standardizedFileURL {
            if let kind = CardKind.named(folder.lastPathComponent) { return kind }
            folder = folder.deletingLastPathComponent()
        }
        return nil
    }

    /// Whether the filename alone is enough to offer "show as card" (used by the desk before any file is read).
    static func isCandidate(_ url: URL, projectRoot: URL) -> Bool {
        ["md", "markdown"].contains(url.pathExtension.lowercased()) && kindByLocation(url, projectRoot: projectRoot) != nil
    }

    /// `fallback` lets a writer show any Markdown file as a card, even one outside the usual folders.
    static func info(for url: URL, text: String, projectRoot: URL, fallback: CardKind? = nil) -> CardInfo? {
        let front = FrontMatter.parse(text)
        guard let kind = kind(of: url, frontMatter: front, projectRoot: projectRoot) ?? fallback else { return nil }
        var lines = front.body.components(separatedBy: "\n")
        var title = url.deletingPathExtension().lastPathComponent
        if let index = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           lines[index].hasPrefix("# ") {
            title = String(lines[index].dropFirst(2)).trimmingCharacters(in: .whitespaces)
            lines.remove(at: index)
        }
        let subtitle = (kind.subtitleKeys + ["subtitle"]).lazy.compactMap { front.value(for: $0) }.first ?? ""
        return CardInfo(url: url, kind: kind, title: title, subtitle: subtitle,
                        tags: FrontMatter.tags(from: front.value(for: "tags")),
                        imageRef: front.value(for: "image"),
                        imageCrop: CropRect(parsing: front.value(for: "image-crop")),
                        color: CardColor.normalized(front.value(for: "color")),
                        body: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: Images

    static func isImage(_ url: URL) -> Bool { imageExtensions.contains(url.pathExtension.lowercased()) }

    /// Finds the picture a card refers to: an absolute path, or one relative to the card or to the project.
    static func resolveImage(_ ref: String, card: URL, projectRoot: URL) -> URL? {
        let trimmed = ref.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let candidates: [URL] = trimmed.hasPrefix("/")
            ? [URL(fileURLWithPath: trimmed)]
            : [card.deletingLastPathComponent().appendingPathComponent(trimmed),
               projectRoot.appendingPathComponent(trimmed),
               projectRoot.appendingPathComponent(FictionProject.imagesFolder).appendingPathComponent(trimmed)]
        return candidates.first { isImage($0) && FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Copies a picture into the project's Images folder (unless it's already inside the project) and
    /// returns the path to store in the card, relative to the project.
    static func importImage(_ source: URL, into projectRoot: URL) throws -> String {
        guard isImage(source) else { throw FictionProjectError.badImage(source.lastPathComponent) }
        if FolderMove.isInside(source, of: projectRoot) {
            return source.standardizedFileURL.pathComponents.dropFirst(projectRoot.standardizedFileURL.pathComponents.count).joined(separator: "/")
        }
        let folder = projectRoot.appendingPathComponent(FictionProject.imagesFolder, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stem = source.deletingPathExtension().lastPathComponent, ext = source.pathExtension
        var destination = folder.appendingPathComponent(source.lastPathComponent)
        var number = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = folder.appendingPathComponent("\(stem)-\(number).\(ext)")
            number += 1
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return "\(FictionProject.imagesFolder)/\(destination.lastPathComponent)"
    }
}
