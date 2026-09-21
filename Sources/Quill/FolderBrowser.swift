import SwiftUI
import AppKit

struct BrowserEntry: Identifiable, Sendable {
    var id: URL { url }
    let url: URL
    let isDirectory: Bool
    var modified: Date? = nil
    var isProject = false
    var name: String { url.lastPathComponent }
    /// The name as shown in the desk; Markdown and text extensions are noise when every file has one.
    var displayName: String {
        guard !isDirectory, FolderCreation.fileExtensions.contains(url.pathExtension.lowercased()) else { return name }
        return url.deletingPathExtension().lastPathComponent
    }
}

enum FileSort: String, CaseIterable, Sendable {
    case name, modified
    var title: String { self == .name ? "Name" : "Last modified" }
}

enum FolderListing {
    static func entries(at folder: URL) throws -> [BrowserEntry] {
        let urls = try FileManager.default.contentsOfDirectory(at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey, .contentModificationDateKey], options: [.skipsHiddenFiles])
        return try urls.compactMap { url in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey, .contentModificationDateKey])
            guard values.isSymbolicLink != true, values.isPackage != true else { return nil }
            if values.isDirectory == true { return BrowserEntry(url: url, isDirectory: true, modified: values.contentModificationDate, isProject: FictionProject.isProject(url)) }
            guard values.isRegularFile == true, ["md", "markdown", "txt"].contains(url.pathExtension.lowercased()) else { return nil }
            return BrowserEntry(url: url, isDirectory: false, modified: values.contentModificationDate)
        }.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

extension FolderListing {
    static func sorted(_ entries: [BrowserEntry], by sort: FileSort, foldersFirst: Bool) -> [BrowserEntry] {
        entries.sorted { a, b in
            if foldersFirst && a.isDirectory != b.isDirectory { return a.isDirectory }
            if sort == .modified {
                let (x, y) = (a.modified ?? .distantPast, b.modified ?? .distantPast)
                if x != y { return x > y }
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// Finds folders and Markdown/text files anywhere beneath `root` whose names contain `query`.
    /// Prefix matches come first. Stops early when its task is cancelled.
    static func search(_ query: String, in root: URL, limit: Int = 200) -> [BrowserEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, let walker = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var found: [BrowserEntry] = []
        for case let url as URL in walker {
            if Task.isCancelled { return [] }
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]) else { continue }
            if values.isSymbolicLink == true { walker.skipDescendants(); continue }
            let isDirectory = values.isDirectory == true
            if !isDirectory {
                guard values.isRegularFile == true, ["md", "markdown", "txt"].contains(url.pathExtension.lowercased()) else { continue }
            }
            let title = isDirectory ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
            guard title.range(of: needle, options: options) != nil else { continue }
            found.append(BrowserEntry(url: url, isDirectory: isDirectory, modified: values.contentModificationDate, isProject: isDirectory && FictionProject.isProject(url)))
            if found.count >= limit { break }
        }
        func rank(_ entry: BrowserEntry) -> Int {
            let title = entry.isDirectory ? entry.name : entry.url.deletingPathExtension().lastPathComponent
            return title.range(of: needle, options: options.union(.anchored)) != nil ? 0 : 1
        }
        return found.sorted {
            let (x, y) = (rank($0), rank($1))
            if x != y { return x < y }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Words, ignoring stray Markdown punctuation such as "---" or "#".
    static func wordCount(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).filter { $0.contains { $0.isLetter || $0.isNumber } }.count
    }
}

struct FileWords: Sendable {
    let words: Int
    let modified: Date?
}

enum NewItemKind: Sendable {
    case file, folder
    var title: String { self == .file ? "New File" : "New Folder" }
}

enum FolderCreationError: LocalizedError {
    case invalidName, exists(String)
    var errorDescription: String? {
        switch self {
        case .invalidName: return "Names can’t be empty, start with a period, or contain “/” or “:”."
        case let .exists(name): return "“\(name)” already exists in this folder."
        }
    }
}

enum FolderCreation {
    static let fileExtensions = ["md", "markdown", "txt"]

    /// The final on-disk name, or nil if it can't be used. Files without a Markdown/text extension get ".md".
    static func fileName(for raw: String, kind: NewItemKind) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.contains(":") else { return nil }
        guard kind == .file, !fileExtensions.contains((name as NSString).pathExtension.lowercased()) else { return name }
        return name + ".md"
    }

    static func create(_ kind: NewItemKind, named raw: String, in folder: URL) throws -> URL {
        guard let name = fileName(for: raw, kind: kind) else { throw FolderCreationError.invalidName }
        let url = folder.appendingPathComponent(name, isDirectory: kind == .folder)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw FolderCreationError.exists(name) }
        switch kind {
        case .file: try Data().write(to: url, options: .withoutOverwriting)
        case .folder: try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        }
        return url
    }
}

enum FolderMoveError: LocalizedError {
    case outsideRoot, intoItself(String), exists(String)
    var errorDescription: String? {
        switch self {
        case .outsideRoot: return "Only items inside your writing folder can be moved here."
        case let .intoItself(name): return "“\(name)” can’t be moved into itself."
        case let .exists(name): return "The destination already has an item named “\(name)”."
        }
    }
}

enum FolderMove {
    /// True when `child` is `parent` or lies anywhere beneath it.
    static func isInside(_ child: URL, of parent: URL) -> Bool {
        let base = parent.standardizedFileURL.pathComponents
        let path = child.standardizedFileURL.pathComponents
        return path.count >= base.count && Array(path.prefix(base.count)) == base
    }

    /// Moves items into `folder` (all inside `root`), validating every item before touching the disk
    /// so a bad one can't leave a half-finished move. Returns the (old, new) pairs actually moved.
    static func perform(_ urls: [URL], into folder: URL, root: URL) throws -> [(from: URL, to: URL)] {
        guard isInside(folder, of: root) else { throw FolderMoveError.outsideRoot }
        var plan: [(from: URL, to: URL)] = []
        for url in urls {
            guard isInside(url, of: root), url.standardizedFileURL != root.standardizedFileURL else { throw FolderMoveError.outsideRoot }
            if url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL { continue }
            if isInside(folder, of: url) { throw FolderMoveError.intoItself(url.lastPathComponent) }
            let destination = folder.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) { throw FolderMoveError.exists(url.lastPathComponent) }
            plan.append((url, destination))
        }
        for move in plan { try coordinatedMove(from: move.from, to: move.to) }
        return plan
    }

    /// Coordinated so an open document is told its file moved and follows it.
    static func coordinatedMove(from: URL, to: URL) throws {
        var coordinationError: NSError?
        var moveError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: from, options: .forMoving,
                                                          writingItemAt: to, options: .forReplacing, error: &coordinationError) { source, destination in
            do { try FileManager.default.moveItem(at: source, to: destination) } catch { moveError = error }
        }
        if let failure = coordinationError ?? moveError { throw failure }
    }

    /// Where `url` ends up after `moves`, if it sits inside something that moved.
    static func rewrite(_ url: URL, moves: [(from: URL, to: URL)]) -> URL {
        for move in moves where isInside(url, of: move.from) {
            let relative = url.standardizedFileURL.pathComponents.dropFirst(move.from.standardizedFileURL.pathComponents.count)
            return relative.reduce(move.to) { $0.appendingPathComponent($1) }
        }
        return url
    }
}

enum FolderRename {
    /// The destination for a rename. Files keep their extension unless a supported one was typed.
    static func destination(for url: URL, isDirectory: Bool, name raw: String) throws -> URL {
        guard let clean = FolderCreation.fileName(for: raw, kind: .folder) else { throw FolderCreationError.invalidName }
        var name = clean
        if !isDirectory {
            let typed = (clean as NSString).pathExtension.lowercased()
            if !FolderCreation.fileExtensions.contains(typed) { name = url.pathExtension.isEmpty ? clean : clean + "." + url.pathExtension }
        }
        let destination = url.deletingLastPathComponent().appendingPathComponent(name, isDirectory: isDirectory)
        let onlyCaseChanged = name.lowercased() == url.lastPathComponent.lowercased()
        if destination.standardizedFileURL != url.standardizedFileURL, !onlyCaseChanged,
           FileManager.default.fileExists(atPath: destination.path) { throw FolderCreationError.exists(name) }
        return destination
    }

    /// Renames in place and returns the new location (unchanged if the name is the same).
    static func perform(_ url: URL, isDirectory: Bool, name raw: String) throws -> URL {
        let target = try destination(for: url, isDirectory: isDirectory, name: raw)
        if target.lastPathComponent == url.lastPathComponent { return url }
        try FolderMove.coordinatedMove(from: url, to: target)
        return target
    }
}

enum FolderTrashError: LocalizedError {
    case inUse(String), occupied(String)
    var errorDescription: String? {
        switch self {
        case let .inUse(name): return "“\(name)” is open. Switch to another file first."
        case let .occupied(name): return "Something named “\(name)” is already where this belongs."
        }
    }
}

struct TrashedItem: Equatable, Sendable {
    let name: String
    let original: URL
    let trashed: URL
}

/// Everything moved to the Trash in one go, so a single Undo brings all of it back.
struct TrashBatch: Equatable, Sendable {
    var items: [TrashedItem]
    var summary: String { items.count == 1 ? "“\(items[0].name)”" : "\(items.count) items" }
}

/// The words the writer chose for each color ("Draft", "Revised"…), shared by every folder.
enum ColorLabels {
    private static let key = "colorLabels"
    static func load(defaults: UserDefaults = .standard) -> [MarkColor: String] {
        guard let data = defaults.data(forKey: key), let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { pair in MarkColor(rawValue: pair.key).map { ($0, pair.value) } })
    }
    static func save(_ labels: [MarkColor: String], defaults: UserDefaults = .standard) {
        let raw = Dictionary(uniqueKeysWithValues: labels.map { ($0.key.rawValue, $0.value) })
        defaults.set(try? JSONEncoder().encode(raw), forKey: key)
    }
}

