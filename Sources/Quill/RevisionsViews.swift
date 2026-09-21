import SwiftUI
import AppKit

/// What a revisions window is looking at: a Fiction Project's manuscript, or the one open document.
struct RevisionScope {
    let root: URL
    /// Every file a snapshot should hold right now.
    let files: [URL]
    let chapterOrder: [String]?
    let isProject: Bool
    let openURL: URL?
    let openText: String
    var title: String { isProject ? "manuscript" : "document" }
}

struct RevisionsRequest: Identifiable {
    let id = UUID()
    let scope: RevisionScope
    /// Start with the name field ready for a new snapshot.
    let saving: Bool
}

/// Save drafts as snapshots, see exactly what changed since each one, and take chapters or the whole draft back.
struct RevisionsSheet: View {
    let request: RevisionsRequest
    let replaceOpenText: (String) -> Void
    let filesChanged: () -> Void
    let restoreOrder: ([String]) -> Void
    let close: () -> Void

    @State private var snapshots: [Snapshot] = []
    @State private var selectedID: String?
    @State private var changes: [FileChange] = []
    @State private var selectedPath: String?
    @State private var pieces: [DiffPiece] = []
    @State private var name = ""
    @State private var note = ""
    @State private var message: String?
    @State private var renaming = false
    @State private var renameName = ""
    @State private var renameNote = ""
    @State private var confirmDraft = false
    @State private var confirmDelete = false
    @State private var busy = false
    @FocusState private var nameFocused: Bool
    @AppStorage("fontFamily") private var family = "Charter"

