import SwiftUI
import AppKit

/// What the Find & Replace sheet needs to know about the window that opened it.
struct FindRequest: Identifiable {
    let id = UUID()
    let root: URL
    /// The file open in the editor, whose unsaved text is what gets searched and changed.
    let openURL: URL?
    let openText: String
}

/// Find and replace across every Markdown file in the writing folder or the Fiction Project, with a preview and an undo.
struct FindReplaceSheet: View {
    let request: FindRequest
    let replaceOpenText: (String) -> Void
    let open: (URL, NSRange) -> Void
    let filesChanged: () -> Void
    let close: () -> Void
    @State private var options = SearchOptions()
    @State private var replacement = ""
    @State private var results: [FileHits] = []
    @State private var skipped: Set<URL> = []
    @State private var searching = false
    @State private var confirming = false
    @State private var receipt: ReplaceReceipt?
    @State private var openTextReplaced = false
    @State private var message: String?

    private var included: [FileHits] { results.filter { !skipped.contains($0.url) } }
    private var matchCount: Int { included.reduce(0) { $0 + $1.hits.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Find & Replace in \(request.root.lastPathComponent)").font(.title3.weight(.semibold))
            Form {
                TextField("Find", text: $options.query)
                TextField("Replace with", text: $replacement)
                HStack(spacing: 18) {
                    Toggle("Match case", isOn: $options.caseSensitive)
                    Toggle("Whole word", isOn: $options.wholeWord)
                }
            }.formStyle(.columns)

            resultsList

            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Text(summary).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if searching { ProgressView().controlSize(.small) }
                if receipt != nil || openTextReplaced {
                    Button("Undo Replace", action: undo)
                }
                Button("Done", action: close).keyboardShortcut(.cancelAction)
                Button("Replace All…") { confirming = true }
                    .keyboardShortcut(.defaultAction)
                    .disabled(matchCount == 0)
                    .confirmationDialog("Replace \(matchCount) \(matchCount == 1 ? "match" : "matches") in \(included.count) \(included.count == 1 ? "file" : "files")?",
                                        isPresented: $confirming, titleVisibility: .visible) {
                        Button("Replace All", role: .destructive, action: replaceAll)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(replacement.isEmpty ? "Every match will be removed. You can undo this from here." : "Each will become “\(replacement)”. You can undo this from here.")
                    }
            }
        }
        .padding(22).frame(width: 580, height: 560)
        .task(id: options) { await search() }
    }

    private var summary: String {
        if options.query.isEmpty { return "Type something to find." }
        if searching && results.isEmpty { return "Searching…" }
        if results.isEmpty { return "No matches." }
        return "\(matchCount) \(matchCount == 1 ? "match" : "matches") in \(included.count) of \(results.count) \(results.count == 1 ? "file" : "files")"
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(results) { file in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Toggle(isOn: Binding(get: { !skipped.contains(file.url) }, set: { on in
                                if on { skipped.remove(file.url) } else { skipped.insert(file.url) }
                            })) {
                                Text(file.path).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                            }.toggleStyle(.checkbox)
                            Spacer()
                            Text("\(file.hits.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                        ForEach(file.hits.prefix(4)) { hit in
                            Button { open(file.url, hit.range) } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("\(hit.line)").font(.caption2).foregroundStyle(.tertiary).monospacedDigit().frame(width: 34, alignment: .trailing)
                                    Text(highlighted(hit)).font(.caption).lineLimit(1).foregroundStyle(.secondary)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain).help("Open this file at the match")
                        }
                        if file.hits.count > 4 {
                            Text("and \(file.hits.count - 4) more").font(.caption2).foregroundStyle(.tertiary).padding(.leading, 42)
                        }
                    }
                    .opacity(skipped.contains(file.url) ? 0.45 : 1)
                }
                if results.isEmpty && !options.query.isEmpty && !searching {
                    Text("Nothing matches. Try turning off Match case or Whole word.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }

    private func highlighted(_ hit: SearchHit) -> AttributedString {
        var text = AttributedString(hit.snippet)
        if let range = Range(hit.snippetRange, in: text) {
            text[range].font = .caption.weight(.bold)
            text[range].foregroundColor = .primary
        }
        return text
    }

    // MARK: Work

    private func liveText() -> [URL: String] {
        guard let url = request.openURL else { return [:] }
        return [url.standardizedFileURL: request.openText]
    }

    private func search() async {
        message = nil
        guard !options.query.isEmpty else { results = []; return }
        searching = true
        try? await Task.sleep(nanoseconds: 220_000_000)
        guard !Task.isCancelled else { return }
        let root = request.root, current = options, live = liveText()
        let found = await Task.detached(priority: .userInitiated) { ProjectSearch.find(in: root, options: current, liveText: live) }.value
        guard !Task.isCancelled else { return }
        results = found
        skipped = skipped.filter { url in found.contains { $0.url == url } }
        searching = false
    }

    private func replaceAll() {
        let chosen = included
        let current = options, text = replacement
        let openURL = request.openURL?.standardizedFileURL
        let diskFiles = chosen.map(\.url).filter { $0.standardizedFileURL != openURL }
        message = nil
        Task {
            do {
                var count = 0, files = 0
                let root = request.root
                // A snapshot first, so a replacement that turns out to be a mistake can be taken back after this window closes.
                let outcome = try await Task.detached { () -> ReplaceReceipt in
                    if !diskFiles.isEmpty {
                        _ = try? Revisions.create(name: "Before replacing “\(current.query)” with “\(text)”", kind: .safety, root: root, files: diskFiles)
                    }
                    return try ProjectSearch.replace(in: diskFiles, options: current, with: text)
                }.value
                count += outcome.replacements
                files += outcome.files
                receipt = outcome.files > 0 ? outcome : nil
                if let openURL, chosen.contains(where: { $0.url.standardizedFileURL == openURL }) {
                    let changed = ProjectSearch.replaced(request.openText, options: current, with: text)
                    if changed.count > 0 {
                        replaceOpenText(changed.text)
                        openTextReplaced = true
                        count += changed.count
                        files += 1
                    }
                }
                message = "Replaced \(count) \(count == 1 ? "match" : "matches") in \(files) \(files == 1 ? "file" : "files")." + (openTextReplaced ? " The open document changed on the page: press ⌘Z or Undo Replace to reverse it, and ⌘S to save it." : "")
                filesChanged()
                await search()
            } catch {
                message = "Could not replace: \(error.localizedDescription). Nothing was changed."
            }
        }
    }

    private func undo() {
        if let receipt {
            do { try ProjectSearch.restore(receipt) } catch { message = "Could not undo: \(error.localizedDescription)"; return }
            self.receipt = nil
            filesChanged()
        }
        if openTextReplaced {
            NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
            openTextReplaced = false
        }
        message = "Put everything back."
        Task { await search() }
    }
}

/// A short reference for the Markdown Sable understands, opened from the Help menu.
struct MarkdownCheatSheet: View {
    private let rows: [(String, String)] = [
        ("**bold**", "Bold  ⌘B"), ("*italic*", "Italic  ⌘I"), ("~~struck~~", "Strikethrough  ⇧⌘X"), ("`code`", "Inline code  ⇧⌘K"),
        ("# Chapter", "Heading — press ⇧⌘H to cycle # ## ###"), ("[words](https://…)", "Link  ⌘K (a copied address becomes the destination)"),
        ("- item   1. item", "Lists — Return continues, Return on an empty item ends, Tab indents"),
        ("- [ ] task", "Task list"), ("> quoted", "Quote"), ("* * *", "Scene break  ⇧⌘L"),
        ("![note](picture.png)", "Image (shown as text; Reading Mode and exports keep the words)"),
        ("<!-- a note -->", "A note to yourself: dimmed, and never exported"),
        ("[^1]  and  [^1]: text", "Footnote"), ("| a | b |", "Table rows appear in a fixed-width font"),
        ("\\*", "A backslash keeps a symbol from doing anything"),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Markdown cheat sheet").font(.title3.weight(.semibold))
            Text("Written by Claude Code.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 9) {
                    ForEach(rows, id: \.0) { row in
                        GridRow {
                            Text(row.0).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                            Text(row.1).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("The Markdown menu has every one of these. Settings → Writing can dim the symbols and turn on curly quotes and dashes.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(22).frame(minWidth: 520, minHeight: 460)
    }
}