struct BrowserRow: Identifiable {
    let entry: BrowserEntry
    let depth: Int
    var id: URL { entry.url }
}

enum MarkColor: String, CaseIterable, Codable, Sendable {
    case red, orange, yellow, green, blue, purple, gray
    var name: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .red: return Color(nsColor: .systemRed)
        case .orange: return Color(nsColor: .systemOrange)
        case .yellow: return Color(nsColor: .systemYellow)
        case .green: return Color(nsColor: .systemGreen)
        case .blue: return Color(nsColor: .systemBlue)
        case .purple: return Color(nsColor: .systemPurple)
        case .gray: return Color(nsColor: .systemGray)
        }
    }
    /// A full-color swatch; menus draw template symbols monochrome, so this is a real image.
    var swatch: NSImage {
        let nsColor: NSColor = {
            switch self {
            case .red: return .systemRed
            case .orange: return .systemOrange
            case .yellow: return .systemYellow
            case .green: return .systemGreen
            case .blue: return .systemBlue
            case .purple: return .systemPurple
            case .gray: return .systemGray
            }
        }()
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            nsColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}

enum MarkFilter: Hashable, Sendable {
    case pinned
    case color(MarkColor)
}

/// Colors and pins for files and folders, stored by path relative to the writing
/// folder so they stay put if the writing folder itself is moved or re-chosen.
struct FolderMarks: Codable, Equatable, Sendable {
    var colors: [String: MarkColor] = [:]
    var pinned: Set<String> = []
    var isEmpty: Bool { colors.isEmpty && pinned.isEmpty }
    var usedColors: [MarkColor] { MarkColor.allCases.filter { color in colors.values.contains(color) } }

    static func key(for url: URL, in root: URL) -> String? {
        let base = root.standardizedFileURL.pathComponents
        let path = url.standardizedFileURL.pathComponents
        guard path.count > base.count, Array(path.prefix(base.count)) == base else { return nil }
        return path.dropFirst(base.count).joined(separator: "/")
    }
    /// Where a stored path ends up after items move (a moved folder carries everything inside it).
    static func rewrite(_ key: String, moves: [(from: URL, to: URL)], root: URL) -> String {
        for move in moves {
            guard let old = FolderMarks.key(for: move.from, in: root), let new = FolderMarks.key(for: move.to, in: root) else { continue }
            if key == old { return new }
            if key.hasPrefix(old + "/") { return new + key.dropFirst(old.count) }
        }
        return key
    }
    /// Carries colors and pins along when items (or whole folders) move.
    func remapped(moves: [(from: URL, to: URL)], root: URL) -> FolderMarks {
        var result = FolderMarks()
        for (key, color) in colors { result.colors[FolderMarks.rewrite(key, moves: moves, root: root)] = color }
        result.pinned = Set(pinned.map { FolderMarks.rewrite($0, moves: moves, root: root) })
        return result
    }
    func keys(matching filter: MarkFilter) -> [String] {
        switch filter {
        case .pinned: return pinned.sorted()
        case let .color(color): return colors.filter { $0.value == color }.map(\.key).sorted()
        }
    }
}

/// Named groups (School, Work, Hobbies…) that folders can be dragged into. Assignments are stored by
/// folder path, so a folder keeps its category when it is renamed or moved inside Sable.
struct FolderCategory: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var color: MarkColor? = nil
    var collapsed = false
}

struct FolderCategories: Codable, Equatable, Sendable {
    var list: [FolderCategory] = []
    var assignments: [String: String] = [:]
    var isEmpty: Bool { list.isEmpty }
    static let maxNameLength = 40

    static func cleanName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : String(name.prefix(maxNameLength))
    }
    func isNameTaken(_ name: String, excluding id: String? = nil) -> Bool {
        list.contains { $0.id != id && $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }
    func category(withID id: String?) -> FolderCategory? { id.flatMap { id in list.first { $0.id == id } } }
    /// The category a folder belongs to, ignoring assignments to categories that no longer exist.
    func categoryID(forKey key: String) -> String? { assignments[key].flatMap { id in list.contains { $0.id == id } ? id : nil } }
    func members(of id: String) -> [String] { assignments.filter { $0.value == id }.map(\.key).sorted() }

    @discardableResult
    mutating func add(name raw: String) -> FolderCategory? {
        guard let name = FolderCategories.cleanName(raw), !isNameTaken(name) else { return nil }
        let category = FolderCategory(id: UUID().uuidString, name: name)
        list.append(category)
        return category
    }
    @discardableResult
    mutating func rename(_ id: String, to raw: String) -> Bool {
        guard let name = FolderCategories.cleanName(raw), !isNameTaken(name, excluding: id), let index = list.firstIndex(where: { $0.id == id }) else { return false }
        list[index].name = name
        return true
    }
    /// Removing a category never touches the folders; they simply go back to the ordinary list.
    mutating func delete(_ id: String) {
        list.removeAll { $0.id == id }
        assignments = assignments.filter { $0.value != id }
    }
    mutating func move(_ id: String, by offset: Int) {
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(0, index + offset), list.count - 1)
        guard target != index else { return }
        list.insert(list.remove(at: index), at: target)
    }
    mutating func assign(key: String, to id: String?) {
        if let id, list.contains(where: { $0.id == id }) { assignments[key] = id } else { assignments[key] = nil }
    }
    mutating func setCollapsed(_ id: String, _ collapsed: Bool) {
        if let index = list.firstIndex(where: { $0.id == id }) { list[index].collapsed = collapsed }
    }
    mutating func setColor(_ id: String, _ color: MarkColor?) {
        if let index = list.firstIndex(where: { $0.id == id }) { list[index].color = color }
    }
    func remapped(moves: [(from: URL, to: URL)], root: URL) -> FolderCategories {
        var result = self
        result.assignments = [:]
        for (key, id) in assignments { result.assignments[FolderMarks.rewrite(key, moves: moves, root: root)] = id }
        return result
    }
}

enum FolderCategoriesStore {
    private static let defaultsKey = "folderCategories"
    static func load(for root: URL, defaults: UserDefaults = .standard) -> FolderCategories {
        all(defaults)[root.standardizedFileURL.path] ?? FolderCategories()
    }
    static func save(_ categories: FolderCategories, for root: URL, defaults: UserDefaults = .standard) {
        var everything = all(defaults)
        everything[root.standardizedFileURL.path] = categories.isEmpty ? nil : categories
        defaults.set(try? JSONEncoder().encode(everything), forKey: defaultsKey)
    }
    private static func all(_ defaults: UserDefaults) -> [String: FolderCategories] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: FolderCategories].self, from: data)) ?? [:]
    }
}

enum FolderMarksStore {
    private static let defaultsKey = "folderMarks"
    static func load(for root: URL, defaults: UserDefaults = .standard) -> FolderMarks {
        all(defaults)[root.standardizedFileURL.path] ?? FolderMarks()
    }
    static func save(_ marks: FolderMarks, for root: URL, defaults: UserDefaults = .standard) {
        var everything = all(defaults)
        everything[root.standardizedFileURL.path] = marks.isEmpty ? nil : marks
        defaults.set(try? JSONEncoder().encode(everything), forKey: defaultsKey)
    }
    private static func all(_ defaults: UserDefaults) -> [String: FolderMarks] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: FolderMarks].self, from: data)) ?? [:]
    }
}

@MainActor
final class FolderBrowser: ObservableObject {
    @Published private(set) var root: URL?
    @Published private(set) var current: URL? { didSet { updateProject() } }
    /// The Fiction Project being viewed, if any. Inside one, the desk shows only that project.
    @Published private(set) var projectURL: URL?
    @Published private(set) var project: FictionProject?
    /// The project's Manuscript folder: the file writers use most, so it is always pinned and red by default.
    @Published private(set) var manuscriptURL: URL?
    @Published private(set) var entries: [BrowserEntry] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var expanded: Set<URL> = []
    @Published private(set) var children: [URL: [BrowserEntry]] = [:]
    @Published private(set) var loadingFolders: Set<URL> = []
    @Published private(set) var folderErrors: [URL: String] = [:]
    @Published private(set) var marks = FolderMarks()
    @Published private(set) var categories = FolderCategories()
    @Published var filter: MarkFilter?
    /// The keyboard cursor and range anchor. Setting it on its own selects just that item.
    @Published var selection: URL? {
        didSet { if !extendingSelection { selectedURLs = selection.map { [$0] } ?? []; rangeCursor = nil } }
    }
    /// Everything currently selected: ⌘-click adds or removes, ⇧-click or ⇧-arrows extend a range.
    @Published private(set) var selectedURLs: Set<URL> = []
    private var extendingSelection = false
    private var rangeCursor: URL?
    /// What the list shows right now, in order. The view records it so ranges know what lies between two rows.
    private(set) var displayed: [BrowserEntry] = []
    @Published var renaming: URL?
    @Published private(set) var searchResults: [BrowserEntry] = []
    @Published private(set) var searching = false
    @Published private(set) var wordCounts: [URL: FileWords] = [:]
    @Published private(set) var lastTrashed: TrashBatch?
    @Published private(set) var colorLabels: [MarkColor: String] = ColorLabels.load()
    @Published var sort = FileSort(rawValue: UserDefaults.standard.string(forKey: "fileSort") ?? "") ?? .name {
        didSet { UserDefaults.standard.set(sort.rawValue, forKey: "fileSort") }
    }
    @Published var foldersFirst = UserDefaults.standard.object(forKey: "foldersFirst") as? Bool ?? true {
        didSet { UserDefaults.standard.set(foldersFirst, forKey: "foldersFirst") }
    }
    private var searchTask: Task<Void, Never>?
    private var countingWords: Set<URL> = []
    private var trashNoticeTask: Task<Void, Never>?

