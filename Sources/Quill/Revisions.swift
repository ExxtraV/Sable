import Foundation

/// Snapshots of a draft, so a big rewrite can always be undone, and a comparison that shows what changed.
///
/// A snapshot is a folder of plain copies inside `.sable-revisions` in the writing folder or Fiction Project, next to
/// a small `snapshot.json`. Nothing is hidden in a database: the copies are ordinary Markdown files you can open.
struct Snapshot: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case manual, automatic, safety }
    struct File: Codable, Equatable {
        /// Path relative to the folder the snapshot belongs to, e.g. "Manuscript/Chapter 1.md".
        var path: String
        var words: Int
    }
    var id: String
    var name: String
    var note: String
    var date: Date
    var kind: Kind
    var files: [File]
    /// The chapter order saved in a Fiction Project when the snapshot was taken.
    var chapterOrder: [String]?
    var words: Int { files.reduce(0) { $0 + $1.words } }
}

enum ChangeStatus: String { case unchanged, changed, added, removed }

/// How one file differs between a snapshot and now.
struct FileChange: Identifiable, Equatable {
    var id: String { path }
    let path: String
    let status: ChangeStatus
    let wordsThen: Int
    let wordsNow: Int
    var delta: Int { wordsNow - wordsThen }
    var title: String { ((path as NSString).lastPathComponent as NSString).deletingPathExtension }
}

/// A stretch of text that is the same, new, or gone.
struct DiffPiece: Equatable {
    enum Kind { case same, inserted, deleted }
    var kind: Kind
    var text: String
}

enum Revisions {
    static let folderName = ".sable-revisions"
    static let automaticLimit = 20

    static func directory(in root: URL) -> URL { root.appendingPathComponent(folderName, isDirectory: true) }

    static func words(in text: String) -> Int { text.split { $0.isWhitespace || $0.isNewline }.count }

    // MARK: Reading