    private var scope: RevisionScope { request.scope }
    private var selected: Snapshot? { snapshots.first { $0.id == selectedID } }
    private var selectedChange: FileChange? { changes.first { $0.path == selectedPath } }
    private var live: [URL: String] { scope.openURL.map { [$0.standardizedFileURL: scope.openText] } ?? [:] }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 270)
            Divider()
            detail.frame(maxWidth: .infinity)
        }
        .frame(width: 940, height: 640)
        .task { reload(); if request.saving { nameFocused = true } }
        .alert("Rename Snapshot", isPresented: $renaming) {
            TextField("Name", text: $renameName)
            TextField("Note", text: $renameNote)
            Button("Save", action: saveDetails)
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Restore the whole \(scope.title) to “\(selected?.name ?? "")”?", isPresented: $confirmDraft, titleVisibility: .visible) {
            Button("Restore Entire Draft", role: .destructive, action: restoreDraft)
            Button("Cancel", role: .cancel) {}
        } message: { Text("Every changed or deleted file goes back to how it was then. Files you have added since are left alone. A safety snapshot of right now is saved first, so you can undo this.") }
        .confirmationDialog("Delete this snapshot?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Snapshot", role: .destructive, action: deleteSelected)
            Button("Cancel", role: .cancel) {}
        } message: { Text("Its copies are removed for good.") }
    }

    // MARK: Left: save and list

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Revisions").font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 8) {
                TextField("Name this draft (e.g. Before the rewrite)", text: $name).textFieldStyle(.roundedBorder).focused($nameFocused)
                    .onSubmit(saveSnapshot)
                TextField("Note (optional)", text: $note).textFieldStyle(.roundedBorder)
                Button(action: saveSnapshot) { Label("Save Snapshot of the \(scope.title)", systemImage: "camera") }
                    .disabled(busy || scope.files.isEmpty)
                    .help("Keeps a copy of \(scope.isProject ? "every chapter" : "this document") exactly as it is now")
            }
            Divider()
            if snapshots.isEmpty {
                Text("No snapshots yet. Save one before a big rewrite, and you can always come back.").font(.callout).foregroundStyle(.secondary)
                Spacer()
            } else {
                List(selection: $selectedID) {
                    ForEach(snapshots) { snapshot in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(snapshot.name).font(.callout.weight(.medium)).lineLimit(1)
                                if snapshot.kind != .manual {
                                    Text(snapshot.kind == .automatic ? "auto" : "safety").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.18), in: Capsule())
                                }
                            }
                            Text(snapshot.date.formatted(date: .abbreviated, time: .shortened) + " · \(snapshot.words.formatted()) words").font(.caption).foregroundStyle(.secondary)
                        }.tag(snapshot.id).padding(.vertical, 2)
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: selectedID) { _, _ in loadChanges() }
            }
        }.padding(16)
    }

    // MARK: Right: what changed

    @ViewBuilder private var detail: some View {
        if let snapshot = selected {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.name).font(.title3.weight(.semibold))
                        Text(snapshot.date.formatted(date: .complete, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        if !snapshot.note.isEmpty { Text(snapshot.note).font(.callout).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button("Rename…") { renameName = snapshot.name; renameNote = snapshot.note; renaming = true }
                    Button("Delete…", role: .destructive) { confirmDelete = true }
                }
                summary(snapshot)
                changeList
                Divider()
                diffArea
                HStack {
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                    Button("Restore This \(scope.isProject ? "Chapter" : "Document")", action: restoreOne)
                        .disabled(busy || selectedChange == nil || selectedChange?.status == .unchanged || selectedChange?.status == .added)
                    Button("Restore Entire Draft…") { confirmDraft = true }.disabled(busy || changes.allSatisfy { $0.status == .unchanged || $0.status == .added })
                    Button("Done", action: close).keyboardShortcut(.cancelAction)
                }
            }.padding(18)
        } else {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "clock.arrow.circlepath").font(.system(size: 34)).foregroundStyle(.tertiary)
                Text("Pick a snapshot to see what has changed since.").foregroundStyle(.secondary)
                Text("Snapshots are plain copies in a hidden “.sable-revisions” folder, so they sync and back up with everything else.").font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center).frame(maxWidth: 380)
                Spacer()
                HStack { Spacer(); Button("Done", action: close).keyboardShortcut(.cancelAction) }
            }.padding(18).frame(maxWidth: .infinity)
        }
    }

    private func summary(_ snapshot: Snapshot) -> some View {
        let changed = changes.filter { $0.status != .unchanged }
        let added = changes.filter { $0.wordsNow > $0.wordsThen }.reduce(0) { $0 + $1.delta }
        let removed = changes.filter { $0.wordsNow < $0.wordsThen }.reduce(0) { $0 + $1.delta }
        return HStack(spacing: 16) {
            Text("\(snapshot.words.formatted()) words then")
            Text("\(changes.reduce(0) { $0 + $1.wordsNow }.formatted()) now")
            Text(changed.isEmpty ? "Nothing has changed" : "\(changed.count) \(changed.count == 1 ? "file" : "files") changed")
            if !changed.isEmpty { Text("+\(added.formatted()) / \(removed.formatted()) words").monospacedDigit() }
        }.font(.caption).foregroundStyle(.secondary)
    }

    private var changeList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(changes) { change in
                    Button { selectedPath = change.path; loadDiff() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: icon(change.status)).foregroundStyle(color(change.status)).frame(width: 16)
                            Text(change.title).lineLimit(1)
                            Spacer()
                            Text(label(change)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .padding(.vertical, 4).padding(.horizontal, 8).contentShape(Rectangle())
                        .background(selectedPath == change.path ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .opacity(change.status == .unchanged ? 0.55 : 1)
                    }.buttonStyle(.plain)
                }
            }
        }
        .frame(height: 130)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var diffArea: some View {
        if let change = selectedChange {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 14) {
                    Text(change.title).font(.callout.weight(.medium))
                    Label("in the snapshot, gone now", systemImage: "strikethrough").foregroundStyle(.red)
                    Label("new since", systemImage: "plus").foregroundStyle(.green)
                }.font(.caption)
                if change.status == .unchanged { Text("This file is the same as the snapshot.").font(.callout).foregroundStyle(.secondary).padding(.top, 6); Spacer() }
                else { DiffTextView(pieces: pieces, family: family) }
            }
        } else {
            Text(changes.contains { $0.status != .unchanged } ? "Choose a file above to see the changes marked in its text." : "").font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func icon(_ status: ChangeStatus) -> String {
        switch status {
        case .unchanged: return "equal.circle"
        case .changed: return "pencil.circle.fill"
        case .added: return "plus.circle.fill"
        case .removed: return "minus.circle.fill"
        }
    }
    private func color(_ status: ChangeStatus) -> Color {
        switch status {
        case .unchanged: return .secondary
        case .changed: return .orange
        case .added: return .green
        case .removed: return .red
        }
    }
    private func label(_ change: FileChange) -> String {
        switch change.status {
        case .unchanged: return "unchanged"
        case .added: return "added · \(change.wordsNow.formatted()) words"
        case .removed: return "deleted since · \(change.wordsThen.formatted()) words"
        case .changed: return (change.delta >= 0 ? "+" : "") + change.delta.formatted() + " words"
        }
    }

    // MARK: Work

    private func reload(select: String? = nil) {
        snapshots = Revisions.list(in: scope.root)
        selectedID = select ?? (snapshots.contains { $0.id == selectedID } ? selectedID : snapshots.first?.id)
        loadChanges()
    }

    private func loadChanges() {
        pieces = []
        selectedPath = nil
        guard let snapshot = selected else { changes = []; return }
        let root = scope.root, files = scope.files, overrides = live
        Task {
            let found = await Task.detached { (try? Revisions.changes(from: snapshot, root: root, files: files, liveText: overrides)) ?? [] }.value
            guard selectedID == snapshot.id else { return }
            changes = found
            selectedPath = found.first { $0.status != .unchanged }?.path
            loadDiff()
        }
    }

    private func loadDiff() {
        guard let snapshot = selected, let change = selectedChange, change.status != .unchanged else { pieces = []; return }
        let root = scope.root, overrides = live
        Task {
            let result = await Task.detached { () -> [DiffPiece] in
                let old = (try? Revisions.text(of: change.path, in: snapshot, root: root)) ?? ""
                let url = root.appendingPathComponent(change.path)
                let now: String
                if change.status == .removed { now = "" }
                else { now = overrides[url.standardizedFileURL] ?? ((try? String(contentsOf: url, encoding: .utf8)) ?? "") }
                return Revisions.diff(from: old, to: now)
            }.value
            guard selectedPath == change.path else { return }
            pieces = result
        }
    }

    private func saveSnapshot() {
        let title = name.trimmingCharacters(in: .whitespaces)
        let label = title.isEmpty ? "Snapshot " + Date().formatted(date: .abbreviated, time: .shortened) : title
        busy = true
        let root = scope.root, files = scope.files, order = scope.chapterOrder, overrides = live, detail = note
        Task {
            do {
                let made = try await Task.detached { try Revisions.create(name: label, note: detail, root: root, files: files, chapterOrder: order, liveText: overrides) }.value
                name = ""; note = ""
                message = "Saved “\(made.name)”: \(made.files.count) \(made.files.count == 1 ? "file" : "files"), \(made.words.formatted()) words."
                reload(select: made.id)
            } catch { message = "Could not save the snapshot: \(error.localizedDescription)" }
            busy = false
        }
    }

    private func saveDetails() {
        guard let snapshot = selected else { return }
        let title = renameName.trimmingCharacters(in: .whitespaces)
        do { try Revisions.rename(snapshot, name: title.isEmpty ? snapshot.name : title, note: renameNote, in: scope.root); reload(select: snapshot.id) }
        catch { message = "Could not rename: \(error.localizedDescription)" }
    }

    private func deleteSelected() {
        guard let snapshot = selected else { return }
        Revisions.delete(snapshot, in: scope.root)
        selectedID = nil
        reload()
    }

    /// A snapshot of right now, so nothing a restore replaces is lost.
    private func safetySnapshot(_ label: String) throws {
        try Revisions.create(name: label, kind: .safety, root: scope.root, files: scope.files, chapterOrder: scope.chapterOrder, liveText: live)
    }

    private func restoreOne() {
        guard let snapshot = selected, let change = selectedChange else { return }
        do {
            try safetySnapshot("Before restoring “\(change.title)”")
            try put(change.path, from: snapshot)
            message = "Restored “\(change.title)” to “\(snapshot.name)”. A safety snapshot of the version it replaced is in the list." + (isOpen(change.path) ? " It is open, so press ⌘Z to reverse it, or ⌘S to keep it." : "")
            filesChanged()
            reload(select: snapshot.id)
        } catch { message = "Could not restore: \(error.localizedDescription). Nothing was changed." }
    }

    private func restoreDraft() {
        guard let snapshot = selected else { return }
        do {
            try safetySnapshot("Before restoring “\(snapshot.name)”")
            var count = 0
            for change in changes where change.status == .changed || change.status == .removed {
                try put(change.path, from: snapshot)
                count += 1
            }
            if let order = snapshot.chapterOrder { restoreOrder(order) }
            message = "Restored \(count) \(count == 1 ? "file" : "files") to “\(snapshot.name)”. A safety snapshot of how it was is in the list."
            filesChanged()
            reload(select: snapshot.id)
        } catch { message = "Could not restore: \(error.localizedDescription)" }
    }

    private func isOpen(_ path: String) -> Bool {
        scope.openURL?.standardizedFileURL == scope.root.appendingPathComponent(path).standardizedFileURL
    }

    /// A file that is open in the editor is changed on the page, where ⌘Z works; every other file is rewritten on disk.
    private func put(_ path: String, from snapshot: Snapshot) throws {
        if isOpen(path) { replaceOpenText(try Revisions.text(of: path, in: snapshot, root: scope.root)) }
        else { try Revisions.restore(path, from: snapshot, root: scope.root) }
    }
}

/// Text with the changes marked: new words underlined in green, removed words struck through in red.
struct DiffTextView: NSViewRepresentable {
    let pieces: [DiffPiece]
    let family: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        if let text = scroll.documentView as? NSTextView {
            text.isEditable = false
            text.isSelectable = true
            text.drawsBackground = false
            text.textContainerInset = NSSize(width: 6, height: 8)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: 14) ?? .systemFont(ofSize: 14)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 6
        let output = NSMutableAttributedString()
        for piece in pieces {
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: style, .foregroundColor: NSColor.labelColor]
            switch piece.kind {
            case .same: attributes[.foregroundColor] = NSColor.secondaryLabelColor
            case .inserted:
                attributes[.backgroundColor] = NSColor.systemGreen.withAlphaComponent(0.22)
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attributes[.underlineColor] = NSColor.systemGreen
            case .deleted:
                attributes[.backgroundColor] = NSColor.systemRed.withAlphaComponent(0.16)
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attributes[.strikethroughColor] = NSColor.systemRed
                attributes[.foregroundColor] = NSColor.secondaryLabelColor
            }
            output.append(NSAttributedString(string: piece.text, attributes: attributes))
        }
        if text.attributedString() != output { text.textStorage?.setAttributedString(output) }
    }
}