    var visibleEntries: [BrowserRow] {
        func ordered(_ entries: [BrowserEntry], parent: URL?) -> [BrowserEntry] {
            // The Manuscript folder keeps the order the writer gave their chapters, whatever the desk's sort says.
            if let parent, isManuscript(parent), let order = project?.chapterOrder {
                let byName = Dictionary(entries.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
                return ManuscriptStats.orderedNames(entries.map(\.name), order: order).compactMap { byName[$0] }
            }
            let sorted = FolderListing.sorted(entries, by: sort, foldersFirst: foldersFirst)
            let arranged = (marks.pinned.isEmpty && manuscriptURL == nil) ? sorted : sorted.filter(isPinned) + sorted.filter { !isPinned($0.url) }
            // Fiction projects are listed on their own, apart from ordinary folders.
            return arranged.contains(where: \.isProject) ? arranged.filter(\.isProject) + arranged.filter { !$0.isProject } : arranged
        }
        func flatten(_ entries: [BrowserEntry], depth: Int, parent: URL?) -> [BrowserRow] {
            ordered(entries, parent: parent).flatMap { entry -> [BrowserRow] in
                let row = BrowserRow(entry: entry, depth: depth)
                guard entry.isDirectory, expanded.contains(entry.url) else { return [row] }
                return [row] + flatten(children[entry.url] ?? [], depth: depth + 1, parent: entry.url)
            }
        }
        return flatten(entries, depth: 0, parent: current)
    }
    private func isPinned(_ entry: BrowserEntry) -> Bool { isPinned(entry.url) }

    /// The topmost folder the desk shows: the project when inside one, otherwise the writing folder.
    var viewRoot: URL? { projectURL ?? root }

    private func updateProject() {
        guard let root, let current, let found = FictionProject.projectRoot(containing: current, within: root) else {
            projectURL = nil; project = nil; manuscriptURL = nil
            return
        }
        projectURL = found
        project = FictionProject.load(found)
        refreshManuscript()
    }

    /// Looked up once per change rather than once per row.
    private func refreshManuscript() {
        manuscriptURL = projectURL.map { FictionProject.folder(for: .chapter, in: $0).standardizedFileURL }
    }
    /// Saves the chapter order and word goal to the project, then re-reads it.
    func setChapterOrder(_ names: [String]) throws {
        guard let projectURL else { throw FictionProjectError.notProject }
        try FictionProject.setChapterOrder(names, in: projectURL)
        project = FictionProject.load(projectURL)
    }
    func setWordGoal(_ goal: Int?) throws {
        guard let projectURL else { throw FictionProjectError.notProject }
        try FictionProject.setWordGoal(goal, in: projectURL)
        project = FictionProject.load(projectURL)
    }
    func isManuscript(_ url: URL) -> Bool {
        guard let manuscriptURL else { return false }
        return url.standardizedFileURL.path == manuscriptURL.path
    }

    /// Folders from the top of the view (the project, or the writing folder) down to the one being viewed.
    var breadcrumbs: [URL] {
        guard let top = viewRoot, let current else { return [] }
        var trail = [current]
        while let last = trail.last, last.standardizedFileURL != top.standardizedFileURL {
            let parent = last.deletingLastPathComponent()
            if parent.standardizedFileURL == last.standardizedFileURL { break }
            trail.append(parent)
        }
        return trail.reversed()
    }

    func color(of url: URL) -> MarkColor? {
        guard let root, let key = FolderMarks.key(for: url, in: root) else { return nil }
        return marks.colors[key] ?? (isManuscript(url) ? .red : nil)
    }
    func isPinned(_ url: URL) -> Bool {
        if isManuscript(url) { return true }
        guard let root, let key = FolderMarks.key(for: url, in: root) else { return false }
        return marks.pinned.contains(key)
    }
    func setColor(_ color: MarkColor?, for url: URL) {
        guard let root, let key = FolderMarks.key(for: url, in: root) else { return }
        marks.colors[key] = color
        commitMarks(root)
    }
    func togglePin(_ url: URL) {
        guard let root, let key = FolderMarks.key(for: url, in: root) else { return }
        if marks.pinned.contains(key) { marks.pinned.remove(key) } else { marks.pinned.insert(key) }
        commitMarks(root)
    }
    private func commitMarks(_ root: URL) {
        FolderMarksStore.save(marks, for: root)
        // A filter with nothing left to show would strand the user in an empty list.
        if let filter, marks.keys(matching: filter).isEmpty { self.filter = nil }
    }
    /// Marked items that still exist, folders first, for the current filter.
    func markedEntries(matching filter: MarkFilter) -> [BrowserEntry] {
        guard let root else { return [] }
        return marks.keys(matching: filter).compactMap { key in
            let url = key.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
            return BrowserEntry(url: url, isDirectory: isDirectory.boolValue, isProject: isDirectory.boolValue && FictionProject.isProject(url))
        }.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    func collapseAll() { expanded = [] }

    // MARK: Color labels
    func label(for color: MarkColor) -> String {
        let custom = colorLabels[color]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? color.name : custom
    }
    func setLabel(_ text: String, for color: MarkColor) {
        colorLabels[color] = text.isEmpty ? nil : text
        ColorLabels.save(colorLabels)
    }

    // MARK: Word counts (computed on demand, cached until the file changes)
    func loadWordCount(for entry: BrowserEntry) {
        guard !entry.isDirectory, !countingWords.contains(entry.url) else { return }
        if let cached = wordCounts[entry.url], cached.modified == entry.modified { return }
        countingWords.insert(entry.url)
        let url = entry.url, modified = entry.modified
        Task {
            let words = await Task.detached(priority: .utility) { () -> Int? in
                guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 4_000_000,
                      let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return FolderListing.wordCount(in: text)
            }.value
            countingWords.remove(url)
            if let words { wordCounts[url] = FileWords(words: words, modified: modified) }
        }
    }

    // MARK: Search (whole focused folder, including collapsed subfolders)
    func updateSearch(_ query: String) {
        searchTask?.cancel()
        guard let current, !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []; searching = false
            return
        }
        searching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            let results = await Task.detached(priority: .userInitiated) { FolderListing.search(query, in: current) }.value
            guard !Task.isCancelled else { return }
            searchResults = results
            searching = false
        }
    }

    // MARK: Rename
    @discardableResult
    func rename(_ entry: BrowserEntry, to name: String) throws -> URL {
        let target = try FolderRename.perform(entry.url, isDirectory: entry.isDirectory, name: name)
        guard target != entry.url, let root else { return target }
        let moves = [(from: entry.url, to: target)]
        marks = marks.remapped(moves: moves, root: root)
        FolderMarksStore.save(marks, for: root)
        categories = categories.remapped(moves: moves, root: root)
        FolderCategoriesStore.save(categories, for: root)
        expanded = Set(expanded.map { FolderMove.rewrite($0, moves: moves) })
        if selection == entry.url { selection = target }
        // A renamed chapter keeps its place in the manuscript.
        if projectURL != nil, isManuscript(entry.url.deletingLastPathComponent()), var order = project?.chapterOrder,
           let index = order.firstIndex(of: entry.name) {
            order[index] = target.lastPathComponent
            try? setChapterOrder(order)
        }
        reload()
        return target
    }

    // MARK: Selection
    func recordDisplayed(_ entries: [BrowserEntry]) { displayed = entries }
    var selectedEntries: [BrowserEntry] { displayed.filter { selectedURLs.contains($0.url) } }

    /// A click with the modifier keys held: ⌘ toggles one item, ⇧ selects the range from the anchor, plain selects just it.
    func click(_ url: URL, command: Bool, shift: Bool) {
        if shift, selection != nil { extendSelection(to: url); return }
        guard command else { selection = url; return }
        extendingSelection = true
        defer { extendingSelection = false }
        if selectedURLs.contains(url) {
            selectedURLs.remove(url)
            if selection == url { selection = selectedURLs.first }
        } else {
            selectedURLs.insert(url)
            selection = url
        }
        rangeCursor = nil
    }
    /// Dragging any item of a multi-item selection moves the whole selection, not just the one under the pointer.
    func dragSet(for urls: [URL]) -> [URL] {
        guard urls.count == 1, selectedURLs.count > 1, selectedURLs.contains(urls[0]) else { return urls }
        let chosen = displayed.map(\.url).filter { selectedURLs.contains($0) }
        // An item inside a selected folder travels with the folder.
        return chosen.filter { url in !chosen.contains { $0 != url && FolderMove.isInside(url, of: $0) } }
    }
    func extendSelection(to url: URL) {
        guard let end = displayed.firstIndex(where: { $0.url == url }) else { return }
        extendingSelection = true
        defer { extendingSelection = false }
        if selection == nil { selection = url }
        guard let start = displayed.firstIndex(where: { $0.url == selection }) else { return }
        selectedURLs = Set(displayed[min(start, end)...max(start, end)].map(\.url))
        rangeCursor = url
    }
    /// ⇧-arrow: grow or shrink the range from its anchor one row at a time.
    func extendSelection(by offset: Int) {
        guard !displayed.isEmpty else { return }
        let from = (rangeCursor ?? selection).flatMap { url in displayed.firstIndex { $0.url == url } } ?? (offset > 0 ? -1 : displayed.count)
        extendSelection(to: displayed[min(max(0, from + offset), displayed.count - 1)].url)
    }
    func selectAllDisplayed() {
        extendingSelection = true
        defer { extendingSelection = false }
        selectedURLs = Set(displayed.map(\.url))
        if selection == nil { selection = displayed.first?.url }
    }
    /// What "Move to Trash" should act on: the whole selection if the item is part of it, otherwise just the item.
    func trashTargets(for entry: BrowserEntry) -> [BrowserEntry] {
        selectedURLs.contains(entry.url) && selectedURLs.count > 1 ? selectedEntries : [entry]
    }

    // MARK: Trash (with a short-lived undo)
    func trash(_ entry: BrowserEntry, protecting inUse: [URL]) throws { try trash([entry], protecting: inUse) }