    /// Every snapshot below `root`, newest first.
    static func list(in root: URL) -> [Snapshot] {
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(at: directory(in: root), includingPropertiesForKeys: nil) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return folders.compactMap { folder -> Snapshot? in
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("snapshot.json")) else { return nil }
            return try? decoder.decode(Snapshot.self, from: data)
        }.sorted { $0.date > $1.date }
    }

    private static func folder(of snapshot: Snapshot, in root: URL) -> URL { directory(in: root).appendingPathComponent(snapshot.id, isDirectory: true) }

    static func text(of path: String, in snapshot: Snapshot, root: URL) throws -> String {
        try String(contentsOf: folder(of: snapshot, in: root).appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: Taking snapshots

    /// Copies `files` (which must be inside `root`) into a new snapshot. `liveText` supplies the text of a file that is open
    /// with changes not saved yet, so the snapshot holds what is on the page.
    @discardableResult
    static func create(name: String, note: String = "", kind: Snapshot.Kind = .manual, root: URL, files: [URL],
                       chapterOrder: [String]? = nil, liveText: [URL: String] = [:], date requested: Date = Date()) throws -> Snapshot {
        let fm = FileManager.default
        // Whole seconds, which is all the file keeps.
        let date = Date(timeIntervalSince1970: requested.timeIntervalSince1970.rounded(.down))
        let rootPath = root.standardizedFileURL.path
        let id = idString(for: date)
        let target = directory(in: root).appendingPathComponent(id, isDirectory: true)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        var entries: [Snapshot.File] = []
        do {
            for url in files {
                let standard = url.standardizedFileURL
                guard standard.path.hasPrefix(rootPath + "/") else { continue }
                let relative = String(standard.path.dropFirst(rootPath.count + 1))
                let text: String
                if let live = liveText[standard] { text = live } else { text = try String(contentsOf: standard, encoding: .utf8) }
                let destination = target.appendingPathComponent(relative)
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: destination, atomically: true, encoding: .utf8)
                entries.append(Snapshot.File(path: relative, words: words(in: text)))
            }
            let snapshot = Snapshot(id: id, name: name, note: note, date: date, kind: kind, files: entries.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }, chapterOrder: chapterOrder)
            try write(snapshot, in: root)
            if kind == .automatic { prune(in: root) }
            return snapshot
        } catch {
            try? fm.removeItem(at: target)
            throw error
        }
    }

    private static func idString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date) + "-" + String(UUID().uuidString.prefix(4)).lowercased()
    }

    private static func write(_ snapshot: Snapshot, in root: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: folder(of: snapshot, in: root).appendingPathComponent("snapshot.json"), options: .atomic)
    }

    /// A daily snapshot when none has been taken in the last day. Returns it, or nil if none was due.
    @discardableResult
    static func automaticIfDue(root: URL, files: [URL], chapterOrder: [String]?, now: Date = Date(), interval: TimeInterval = 86_400) -> Snapshot? {
        guard !files.isEmpty else { return nil }
        let existing = list(in: root)
        if let latest = existing.first(where: { $0.kind != .safety }), now.timeIntervalSince(latest.date) < interval { return nil }
        // Nothing has changed since the last one: don't fill the folder with copies of the same words.
        if let latest = existing.first, let diffs = try? changes(from: latest, root: root, files: files), diffs.allSatisfy({ $0.status == .unchanged }) { return nil }
        return try? create(name: "Daily snapshot", kind: .automatic, root: root, files: files, chapterOrder: chapterOrder, date: now)
    }

    static func prune(in root: URL, keepAutomatic: Int = automaticLimit) {
        let automatic = list(in: root).filter { $0.kind == .automatic }
        for old in automatic.dropFirst(keepAutomatic) { delete(old, in: root) }
    }

    static func rename(_ snapshot: Snapshot, name: String, note: String, in root: URL) throws {
        var updated = snapshot
        updated.name = name
        updated.note = note
        try write(updated, in: root)
    }

    static func delete(_ snapshot: Snapshot, in root: URL) {
        try? FileManager.default.removeItem(at: folder(of: snapshot, in: root))
    }

    // MARK: Comparing

    /// How each file in the snapshot, and each of `files` now, differs. `liveText` overrides what is on disk.
    static func changes(from snapshot: Snapshot, root: URL, files: [URL], liveText: [URL: String] = [:]) throws -> [FileChange] {
        let rootPath = root.standardizedFileURL.path
        var now: [String: String] = [:]
        for url in files {
            let standard = url.standardizedFileURL
            guard standard.path.hasPrefix(rootPath + "/") else { continue }
            let relative = String(standard.path.dropFirst(rootPath.count + 1))
            if let text = liveText[standard] ?? (try? String(contentsOf: standard, encoding: .utf8)) { now[relative] = text }
        }
        var result: [FileChange] = []
        for file in snapshot.files {
            if let current = now.removeValue(forKey: file.path) {
                let then = try text(of: file.path, in: snapshot, root: root)
                result.append(FileChange(path: file.path, status: then == current ? .unchanged : .changed, wordsThen: file.words, wordsNow: words(in: current)))
            } else {
                result.append(FileChange(path: file.path, status: .removed, wordsThen: file.words, wordsNow: 0))
            }
        }
        for (path, text) in now { result.append(FileChange(path: path, status: .added, wordsThen: 0, wordsNow: words(in: text))) }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    // MARK: Restoring

    /// Puts one file back as it was. The caller takes a safety snapshot first.
    static func restore(_ path: String, from snapshot: Snapshot, root: URL) throws {
        let text = try text(of: path, in: snapshot, root: root)
        let destination = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: destination, atomically: true, encoding: .utf8)
    }

    // MARK: The difference between two texts

    /// The words added and removed going from `old` to `new`, paragraph by paragraph and then word by word.
    static func diff(from old: String, to new: String) -> [DiffPiece] {
        let oldLines = lines(of: old), newLines = lines(of: new)
        var pieces: [DiffPiece] = []
        func add(_ kind: DiffPiece.Kind, _ text: String) {
            guard !text.isEmpty else { return }
            if let last = pieces.last, last.kind == kind { pieces[pieces.count - 1].text += text } else { pieces.append(DiffPiece(kind: kind, text: text)) }
        }
        var removedText = "", insertedText = ""
        func flushChange() {
            defer { removedText = ""; insertedText = "" }
            if removedText.isEmpty { add(.inserted, insertedText); return }
            if insertedText.isEmpty { add(.deleted, removedText); return }
            for piece in wordDiff(from: removedText, to: insertedText) { add(piece.kind, piece.text) }
        }
        for step in align(oldLines, newLines) {
            switch step {
            case let .same(line): flushChange(); add(.same, line)
            case let .removed(line): removedText += line
            case let .inserted(line): insertedText += line
            }
        }
        flushChange()
        return pieces
    }

    /// Lines with their line breaks kept, so putting them back together gives the text exactly.
    private static func lines(of text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == "\n" || character == "\r\n" { result.append(current); current = "" }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private enum Step<T: Hashable> { case same(T), removed(T), inserted(T) }

    /// Lines or words of two sequences lined up: what stayed, what left, what arrived.
    private static func align<T: Hashable>(_ old: [T], _ new: [T]) -> [Step<T>] {
        let difference = new.difference(from: old)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in difference {
            switch change {
            case let .remove(offset, _, _): removed.insert(offset)
            case let .insert(offset, _, _): inserted.insert(offset)
            }
        }
        var steps: [Step<T>] = []
        var i = 0, j = 0
        while i < old.count || j < new.count {
            if i < old.count, removed.contains(i) { steps.append(.removed(old[i])); i += 1 }
            else if j < new.count, inserted.contains(j) { steps.append(.inserted(new[j])); j += 1 }
            else if i < old.count, j < new.count { steps.append(.same(old[i])); i += 1; j += 1 }
            else { break }
        }
        return steps
    }

    private static func tokens(_ text: String) -> [String] {
        var result: [String] = []
        var current = "", inSpace: Bool?
        for character in text {
            let space = character.isWhitespace
            if inSpace == space { current.append(character) }
            else {
                if !current.isEmpty { result.append(current) }
                current = String(character)
                inSpace = space
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func wordDiff(from old: String, to new: String) -> [DiffPiece] {
        let a = tokens(old), b = tokens(new)
        // A rewrite of a whole scene is not worth comparing word by word: show it as one removal and one addition.
        guard a.count * b.count < 25_000_000 || a.count + b.count < 6_000 else {
            return [DiffPiece(kind: .deleted, text: old), DiffPiece(kind: .inserted, text: new)]
        }
        var pieces: [DiffPiece] = []
        func add(_ kind: DiffPiece.Kind, _ text: String) {
            if let last = pieces.last, last.kind == kind { pieces[pieces.count - 1].text += text } else { pieces.append(DiffPiece(kind: kind, text: text)) }
        }
        for step in align(a, b) {
            switch step {
            case let .same(token): add(.same, token)
            case let .removed(token): add(.deleted, token)
            case let .inserted(token): add(.inserted, token)
            }
        }
        return pieces
    }
}
