import SwiftUI
import AppKit

struct BrowserEntry: Identifiable, Sendable {
    var id: URL { url }
    let url: URL
    let isDirectory: Bool
    var modified: Date? = nil
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
            if values.isDirectory == true { return BrowserEntry(url: url, isDirectory: true, modified: values.contentModificationDate) }
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
            found.append(BrowserEntry(url: url, isDirectory: isDirectory, modified: values.contentModificationDate))
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
    /// Carries colors and pins along when items (or whole folders) move.
    func remapped(moves: [(from: URL, to: URL)], root: URL) -> FolderMarks {
        func rewrite(_ key: String) -> String {
            for move in moves {
                guard let old = FolderMarks.key(for: move.from, in: root), let new = FolderMarks.key(for: move.to, in: root) else { continue }
                if key == old { return new }
                if key.hasPrefix(old + "/") { return new + key.dropFirst(old.count) }
            }
            return key
        }
        var result = FolderMarks()
        for (key, color) in colors { result.colors[rewrite(key)] = color }
        result.pinned = Set(pinned.map(rewrite))
        return result
    }
    func keys(matching filter: MarkFilter) -> [String] {
        switch filter {
        case .pinned: return pinned.sorted()
        case let .color(color): return colors.filter { $0.value == color }.map(\.key).sorted()
        }
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
    @Published private(set) var current: URL?
    @Published private(set) var entries: [BrowserEntry] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var expanded: Set<URL> = []
    @Published private(set) var children: [URL: [BrowserEntry]] = [:]
    @Published private(set) var loadingFolders: Set<URL> = []
    @Published private(set) var folderErrors: [URL: String] = [:]
    @Published private(set) var marks = FolderMarks()
    @Published var filter: MarkFilter?
    @Published var selection: URL?
    @Published var renaming: URL?
    @Published private(set) var searchResults: [BrowserEntry] = []
    @Published private(set) var searching = false
    @Published private(set) var wordCounts: [URL: FileWords] = [:]
    @Published private(set) var lastTrashed: TrashedItem?
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
        func ordered(_ entries: [BrowserEntry]) -> [BrowserEntry] {
            let sorted = FolderListing.sorted(entries, by: sort, foldersFirst: foldersFirst)
            guard !marks.pinned.isEmpty else { return sorted }
            return sorted.filter(isPinned) + sorted.filter { !isPinned($0.url) }
        }
        func flatten(_ entries: [BrowserEntry], depth: Int) -> [BrowserRow] {
            ordered(entries).flatMap { entry -> [BrowserRow] in
                let row = BrowserRow(entry: entry, depth: depth)
                guard entry.isDirectory, expanded.contains(entry.url) else { return [row] }
                return [row] + flatten(children[entry.url] ?? [], depth: depth + 1)
            }
        }
        return flatten(entries, depth: 0)
    }
    private func isPinned(_ entry: BrowserEntry) -> Bool { isPinned(entry.url) }

    /// Folders from the writing folder down to the one being viewed.
    var breadcrumbs: [URL] {
        guard let root, let current else { return [] }
        var trail = [current]
        while let last = trail.last, last.standardizedFileURL != root.standardizedFileURL {
            let parent = last.deletingLastPathComponent()
            if parent.standardizedFileURL == last.standardizedFileURL { break }
            trail.append(parent)
        }
        return trail.reversed()
    }

    func color(of url: URL) -> MarkColor? {
        guard let root, let key = FolderMarks.key(for: url, in: root) else { return nil }
        return marks.colors[key]
    }
    func isPinned(_ url: URL) -> Bool {
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
            return BrowserEntry(url: url, isDirectory: isDirectory.boolValue)
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
        expanded = Set(expanded.map { FolderMove.rewrite($0, moves: moves) })
        if selection == entry.url { selection = target }
        reload()
        return target
    }