    /// Moves everything to the Trash at once. Items already inside another selected folder ride along with it.
    func trash(_ entries: [BrowserEntry], protecting inUse: [URL]) throws {
        let top = entries.filter { entry in !entries.contains { $0.url != entry.url && FolderMove.isInside(entry.url, of: $0.url) } }
        if let blocked = top.first(where: { entry in inUse.contains { FolderMove.isInside($0, of: entry.url) } }) {
            throw FolderTrashError.inUse(blocked.displayName)
        }
        var done: [TrashedItem] = []
        var failure: Error?
        for entry in top {
            do {
                var resulting: NSURL?
                try FileManager.default.trashItem(at: entry.url, resultingItemURL: &resulting)
                done.append(TrashedItem(name: entry.displayName, original: entry.url, trashed: (resulting as URL?) ?? entry.url))
            } catch { failure = error; break }
        }
        if !done.isEmpty {
            lastTrashed = TrashBatch(items: done)
            let gone = done.map(\.original)
            expanded = expanded.filter { open in !gone.contains { FolderMove.isInside(open, of: $0) } }
            selectedURLs = selectedURLs.filter { url in !gone.contains { FolderMove.isInside(url, of: $0) } }
            if let selection, gone.contains(where: { FolderMove.isInside(selection, of: $0) }) { self.selection = nil }
            reload()
            trashNoticeTask?.cancel()
            trashNoticeTask = Task {
                try? await Task.sleep(for: .seconds(12))
                if !Task.isCancelled { lastTrashed = nil }
            }
        }
        if let failure { throw failure }
    }

    /// Restores everything from the last batch. Anything whose place has been taken stays in the Trash and is reported.
    func undoTrash() throws {
        guard let batch = lastTrashed else { return }
        var remaining: [TrashedItem] = []
        for item in batch.items {
            if FileManager.default.fileExists(atPath: item.original.path) { remaining.append(item); continue }
            do { try FolderMove.coordinatedMove(from: item.trashed, to: item.original) } catch { remaining.append(item) }
        }
        lastTrashed = remaining.isEmpty ? nil : TrashBatch(items: remaining)
        reload()
        if let first = remaining.first { throw FolderTrashError.occupied(remaining.count == 1 ? first.name : "\(remaining.count) items") }
    }
    func dismissTrashNotice() { lastTrashed = nil }

    // MARK: Chapters (reordering from the Files tab uses the same saved order as the Manuscript tab)
    func isChapter(_ url: URL) -> Bool {
        guard isManuscript(url.deletingLastPathComponent()) else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
    /// The Manuscript folder's entries in the order the writer arranged them.
    func chapterNames() -> [String] {
        guard let manuscriptURL else { return [] }
        let names = ((try? FolderListing.entries(at: manuscriptURL)) ?? []).map(\.name)
        return ManuscriptStats.orderedNames(names, order: project?.chapterOrder)
    }
    func reorderChapter(_ url: URL, onto target: URL) throws {
        let names = chapterNames()
        let order = ManuscriptStats.moved(names, url.lastPathComponent, to: target.lastPathComponent)
        guard order != names else { return }
        try setChapterOrder(order)
        reload()
    }
    func moveChapter(_ url: URL, to index: Int) throws {
        let names = chapterNames()
        guard !names.isEmpty else { return }
        try reorderChapter(url, onto: manuscriptURL!.appendingPathComponent(names[min(max(0, index), names.count - 1)]))
    }

    /// Creates a file or folder and refreshes whichever list is showing it.
    /// Re-reads the current folder and any open subfolders in place, without blanking the list.
    func reload() {
        guard let current else { return }
        requestID = UUID()
        let request = requestID
        Task {
            let result = await Task.detached(priority: .userInitiated) { Result { try FolderListing.entries(at: current) } }.value
            guard request == requestID else { return }
            switch result {
            case let .success(items):
                entries = items
                refreshManuscript()
                for folder in expanded { loadChildren(folder) }
            case let .failure(failure): error = failure.localizedDescription
            }
        }
    }

    func move(_ urls: [URL], into folder: URL) throws {
        guard let root else { throw FolderMoveError.outsideRoot }
        let moved = try FolderMove.perform(urls, into: folder, root: root)
        guard !moved.isEmpty else { return }
        marks = marks.remapped(moves: moved, root: root)
        FolderMarksStore.save(marks, for: root)
        categories = categories.remapped(moves: moved, root: root)
        FolderCategoriesStore.save(categories, for: root)
        expanded = Set(expanded.map { FolderMove.rewrite($0, moves: moved) })
        expanded.insert(folder)
        if folder.standardizedFileURL != current?.standardizedFileURL { loadChildren(folder) }
        reload()
    }

    @discardableResult
    func create(_ kind: NewItemKind, named name: String, in folder: URL) throws -> URL {
        let url = try FolderCreation.create(kind, named: name, in: folder)
        if folder.standardizedFileURL != current?.standardizedFileURL { expanded.insert(folder); loadChildren(folder) }
        reload()
        return url
    }
    func toggle(_ url: URL) {
        if expanded.contains(url) { expanded.remove(url) }
        else { expanded.insert(url); loadChildren(url) }
    }
    private func loadChildren(_ url: URL) {
        let request = requestID
        loadingFolders.insert(url)
        folderErrors[url] = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) { Result { try FolderListing.entries(at: url) } }.value
            guard request == requestID else { return }
            loadingFolders.remove(url)
            switch result { case let .success(items): children[url] = items; case let .failure(error): folderErrors[url] = error.localizedDescription }
        }
    }
    private var scoped = false
    private var requestID = UUID()

    init() {
        if let bookmark = UserDefaults.standard.data(forKey: "writingFolder") {
            var stale = false
            do {
                let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
                scoped = url.startAccessingSecurityScopedResource()
                root = url
                current = url
                marks = FolderMarksStore.load(for: url)
                categories = FolderCategoriesStore.load(for: url)
                if stale, let fresh = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(fresh, forKey: "writingFolder")
                }
            } catch { self.error = "Choose the folder again: \(error.localizedDescription)" }
        }
    }
    func choose(_ url: URL) throws {
        let newScope = url.startAccessingSecurityScopedResource()
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            if scoped { root?.stopAccessingSecurityScopedResource() }
            scoped = newScope
            root = url
            current = url
            marks = FolderMarksStore.load(for: url)
            categories = FolderCategoriesStore.load(for: url)
            filter = nil
            expanded = []; children = [:]
            UserDefaults.standard.set(bookmark, forKey: "writingFolder")
            refresh()
        } catch {
            if newScope { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }
    func navigate(_ url: URL, leavingProject: Bool = false) {
        guard let root, FolderMove.isInside(url, of: root) else { return }
        // Inside a project the desk shows only that project; leaving is always an explicit choice.
        if let projectURL, !leavingProject, !FolderMove.isInside(url, of: projectURL) { return }
        current = url
        expanded = []; children = [:]
        refresh()
    }
    func up() {
        guard let current, current.standardizedFileURL != viewRoot?.standardizedFileURL else { return }
        navigate(current.deletingLastPathComponent())
    }

    // MARK: Categories
    /// True while the listing is the writing folder itself, where categories can be created.
    var canManageCategories: Bool {
        guard projectURL == nil, let root, let current else { return false }
        return current.standardizedFileURL.path == root.standardizedFileURL.path
    }
    func categoryID(of entry: BrowserEntry) -> String? {
        guard entry.isDirectory, !entry.isProject, let root, let key = FolderMarks.key(for: entry.url, in: root) else { return nil }
        return categories.categoryID(forKey: key)
    }
    private func commitCategories() {
        guard let root else { return }
        FolderCategoriesStore.save(categories, for: root)
    }
    @discardableResult
    func addCategory(named name: String) -> Bool {
        guard categories.add(name: name) != nil else { return false }
        commitCategories()
        return true
    }
    @discardableResult
    func renameCategory(_ id: String, to name: String) -> Bool {
        guard categories.rename(id, to: name) else { return false }
        commitCategories()
        return true
    }
    func deleteCategory(_ id: String) { categories.delete(id); commitCategories() }
    func moveCategory(_ id: String, by offset: Int) { categories.move(id, by: offset); commitCategories() }
    func setCategoryColor(_ id: String, _ color: MarkColor?) { categories.setColor(id, color); commitCategories() }
    func toggleCategory(_ id: String) {
        guard let category = categories.category(withID: id) else { return }
        categories.setCollapsed(id, !category.collapsed)
        commitCategories()
    }
    /// Files a folder under a category (or back to the ordinary list with nil).
    func assign(_ url: URL, to id: String?) {
        guard let root, let key = FolderMarks.key(for: url, in: root) else { return }
        categories.assign(key: key, to: id)
        commitCategories()
    }

    // MARK: Fiction Projects
    var canLeaveProject: Bool {
        guard let projectURL, let root else { return false }
        return projectURL.standardizedFileURL != root.standardizedFileURL
    }
    func leaveProject() {
        guard canLeaveProject, let projectURL else { return }
        navigate(projectURL.deletingLastPathComponent(), leavingProject: true)
    }
    /// Follows the open document: opening a file that belongs to a project brings the desk into that project.
    func enterProject(containing file: URL) {
        guard let root, let found = FictionProject.projectRoot(containing: file, within: root),
              found.standardizedFileURL != projectURL?.standardizedFileURL else { return }
        navigate(found, leavingProject: true)
    }
    @discardableResult
    func createProject(named name: String, starterFiles: Bool) throws -> URL {
        guard let current, projectURL == nil else { throw FictionProjectError.alreadyProject }
        let url = try FictionProject.create(named: name, in: current, starterFiles: starterFiles)
        navigate(url)
        return url
    }
    func adoptAsProject(_ url: URL, addStandardFolders: Bool) throws {
        try FictionProject.adopt(url, addStandardFolders: addStandardFolders)
        updateProject()
        reload()
    }
    func convertToRegularFolder(_ url: URL) throws {
        try FictionProject.convertToRegularFolder(url)
        updateProject()
        reload()
    }
    /// What the "+" on a project folder adds: chapters for Manuscript, and characters, locations, or world notes
    /// for their folders (including folders inside them, like Characters/Villains).
    func projectItem(forFolder url: URL) -> NewProjectItem? {
        guard let projectURL, FolderMove.isInside(url, of: projectURL), url.standardizedFileURL.path != projectURL.standardizedFileURL.path else { return nil }
        if isManuscript(url) { return .chapter }
        switch CardParsing.kindByLocation(url.appendingPathComponent("x.md"), projectRoot: projectURL) {
        case .character?: return .character
        case .location?: return .location
        case .lore?: return .lore
        case nil: return nil
        }
    }

    @discardableResult
    func createProjectItem(_ item: NewProjectItem, named name: String, in folder: URL? = nil) throws -> URL {
        guard let projectURL else { throw FictionProjectError.notProject }
        let url = try FictionProject.createItem(item, named: name, in: projectURL, folder: folder)
        let folder = url.deletingLastPathComponent()
        if folder.standardizedFileURL != current?.standardizedFileURL { expanded.insert(folder); loadChildren(folder) }
        reload()
        return url
    }
    /// The card type a file would show as, judging by where it lives in the project.
    func cardKind(of entry: BrowserEntry) -> CardKind? {
        guard let projectURL, !entry.isDirectory else { return nil }
        return CardParsing.isCandidate(entry.url, projectRoot: projectURL) ? CardParsing.kindByLocation(entry.url, projectRoot: projectURL) : nil
    }
    func refresh() {
        guard let current else { return }
        requestID = UUID()
        let request = requestID
        loading = true
        error = nil
        entries = []
        children = [:]; loadingFolders = []; folderErrors = [:]
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try FolderListing.entries(at: current) }
            }.value
            guard request == requestID else { return }
            loading = false
            switch result {
            case let .success(items):
                entries = items
                refreshManuscript()
                for folder in expanded { loadChildren(folder) }
            case let .failure(failure): error = failure.localizedDescription
            }
        }
    }
}

private enum SectionKind {
    case projects, folders, files, other
    case category(FolderCategory)
}
private struct SectionHeader: Identifiable {
    let kind: SectionKind
    let title: String
    let count: Int
    var id: String {
        switch kind {
        case .projects: return "projects"
        case .folders: return "folders"
        case .files: return "files"
        case .other: return "other"
        case let .category(category): return "category:\(category.id)"
        }
    }
}
private enum TreeItem: Identifiable {
    case header(SectionHeader)
    case row(BrowserRow)
    var id: String {
        switch self {
        case let .header(header): return "header:" + header.id
        case let .row(row): return "row:" + row.entry.url.absoluteString
        }
    }
    var row: BrowserRow? { if case let .row(row) = self { return row } else { return nil } }
}

struct FolderBrowserSection: View {
    @EnvironmentObject private var browser: FolderBrowser
    let currentURL: URL?
    let search: String
    let chooseFolder: () -> Void
    let switchFile: (URL) -> Void
    let showParallel: (URL) -> Void
    var parallelURL: URL? = nil
    var showCard: (URL) -> Void = { _ in }
    /// Called before the open document's file is trashed, so the editor can let go of it first.
    var releaseCurrentDocument: () -> Void = {}
    @State private var pendingTrash: [BrowserEntry] = []
    @State private var showNewItem = false
    @State private var newKind = NewItemKind.file
    @State private var newProjectItem: NewProjectItem?
    @State private var showNewProject = false
    @State private var projectName = ""
    @State private var projectStarter = true
    @State private var convertTarget: URL?
    @State private var showCategoryAlert = false
    @State private var categoryEditing: FolderCategory?
    @State private var categoryName = ""
    @State private var targetedHeader: String?
    @State private var adoptTarget: URL?
    @State private var newFolder: URL?
    @State private var newName = ""
    @State private var problem: String?
    @FocusState private var listFocused: Bool

    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var searching: Bool { !query.isEmpty }
    /// Search and color filters show a flat list with folder paths; otherwise the expandable tree.
    private var flat: Bool { searching || browser.filter != nil }

    private var rows: [BrowserRow] {
        if searching { return browser.searchResults.map { BrowserRow(entry: $0, depth: 0) } }
        if let filter = browser.filter { return browser.markedEntries(matching: filter).map { BrowserRow(entry: $0, depth: 0) } }
        return browser.visibleEntries
    }