    // MARK: Trash (with a short-lived undo)
    func trash(_ entry: BrowserEntry, protecting inUse: [URL]) throws {
        if inUse.contains(where: { FolderMove.isInside($0, of: entry.url) }) { throw FolderTrashError.inUse(entry.displayName) }
        var resulting: NSURL?
        try FileManager.default.trashItem(at: entry.url, resultingItemURL: &resulting)
        lastTrashed = TrashedItem(name: entry.displayName, original: entry.url, trashed: (resulting as URL?) ?? entry.url)
        expanded = expanded.filter { !FolderMove.isInside($0, of: entry.url) }
        if let selection, FolderMove.isInside(selection, of: entry.url) { self.selection = nil }
        reload()
        trashNoticeTask?.cancel()
        trashNoticeTask = Task {
            try? await Task.sleep(for: .seconds(12))
            if !Task.isCancelled { lastTrashed = nil }
        }
    }
    func undoTrash() throws {
        guard let item = lastTrashed else { return }
        if FileManager.default.fileExists(atPath: item.original.path) { throw FolderTrashError.occupied(item.name) }
        try FolderMove.coordinatedMove(from: item.trashed, to: item.original)
        lastTrashed = nil
        reload()
    }
    func dismissTrashNotice() { lastTrashed = nil }

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
            filter = nil
            expanded = []; children = [:]
            UserDefaults.standard.set(bookmark, forKey: "writingFolder")
            refresh()
        } catch {
            if newScope { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }
    func navigate(_ url: URL) {
        guard let root else { return }
        let base = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path == base || path.hasPrefix(base + "/") else { return }
        current = url
        expanded = []; children = [:]
        refresh()
    }
    func up() {
        guard let current, current != root else { return }
        navigate(current.deletingLastPathComponent())
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
                for folder in expanded { loadChildren(folder) }
            case let .failure(failure): error = failure.localizedDescription
            }
        }
    }
}