    var body: some View { projectDialogs(creationDialogs(content)) }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let current = browser.current {
                if let project = browser.project, let projectURL = browser.projectURL { projectHeader(project, projectURL) }
                breadcrumbBar(current)
                if !browser.marks.isEmpty { filterBar }
                let items = flat ? rows.map { TreeItem.row($0) } : treeItems()
                let shown = items.compactMap(\.row)
                let _ = browser.recordDisplayed(shown.map(\.entry))
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        switch item {
                        case let .header(header): headerView(header, first: index == 0)
                        case let .row(row):
                            BrowserRowView(entry: row.entry, depth: row.depth, currentURL: currentURL, showPath: flat,
                                           parallelURL: parallelURL, switchFile: switchFile, showParallel: showParallel,
                                           promptNew: { promptNew($0, in: $1) }, dropOnRow: dropOnRow, rename: rename, trash: requestTrash,
                                           showCard: showCard, convertProject: { convertTarget = $0 }, adoptFolder: { adoptTarget = $0 },
                                           newCategory: { promptCategory(nil) }, addToFolder: addToFolder)
                                .id(row.entry.url)
                        }
                    }
                }
                .focusable().focused($listFocused).focusEffectDisabled()
                .onKeyPress(phases: .down) { handleKey($0, rows: shown) }
                .onChange(of: browser.selection) { _, new in if new != nil { listFocused = true } }
                emptyState(shownCount: shown.count)
                if let item = browser.lastTrashed { trashNotice(item) }
                if !browser.folderErrors.isEmpty { Text("A subfolder could not be read. Refresh or choose the folder again.").font(.caption).foregroundStyle(.secondary) }
            } else {
                Button("Choose Writing Folder…", action: chooseFolder).font(.caption)
                Text("Browse Markdown files and subfolders. Click a file to switch to it.").font(.caption).foregroundStyle(.secondary)
            }
            if let error = browser.error { Text(error).font(.caption).foregroundStyle(.secondary) }
        }
        .onAppear { if browser.entries.isEmpty { browser.refresh() } }
        .onChange(of: search) { _, value in browser.updateSearch(value) }
        .onChange(of: browser.current) { _, _ in browser.updateSearch(search) }
    }

    private func creationDialogs<V: View>(_ view: V) -> some View {
        view
        .alert(newProjectItem?.title ?? newKind.title, isPresented: $showNewItem) {
            TextField(newProjectItem?.prompt ?? (newKind == .file ? "Untitled.md" : "Folder name"), text: $newName)
            Button("Create") { createItem() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("In “\(newFolder?.lastPathComponent ?? "")”") }
        .alert(categoryEditing == nil ? "New Category" : "Rename Category", isPresented: $showCategoryAlert) {
            TextField("School, Work, Hobbies…", text: $categoryName)
            Button(categoryEditing == nil ? "Create" : "Rename") { saveCategory() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Categories group your folders. Drag a folder onto a category to file it there.") }
        .sheet(isPresented: $showNewProject) {
            NewProjectSheet(name: $projectName, starter: $projectStarter, location: browser.current?.lastPathComponent ?? "your writing folder",
                            create: createProject, cancel: { showNewProject = false })
        }
    }

    private func projectDialogs<V: View>(_ view: V) -> some View {
        view
        .confirmationDialog("Convert to a regular folder?", isPresented: Binding(get: { convertTarget != nil }, set: { if !$0 { convertTarget = nil } }), titleVisibility: .visible) {
            Button("Convert to Regular Folder") { convertProject() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Every file and folder stays exactly as it is, and other editors keep working. Sable just stops treating it as a Fiction Project, so the project-only view and character cards go away.") }
        .confirmationDialog("Make this a Fiction Project?", isPresented: Binding(get: { adoptTarget != nil }, set: { if !$0 { adoptTarget = nil } }), titleVisibility: .visible) {
            Button("Add Standard Folders") { adopt(addFolders: true) }
            Button("Keep My Folders As They Are") { adopt(addFolders: false) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Nothing is moved or changed. Standard folders (Manuscript, Characters, Locations, World, Notes, Images) are only added if you choose to, and existing ones are reused. You can convert it back at any time.") }
        .confirmationDialog(trashTitle, isPresented: Binding(get: { !pendingTrash.isEmpty }, set: { if !$0 { pendingTrash = [] } }), titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) { performTrash(pendingTrash) }
            Button("Cancel", role: .cancel) { pendingTrash = [] }
        } message: { Text(trashMessage) }
        .alert("That didn’t work", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") { problem = nil }
        } message: { Text(problem ?? "") }
    }

    // MARK: Header pieces

    // MARK: Sections: fiction projects, your own categories, then everything else

    private enum RowGroup { case folder, file, other }
    private func group(of entry: BrowserEntry) -> RowGroup {
        guard browser.foldersFirst else { return .other }
        return entry.isDirectory ? .folder : .file
    }

    /// A top-level entry together with any rows expanded beneath it.
    private struct Block { var rows: [BrowserRow]; var entry: BrowserEntry { rows[0].entry } }

    /// Builds the list. Headings only appear once a folder holds a project or you have made categories,
    /// so a plain library stays as quiet as ever.
    private func treeItems() -> [TreeItem] {
        let all = browser.visibleEntries
        var blocks: [Block] = []
        for row in all {
            if row.depth == 0 || blocks.isEmpty { blocks.append(Block(rows: [row])) } else { blocks[blocks.count - 1].rows.append(row) }
        }
        let hasProjects = blocks.contains { $0.entry.isProject }
        let categorized = blocks.contains { browser.categoryID(of: $0.entry) != nil }
        let useCategories = browser.projectURL == nil && (browser.canManageCategories ? !browser.categories.isEmpty : categorized)
        guard hasProjects || useCategories else { return all.map { .row($0) } }

        var items: [TreeItem] = []
        func add(_ chosen: [Block]) { for block in chosen { items += block.rows.map { .row($0) } } }
        let projects = blocks.filter { $0.entry.isProject }
        if !projects.isEmpty {
            items.append(.header(SectionHeader(kind: .projects, title: "Fiction Projects", count: projects.count)))
            add(projects)
        }
        if useCategories {
            for category in browser.categories.list {
                let members = blocks.filter { !$0.entry.isProject && browser.categoryID(of: $0.entry) == category.id }
                // Empty categories stay visible in the writing folder so there's somewhere to drop folders.
                if members.isEmpty && !browser.canManageCategories { continue }
                items.append(.header(SectionHeader(kind: .category(category), title: category.name, count: members.count)))
                if !category.collapsed { add(members) }
            }
        }
        let rest = blocks.filter { !$0.entry.isProject && (!useCategories || browser.categoryID(of: $0.entry) == nil) }
        var previous: RowGroup?
        for block in rest {
            let current = group(of: block.entry)
            if current != previous {
                let count = rest.filter { group(of: $0.entry) == current }.count
                switch current {
                case .folder: items.append(.header(SectionHeader(kind: .folders, title: "Folders", count: count)))
                case .file: items.append(.header(SectionHeader(kind: .files, title: "Files", count: count)))
                case .other: items.append(.header(SectionHeader(kind: .other, title: "Folders & Files", count: count)))
                }
                previous = current
            }
            items += block.rows.map { .row($0) }
        }
        return items
    }

    @ViewBuilder
    private func headerView(_ header: SectionHeader, first: Bool) -> some View {
        switch header.kind {
        case let .category(category): categoryHeader(category, count: header.count, first: first)
        case .folders, .other:
            plainHeader(header, first: first)
                // Dropping a folder here takes it out of its category.
                .dropDestination(for: URL.self) { urls, _ in dropOnHeader(urls, category: nil) } isTargeted: { setTargeted(header.id, $0) }
                .background(targetedHeader == header.id ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6))
        case .projects, .files: plainHeader(header, first: first)
        }
    }

    private func plainHeader(_ header: SectionHeader, first: Bool) -> some View {
        Text(header.title.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(1.1).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.top, first ? 2 : 12).padding(.bottom, 3)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }

    private func categoryHeader(_ category: FolderCategory, count: Int, first: Bool) -> some View {
        Button { withAnimation(.smooth(duration: 0.2)) { browser.toggleCategory(category.id) } } label: {
            HStack(spacing: 6) {
                Image(systemName: category.collapsed ? "chevron.right" : "chevron.down").font(.system(size: 8, weight: .bold)).frame(width: 10)
                if let color = category.color { Circle().fill(color.color).frame(width: 7, height: 7) }
                Text(category.name.uppercased()).lineLimit(1)
                Text("\(count)").foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .font(.system(size: 9.5, weight: .semibold)).tracking(1.1).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 5).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, first ? 2 : 10)
        .background(targetedHeader == "category:\(category.id)" ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .dropDestination(for: URL.self) { urls, _ in dropOnHeader(urls, category: category.id) } isTargeted: { setTargeted("category:\(category.id)", $0) }
        .help("Drag folders here to file them under \(category.name)")
        .contextMenu {
            Button("Rename…") { promptCategory(category) }
            Menu("Color") {
                ForEach(MarkColor.allCases, id: \.self) { color in
                    Button { browser.setCategoryColor(category.id, color) } label: {
                        Label { Text(browser.label(for: color) + (category.color == color ? " ✓" : "")) } icon: { Image(nsImage: color.swatch) }
                    }
                }
                if category.color != nil { Divider(); Button("No Color") { browser.setCategoryColor(category.id, nil) } }
            }
            Divider()
            Button("Move Up") { browser.moveCategory(category.id, by: -1) }.disabled(browser.categories.list.first?.id == category.id)
            Button("Move Down") { browser.moveCategory(category.id, by: 1) }.disabled(browser.categories.list.last?.id == category.id)
            Divider()
            Button("Delete Category", role: .destructive) { browser.deleteCategory(category.id) }
        }
    }

    private func setTargeted(_ id: String, _ on: Bool) {
        if on { targetedHeader = id } else if targetedHeader == id { targetedHeader = nil }
    }

    /// Only folders shown in this very list can be filed; anything else is refused with a hint.
    private func dropOnHeader(_ urls: [URL], category: String?) -> Bool {
        guard let current = browser.current else { return false }
        var filed = false
        for url in urls {
            var isDirectory: ObjCBool = false
            guard url.deletingLastPathComponent().standardizedFileURL.path == current.standardizedFileURL.path,
                  FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
                  !FictionProject.isProject(url) else { continue }
            browser.assign(url, to: category)
            filed = true
        }
        if !filed { problem = "Drag folders from this list onto a category to file them there." }
        return filed
    }

    private func promptCategory(_ editing: FolderCategory?) {
        categoryEditing = editing
        categoryName = editing?.name ?? ""
        showCategoryAlert = true
    }

    private func saveCategory() {
        let ok = categoryEditing.map { browser.renameCategory($0.id, to: categoryName) } ?? browser.addCategory(named: categoryName)
        if !ok { problem = "A category needs a name that isn’t already in use." }
    }

    private func projectHeader(_ project: FictionProject, _ url: URL) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "books.vertical.fill").font(.system(size: 15)).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(project.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text("FICTION PROJECT").font(.system(size: 9, weight: .medium)).tracking(1.2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if browser.canLeaveProject {
                Button { browser.leaveProject() } label: {
                    Label("Leave", systemImage: "rectangle.portrait.and.arrow.right").font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered).controlSize(.small)
                .help("Leave this project and see all your files").accessibilityLabel("Leave project")
            }
            Menu {
                if browser.canLeaveProject { Button("Leave Project") { browser.leaveProject() } }
                Button("Start Here Guide") { openGuide(in: url) }
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Divider()
                Button("Convert to Regular Folder…") { convertTarget = url }
            } label: { Image(systemName: "ellipsis").frame(width: 22, height: 22) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Project options")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
    }

    /// Focusing a folder narrows the desk to it; the trail shows the way back out.
    private func breadcrumbBar(_ current: URL) -> some View {
        HStack(spacing: 6) {
            Button { browser.up() } label: { Image(systemName: "arrow.up") }
                .disabled(current == browser.root).accessibilityLabel("Parent folder")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(browser.breadcrumbs.enumerated()), id: \.element) { index, url in
                        if index > 0 { Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary) }
                        BreadcrumbChip(url: url, isCurrent: url == current, navigate: { browser.navigate(url) }, drop: move)
                    }
                }
            }
            Spacer(minLength: 0)
            if browser.loading || browser.searching { ProgressView().controlSize(.small) }
            Menu {
                if browser.projectURL != nil {
                    ForEach(NewProjectItem.allCases, id: \.self) { item in Button(item.title + "…") { promptItem(item) } }
                    Divider()
                }
                Button("New File…") { promptNew(.file, in: browser.current) }
                Button("New Folder…") { promptNew(.folder, in: browser.current) }
                if browser.projectURL == nil {
                    Divider()
                    Button("New Fiction Project…") { projectName = ""; showNewProject = true }
                    if browser.canManageCategories { Button("New Category…") { promptCategory(nil) } }
                }
            } label: { Image(systemName: "plus") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Create a file or folder in \(current.lastPathComponent)").accessibilityLabel("New file or folder")
            Menu {
                Button("Choose Writing Folder…", action: chooseFolder)
                Button("Refresh") { browser.refresh() }
                Button("Collapse All Folders") { browser.collapseAll() }.disabled(browser.expanded.isEmpty)
                if browser.projectURL == nil, let root = browser.root { Button("Back to \(root.lastPathComponent)") { browser.navigate(root) } }
                if browser.canLeaveProject { Button("Leave Project") { browser.leaveProject() } }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("File browser menu")
        }.buttonStyle(.plain).padding(.vertical, 4)
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            FilterChip(active: browser.filter == nil, help: "Show all files") { browser.filter = nil } label: {
                Text("All").font(.system(size: 11))
            }
            if !browser.marks.pinned.isEmpty {
                FilterChip(active: browser.filter == .pinned, help: "Show pinned items") { browser.filter = .pinned } label: {
                    Image(systemName: "pin.fill").font(.system(size: 10))
                }
            }
            ForEach(browser.marks.usedColors, id: \.self) { color in
                let active = browser.filter == .color(color)
                FilterChip(active: active, help: "Show only “\(browser.label(for: color))”") { browser.filter = .color(color) } label: {
                    HStack(spacing: 4) {
                        Circle().fill(color.color).frame(width: 9, height: 9)
                        if active { Text(browser.label(for: color)).font(.system(size: 11)).lineLimit(1) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func emptyState(shownCount: Int) -> some View {
        if searching && !browser.searching && shownCount == 0 {
            Text("Nothing in “\(browser.current?.lastPathComponent ?? "this folder")” matches “\(query)”.").font(.caption).foregroundStyle(.secondary)
        } else if browser.filter != nil && shownCount == 0 {
            Text("Nothing matches.").font(.caption).foregroundStyle(.secondary)
        } else if !flat && !browser.loading && browser.entries.isEmpty && browser.error == nil {
            Text("Nothing here yet. Use + to add a file or folder.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func trashNotice(_ batch: TrashBatch) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "trash").foregroundStyle(.secondary)
            Text("Moved \(batch.summary) to the Trash").lineLimit(1)
            Spacer(minLength: 0)
            Button("Undo") { do { try browser.undoTrash() } catch { problem = error.localizedDescription } }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
            Button { browser.dismissTrashNotice() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .font(.system(size: 11)).padding(8)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Actions

    private func promptItem(_ item: NewProjectItem, in folder: URL? = nil) {
        guard let projectURL = browser.projectURL else { return }
        newProjectItem = item
        newFolder = folder ?? FictionProject.folder(for: item, in: projectURL)
        newName = item == .chapter ? FictionProject.nextChapterName(in: projectURL) : ""
        showNewItem = true
    }

    /// The "+" on a project folder. A chapter is added straight away (numbered for you) and opened;
    /// the others ask for a name first.
    private func addToFolder(_ folder: URL, _ item: NewProjectItem) {
        guard item == .chapter, let projectURL = browser.projectURL else { promptItem(item, in: folder); return }
        do {
            let url = try browser.createProjectItem(.chapter, named: FictionProject.nextChapterName(in: projectURL), in: folder)
            switchFile(url)
        } catch { problem = error.localizedDescription }
    }

    /// Opens the project's Start Here note, writing it first if it was deleted.
    private func openGuide(in project: URL) {
        do {
            let guide = try FictionProject.ensureGuide(in: project)
            browser.reload()
            switchFile(guide)
        } catch { problem = error.localizedDescription }
    }

    private func createProject() {
        do {
            let url = try browser.createProject(named: projectName, starterFiles: projectStarter)
            showNewProject = false
            // A new project opens on its Start Here note, which explains how everything works.
            switchFile(FictionProject.guideURL(in: url))
        } catch { showNewProject = false; problem = error.localizedDescription }
    }

    private func convertProject() {
        guard let url = convertTarget else { return }
        do { try browser.convertToRegularFolder(url) } catch { problem = error.localizedDescription }
        convertTarget = nil
    }

    private func adopt(addFolders: Bool) {
        guard let url = adoptTarget else { return }
        do { try browser.adoptAsProject(url, addStandardFolders: addFolders); browser.navigate(url) } catch { problem = error.localizedDescription }
        adoptTarget = nil
    }

    private func promptNew(_ kind: NewItemKind, in folder: URL?) {
        guard let folder else { return }
        newProjectItem = nil
        newKind = kind
        newFolder = folder
        newName = ""
        showNewItem = true
    }

    private func createItem() {
        guard let folder = newFolder else { return }
        do {
            if let item = newProjectItem {
                let url = try browser.createProjectItem(item, named: newName, in: newFolder)
                switchFile(url)
            } else {
                let url = try browser.create(newKind, named: newName, in: folder)
                if newKind == .file { switchFile(url) }
            }
        } catch { problem = error.localizedDescription }
    }

    /// The parallel document is off limits while it's open beside the draft.
    private func parallelGuard(_ urls: [URL], action: String) -> Bool {
        guard let parallelURL, urls.contains(where: { FolderMove.isInside(parallelURL, of: $0) }) else { return true }
        problem = "Close the parallel document before \(action) it."
        return false
    }

    private func move(_ dropped: [URL], into folder: URL) {
        let urls = browser.dragSet(for: dropped)
        guard parallelGuard(urls, action: "moving") else { return }
        do { try browser.move(urls, into: folder) } catch { problem = error.localizedDescription }
    }

    private func rename(_ entry: BrowserEntry, to name: String) {
        defer { browser.renaming = nil }
        guard parallelGuard([entry.url], action: "renaming") else { return }
        do { try browser.rename(entry, to: name) } catch { problem = error.localizedDescription }
    }

    private func includesOpenFile(_ entries: [BrowserEntry]) -> Bool {
        guard let currentURL else { return false }
        return entries.contains { FolderMove.isInside(currentURL, of: $0.url) }
    }

    /// One file goes straight to the Trash (with Undo). Several items, a folder, or the file you have open ask first.
    private func requestTrash(_ entries: [BrowserEntry]) {
        guard !entries.isEmpty, parallelGuard(entries.map(\.url), action: "trashing") else { return }
        if entries.count > 1 || entries.contains(where: \.isDirectory) || includesOpenFile(entries) { pendingTrash = entries }
        else { performTrash(entries) }
    }

    private func performTrash(_ entries: [BrowserEntry]) {
        pendingTrash = []
        // The open file can't be trashed out from under the editor, so the page becomes blank first.
        if includesOpenFile(entries) { releaseCurrentDocument() }
        do { try browser.trash(entries, protecting: [parallelURL].compactMap { $0 }) } catch { problem = error.localizedDescription }
    }

    private var trashTitle: String {
        pendingTrash.count == 1 ? "Move “\(pendingTrash[0].displayName)” to the Trash?" : "Move \(pendingTrash.count) items to the Trash?"
    }
    private var trashMessage: String {
        var parts: [String] = []
        if includesOpenFile(pendingTrash) { parts.append("The file you have open is included, so Sable will switch to a blank page. Unsaved changes to it won’t be kept.") }
        if pendingTrash.contains(where: \.isDirectory) { parts.append("Folders go with everything inside them.") }
        parts.append("You can undo right afterward, or restore them from the Trash later.")
        return parts.joined(separator: " ")
    }

    /// Dropping a chapter onto another in the Manuscript folder reorders them; anything else moves as before.
    private func dropOnRow(_ urls: [URL], _ entry: BrowserEntry) {
        if let dragged = urls.first, urls.count == 1, browser.selectedURLs.count <= 1, browser.isChapter(entry.url), browser.isChapter(dragged),
           dragged.deletingLastPathComponent().standardizedFileURL.path == entry.url.deletingLastPathComponent().standardizedFileURL.path {
            do { try browser.reorderChapter(dragged, onto: entry.url) } catch { problem = error.localizedDescription }
            return
        }
        move(urls, into: entry.isDirectory ? entry.url : entry.url.deletingLastPathComponent())
    }

    // MARK: Keyboard

    private func handleKey(_ press: KeyPress, rows: [BrowserRow]) -> KeyPress.Result {
        guard browser.renaming == nil, !rows.isEmpty else { return .ignored }
        let index = rows.firstIndex { $0.entry.url == browser.selection }
        let selected = index.map { rows[$0].entry }
        switch press.key {
        case .downArrow:
            if press.modifiers.contains(.shift) { browser.extendSelection(by: 1) }
            else { browser.selection = rows[min((index ?? -1) + 1, rows.count - 1)].entry.url }
        case .upArrow:
            if press.modifiers.contains(.shift) { browser.extendSelection(by: -1) }
            else { browser.selection = rows[max((index ?? rows.count) - 1, 0)].entry.url }
        case .rightArrow:
            guard let selected, selected.isDirectory, !selected.isProject, !flat, !browser.expanded.contains(selected.url) else { return .ignored }
            browser.toggle(selected.url)
        case .leftArrow:
            guard let selected, !flat else { return .ignored }
            if selected.isDirectory, browser.expanded.contains(selected.url) { browser.toggle(selected.url) }
            else if let parent = rows.first(where: { $0.entry.url == selected.url.deletingLastPathComponent() }) { browser.selection = parent.entry.url }
            else { return .ignored }
        case .return:
            guard let selected else { return .ignored }
            if press.modifiers.contains(.shift) { browser.renaming = selected.url }
            else if !selected.isDirectory { switchFile(selected.url) }
            else if flat || selected.isProject { browser.navigate(selected.url) }
            else { browser.toggle(selected.url) }
        case .delete:
            guard press.modifiers.contains(.command) else { return .ignored }
            let chosen = browser.selectedEntries.isEmpty ? [selected].compactMap { $0 } : browser.selectedEntries
            guard !chosen.isEmpty else { return .ignored }
            requestTrash(chosen)
        case .escape:
            guard browser.selection != nil || !browser.selectedURLs.isEmpty else { return .ignored }
            browser.selection = nil
        default:
            guard press.modifiers.contains(.command), press.characters == "a" else { return .ignored }
            browser.selectAllDisplayed()
        }
        return .handled
    }
}

private struct NewProjectSheet: View {
    @Binding var name: String
    @Binding var starter: Bool
    let location: String
    let create: () -> Void
    let cancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "books.vertical").font(.largeTitle).foregroundStyle(.secondary)
            Text("New Fiction Project").font(.title3.weight(.semibold))
            Text("Creates a folder in “\(location)” with Manuscript, Characters, Locations, World, Notes, and Images inside. It’s all ordinary Markdown files, so any editor can open it.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Project name", text: $name).textFieldStyle(.roundedBorder).onSubmit(create)
            Toggle("Add a sample chapter, character, and location", isOn: $starter)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button("Create Project", action: create).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.padding(24).frame(width: 400)
    }
}

private struct FilterChip<Label: View>: View {
    let active: Bool
    let help: String
    let action: () -> Void
    @ViewBuilder let label: Label
    var body: some View {
        Button(action: action) {
            label.frame(minWidth: 16, minHeight: 16).padding(.horizontal, 6).padding(.vertical, 2)
                .background(active ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(active ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1))
        }.buttonStyle(.plain).help(help)
    }
}

private struct BreadcrumbChip: View {
    let url: URL
    let isCurrent: Bool
    let navigate: () -> Void
    let drop: ([URL], URL) -> Void
    @State private var targeted = false
    var body: some View {
        Button(url.lastPathComponent, action: navigate)
            .foregroundStyle(isCurrent ? .primary : .secondary)
            .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
            .padding(.horizontal, 4).padding(.vertical, 2)
            .background(targeted ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .help(isCurrent ? url.path : "\(url.path) — drop items here to move them")
            .disabled(isCurrent)
            .dropDestination(for: URL.self) { urls, _ in drop(urls, url); return true } isTargeted: { targeted = $0 }
    }
}

private struct BrowserRowView: View {
    @EnvironmentObject private var browser: FolderBrowser
    let entry: BrowserEntry
    let depth: Int
    let currentURL: URL?
    let showPath: Bool
    let parallelURL: URL?
    let switchFile: (URL) -> Void
    let showParallel: (URL) -> Void
    let promptNew: (NewItemKind, URL?) -> Void
    let dropOnRow: ([URL], BrowserEntry) -> Void
    let rename: (BrowserEntry, String) -> Void
    let trash: ([BrowserEntry]) -> Void
    let showCard: (URL) -> Void
    let convertProject: (URL) -> Void
    let adoptFolder: (URL) -> Void
    let newCategory: () -> Void
    let addToFolder: (URL, NewProjectItem) -> Void
    @AppStorage("sidebarCompact") private var compact = false
    @AppStorage("sidebarShowIcons") private var showIcons = true
    @AppStorage("sidebarShowExtensions") private var showExtensions = false
    @AppStorage("sidebarShowModified") private var showModified = false
    @AppStorage("sidebarShowWords") private var showWords = false
    @State private var hovering = false
    @State private var dropTargeted = false
    @State private var draft = ""
    @FocusState private var editing: Bool

    private var mark: MarkColor? { browser.color(of: entry.url) }
    private var expanded: Bool { browser.expanded.contains(entry.url) && !showPath }
    private var isParallel: Bool { parallelURL?.standardizedFileURL == entry.url.standardizedFileURL }
    private var isCurrent: Bool { currentURL?.standardizedFileURL == entry.url.standardizedFileURL }
    private var isSelected: Bool { browser.selectedURLs.contains(entry.url) }
    private var cardKind: CardKind? { browser.cardKind(of: entry) }
    /// The kind of thing a "+" on this folder would add (chapter, character, location, world note).
    private var addItem: NewProjectItem? { entry.isDirectory && inProject ? browser.projectItem(forFolder: entry.url) : nil }
    private var inProject: Bool { browser.projectURL != nil }
    private var isMarkdown: Bool { ["md", "markdown"].contains(entry.url.pathExtension.lowercased()) }
    private var isRenaming: Bool { browser.renaming == entry.url }
    /// Dropping on a folder moves into it; dropping on a file moves next to it.
    private var dropFolder: URL { entry.isDirectory ? entry.url : entry.url.deletingLastPathComponent() }
    private var title: String { showExtensions ? entry.name : entry.displayName }
    private var parentPath: String? {
        guard showPath, let root = browser.root, let key = FolderMarks.key(for: entry.url.deletingLastPathComponent(), in: root) else { return nil }
        return key
    }
    private var detail: String? {
        var parts: [String] = []
        if let parentPath { parts.append(parentPath) }
        if showWords, !entry.isDirectory, let counted = browser.wordCounts[entry.url] { parts.append("\(counted.words.formatted()) words") }
        if showModified, let modified = entry.modified {
            parts.append(modified.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 4) {
            if isRenaming { renameField } else { mainButton }
            if let addItem, !isRenaming, hovering {
                Button { addToFolder(entry.url, addItem) } label: {
                    Image(systemName: "plus.circle").font(.system(size: 12)).foregroundStyle(Color.accentColor).frame(width: 22, height: 20)
                }.buttonStyle(.plain)
                .help(addItem.addHelp).accessibilityLabel(addItem.title)
            }
            if let cardKind, !isRenaming, hovering {
                Button { showCard(entry.url) } label: {
                    Image(systemName: "rectangle.stack.person.crop").font(.system(size: 11)).foregroundStyle(Color.secondary).frame(width: 22, height: 20)
                }.buttonStyle(.plain)
                .help("Show this \(cardKind.title.lowercased()) as a card").accessibilityLabel("Show as card")
            }
            if !entry.isDirectory && !isCurrent && !isRenaming && (hovering || isParallel) {
                Button { showParallel(entry.url) } label: {
                    Image(systemName: isParallel ? "rectangle.split.2x1.fill" : "rectangle.split.2x1")
                        .font(.system(size: 11)).foregroundStyle(isParallel ? Color.accentColor : Color.secondary)
                        .frame(width: 22, height: 20)
                }.buttonStyle(.plain)
                .help(isParallel ? "Open beside your draft" : "Open beside current document")
                .accessibilityLabel(isParallel ? "Open beside your draft" : "Open beside current document")
            }
        }
        .font(.system(size: 12)).padding(compact ? 4 : 7).padding(.leading, CGFloat(min(depth, 10)) * 12)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(dropTargeted ? Color.accentColor : .clear, lineWidth: 1.5))
        .onHover { hovering = $0 }
        .draggable(entry.url)
        .dropDestination(for: URL.self) { urls, _ in dropOnRow(urls, entry); return true } isTargeted: { dropTargeted = $0 }
        .task(id: showWords) { if showWords { browser.loadWordCount(for: entry) } }
        .contextMenu { menu }
    }

    private var mainButton: some View {
        Button {
            // ⌘-click and ⇧-click build a selection; a plain click selects the row and opens it.
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            browser.click(entry.url, command: flags.contains(.command), shift: flags.contains(.shift))
            if flags.contains(.command) || flags.contains(.shift) { return }
            if !entry.isDirectory { switchFile(entry.url) }
            else if showPath || entry.isProject { browser.navigate(entry.url) }
            else { browser.toggle(entry.url) }
        } label: {
            HStack(spacing: 8) {
                if entry.isProject {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).frame(width: 10)
                    Image(systemName: "books.vertical.fill").foregroundStyle(Color.accentColor)
                } else if entry.isDirectory {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).frame(width: 10)
                    if showIcons { Image(systemName: "folder.fill").foregroundStyle(mark?.color ?? Color.secondary.opacity(0.7)) }
                } else if showIcons {
                    Image(systemName: cardKind?.symbol ?? "doc.text").foregroundStyle(.secondary).padding(.leading, 18)
                } else {
                    Color.clear.frame(width: 10, height: 1)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).lineLimit(1).fontWeight(isCurrent ? .medium : .regular)
                    if entry.isProject && detail == nil { Text("Fiction Project").font(.system(size: 10)).foregroundStyle(.tertiary) }
                    if let detail { Text(detail).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1) }
                }
                Spacer(minLength: 0)
                if browser.isPinned(entry.url) { Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.tertiary) }
                if let mark, !showIcons || !entry.isDirectory {
                    Circle().fill(mark.color).frame(width: 7, height: 7).help(browser.label(for: mark))
                }
                if browser.loadingFolders.contains(entry.url) { ProgressView().controlSize(.mini) }
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private var renameField: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.text").foregroundStyle(.secondary)
            TextField("Name", text: $draft)
                .textFieldStyle(.roundedBorder).focused($editing)
                .onSubmit { rename(entry, draft) }
                .onExitCommand { browser.renaming = nil }
                .onChange(of: editing) { _, focused in if !focused && isRenaming { browser.renaming = nil } }
        }
        .onAppear { draft = entry.isDirectory ? entry.name : (showExtensions ? entry.name : entry.displayName); editing = true }
    }

    @ViewBuilder
    private var menu: some View {
        if entry.isProject {
            Button("Open Project") { browser.navigate(entry.url) }
            Button("Convert to Regular Folder…") { convertProject(entry.url) }
            Divider()
        } else if entry.isDirectory {
            Button("Focus on This Folder") { browser.navigate(entry.url) }
            if let addItem { Button(addItem.title + " Here" + (addItem == .chapter ? "" : "…")) { addToFolder(entry.url, addItem) } }
            Button("New File in This Folder…") { promptNew(.file, entry.url) }
            Button("New Folder in This Folder…") { promptNew(.folder, entry.url) }
            if !inProject { Button("Make Fiction Project…") { adoptFolder(entry.url) } }
            if !inProject { categoryMenu }
        } else {
            Button("Switch to This File") { switchFile(entry.url) }
            Button("Open Beside Current Document") { showParallel(entry.url) }.disabled(isCurrent)
            if inProject && isMarkdown {
                Button("Show as Card") { showCard(entry.url) }
            }
        }
        if browser.isChapter(entry.url) { chapterMenu }
        Divider()
        Button("Rename") { browser.selection = entry.url; browser.renaming = entry.url }
        Menu("Color") {
            ForEach(MarkColor.allCases, id: \.self) { color in
                Button { browser.setColor(color, for: entry.url) } label: {
                    Label { Text(browser.label(for: color) + (mark == color ? " ✓" : "")) } icon: { Image(nsImage: color.swatch) }
                }
            }
            if mark != nil { Divider(); Button("Remove Color") { browser.setColor(nil, for: entry.url) } }
        }
        if browser.isManuscript(entry.url) {
            Button("Always Pinned (Manuscript)") {}.disabled(true)
        } else {
            Button(browser.isPinned(entry.url) ? "Unpin" : "Pin to Top") { browser.togglePin(entry.url) }
        }
        Divider()
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
        let targets = browser.trashTargets(for: entry)
        Button(targets.count > 1 ? "Move \(targets.count) Items to Trash" : "Move to Trash", role: .destructive) { trash(targets) }
    }

    /// Reordering without dragging, for chapters in the Manuscript folder.
    @ViewBuilder
    private var chapterMenu: some View {
        let names = browser.chapterNames()
        let index = names.firstIndex(of: entry.name) ?? 0
        Divider()
        Button("Move Chapter Up") { try? browser.moveChapter(entry.url, to: index - 1) }.disabled(index == 0)
        Button("Move Chapter Down") { try? browser.moveChapter(entry.url, to: index + 1) }.disabled(index >= names.count - 1)
        Button("Move Chapter to Top") { try? browser.moveChapter(entry.url, to: 0) }.disabled(index == 0)
        Button("Move Chapter to End") { try? browser.moveChapter(entry.url, to: names.count - 1) }.disabled(index >= names.count - 1)
    }

    /// The same filing that dragging onto a category header does, for anyone who prefers a menu.
    private var categoryMenu: some View {
        let assigned = browser.categoryID(of: entry)
        return Menu("Category") {
            ForEach(browser.categories.list) { category in
                Button(category.name + (assigned == category.id ? " ✓" : "")) { browser.assign(entry.url, to: category.id) }
            }
            if !browser.categories.list.isEmpty { Divider() }
            if assigned != nil { Button("Remove from Category") { browser.assign(entry.url, to: nil) } }
            Button("New Category…", action: newCategory)
        }
    }

    private var rowBackground: Color {
        if dropTargeted { return Color.accentColor.opacity(0.18) }
        if isCurrent { return Color.accentColor.opacity(0.14) }
        if isSelected { return Color.primary.opacity(0.08) }
        if entry.isDirectory, let mark { return mark.color.opacity(0.10) }
        return .clear
    }
}