struct FolderBrowserSection: View {
    @EnvironmentObject private var browser: FolderBrowser
    let currentURL: URL?
    let search: String
    let chooseFolder: () -> Void
    let switchFile: (URL) -> Void
    let showParallel: (URL) -> Void
    var parallelURL: URL? = nil
    @State private var showNewItem = false
    @State private var newKind = NewItemKind.file
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let current = browser.current {
                breadcrumbBar(current)
                if !browser.marks.isEmpty { filterBar }
                let shown = rows
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(shown) { row in
                        BrowserRowView(entry: row.entry, depth: row.depth, currentURL: currentURL, showPath: flat,
                                       parallelURL: parallelURL, switchFile: switchFile, showParallel: showParallel,
                                       promptNew: { promptNew($0, in: $1) }, moveItems: move, rename: rename, trash: trash)
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
        .alert(newKind.title, isPresented: $showNewItem) {
            TextField(newKind == .file ? "Untitled.md" : "Folder name", text: $newName)
            Button("Create") { createItem() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("In “\(newFolder?.lastPathComponent ?? "")”") }
        .alert("That didn’t work", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") { problem = nil }
        } message: { Text(problem ?? "") }
    }

    // MARK: Header pieces

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
                Button("New File…") { promptNew(.file, in: browser.current) }
                Button("New Folder…") { promptNew(.folder, in: browser.current) }
            } label: { Image(systemName: "plus") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Create a file or folder in \(current.lastPathComponent)").accessibilityLabel("New file or folder")
            Menu {
                Button("Choose Writing Folder…", action: chooseFolder)
                Button("Refresh") { browser.refresh() }
                Button("Collapse All Folders") { browser.collapseAll() }.disabled(browser.expanded.isEmpty)
                if let root = browser.root { Button("Back to \(root.lastPathComponent)") { browser.navigate(root) } }
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

    private func trashNotice(_ item: TrashedItem) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "trash").foregroundStyle(.secondary)
            Text("Moved “\(item.name)” to the Trash").lineLimit(1)
            Spacer(minLength: 0)
            Button("Undo") { do { try browser.undoTrash() } catch { problem = error.localizedDescription } }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
            Button { browser.dismissTrashNotice() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .font(.system(size: 11)).padding(8)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Actions

    private func promptNew(_ kind: NewItemKind, in folder: URL?) {
        guard let folder else { return }
        newKind = kind
        newFolder = folder
        newName = ""
        showNewItem = true
    }

    private func createItem() {
        guard let folder = newFolder else { return }
        do {
            let url = try browser.create(newKind, named: newName, in: folder)
            if newKind == .file { switchFile(url) }
        } catch { problem = error.localizedDescription }
    }

    /// The parallel document is off limits while it's open beside the draft.
    private func parallelGuard(_ urls: [URL], action: String) -> Bool {
        guard let parallelURL, urls.contains(where: { FolderMove.isInside(parallelURL, of: $0) }) else { return true }
        problem = "Close the parallel document before \(action) it."
        return false
    }

    private func move(_ urls: [URL], into folder: URL) {
        guard parallelGuard(urls, action: "moving") else { return }
        do { try browser.move(urls, into: folder) } catch { problem = error.localizedDescription }
    }

    private func rename(_ entry: BrowserEntry, to name: String) {
        defer { browser.renaming = nil }
        guard parallelGuard([entry.url], action: "renaming") else { return }
        do { try browser.rename(entry, to: name) } catch { problem = error.localizedDescription }
    }

    private func trash(_ entry: BrowserEntry) {
        guard parallelGuard([entry.url], action: "trashing") else { return }
        do { try browser.trash(entry, protecting: [currentURL].compactMap { $0 }) } catch { problem = error.localizedDescription }
    }

    // MARK: Keyboard

    private func handleKey(_ press: KeyPress, rows: [BrowserRow]) -> KeyPress.Result {
        guard browser.renaming == nil, !rows.isEmpty else { return .ignored }
        let index = rows.firstIndex { $0.entry.url == browser.selection }
        let selected = index.map { rows[$0].entry }
        switch press.key {
        case .downArrow:
            browser.selection = rows[min((index ?? -1) + 1, rows.count - 1)].entry.url
        case .upArrow:
            browser.selection = rows[max((index ?? rows.count) - 1, 0)].entry.url
        case .rightArrow:
            guard let selected, selected.isDirectory, !flat, !browser.expanded.contains(selected.url) else { return .ignored }
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
            else if flat { browser.navigate(selected.url) }
            else { browser.toggle(selected.url) }
        case .delete:
            guard press.modifiers.contains(.command), let selected else { return .ignored }
            trash(selected)
        case .escape:
            guard browser.selection != nil else { return .ignored }
            browser.selection = nil
        default: return .ignored
        }
        return .handled
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
    let moveItems: ([URL], URL) -> Void
    let rename: (BrowserEntry, String) -> Void
    let trash: (BrowserEntry) -> Void
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
    private var isSelected: Bool { browser.selection == entry.url }
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
        .dropDestination(for: URL.self) { urls, _ in moveItems(urls, dropFolder); return true } isTargeted: { dropTargeted = $0 }
        .task(id: showWords) { if showWords { browser.loadWordCount(for: entry) } }
        .contextMenu { menu }
    }

    private var mainButton: some View {
        Button {
            browser.selection = entry.url
            if !entry.isDirectory { switchFile(entry.url) }
            else if showPath { browser.navigate(entry.url) }
            else { browser.toggle(entry.url) }
        } label: {
            HStack(spacing: 8) {
                if entry.isDirectory {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).frame(width: 10)
                    if showIcons { Image(systemName: "folder.fill").foregroundStyle(mark?.color ?? Color.secondary.opacity(0.7)) }
                } else if showIcons {
                    Image(systemName: "doc.text").foregroundStyle(.secondary).padding(.leading, 18)
                } else {
                    Color.clear.frame(width: 10, height: 1)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).lineLimit(1).fontWeight(isCurrent ? .medium : .regular)
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
        if entry.isDirectory {
            Button("Focus on This Folder") { browser.navigate(entry.url) }
            Button("New File in This Folder…") { promptNew(.file, entry.url) }
            Button("New Folder in This Folder…") { promptNew(.folder, entry.url) }
        } else {
            Button("Switch to This File") { switchFile(entry.url) }
            Button("Open Beside Current Document") { showParallel(entry.url) }.disabled(isCurrent)
        }
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
        Button(browser.isPinned(entry.url) ? "Unpin" : "Pin to Top") { browser.togglePin(entry.url) }
        Divider()
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
        Button("Move to Trash", role: .destructive) { trash(entry) }.disabled(isCurrent)
    }

    private var rowBackground: Color {
        if dropTargeted { return Color.accentColor.opacity(0.18) }
        if isCurrent { return Color.accentColor.opacity(0.14) }
        if isSelected { return Color.primary.opacity(0.08) }
        if entry.isDirectory, let mark { return mark.color.opacity(0.10) }
        return .clear
    }
}
