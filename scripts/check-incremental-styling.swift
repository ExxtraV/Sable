import AppKit
import SwiftUI
import QuillCore

// Thousands of seeded random edits, made through the same NSTextView entry points typing uses, each followed by a
// comparison against a from-scratch restyle of the same text. The two must match run by run: text-storage attributes,
// the temporary attributes Sable draws (focus dimming, prose suggestions), the name ranges the shimmer plays on, and the
// SwiftUI binding's copy of the text. Any shortcut in restyling after an edit has to keep this passing.
//
// The editor hands typing to the binding in batches, so after each edit the check settles it one of the ways the app
// does (a pause, the document committing its editors before a save, losing focus) or leaves it pending for a while, and
// proves that a SwiftUI update with the binding's older text never throws typing away. Once settled, the binding must
// hold exactly the editor's text and the status bar's counts must match a fresh count.
//
// QUILL_FUZZ_SEED overrides the seed, QUILL_FUZZ_EDITS the number of edits per configuration (for long local soak runs),
// and QUILL_FUZZ_SABOTAGE=1 corrupts one attribute on purpose to prove the comparison notices.

@main enum IncrementalStylingChecks {
    @MainActor static func main() {
        let environment = ProcessInfo.processInfo.environment
        let seed = environment["QUILL_FUZZ_SEED"].flatMap { UInt64($0) }
        let edits = environment["QUILL_FUZZ_EDITS"].flatMap { Int($0) }
        let sabotage = environment["QUILL_FUZZ_SABOTAGE"] == "1"
        let started = Date()

        var defaults = EditorSettings.defaults
        defaults.nameShimmer = false // The shimmer paints on a timer; name ranges are still compared.
        var everything = EditorSettings.everything
        everything.nameShimmer = false
        everything.focusGradient = false // Classic dimming depends only on the text and caret, so it is compared every edit.
        everything.typewriterMode = "room"
        var gradient = EditorSettings.defaults
        gradient.nameShimmer = false
        gradient.focusParagraph = true

        let overrides = [seed.map { "QUILL_FUZZ_SEED=\($0)" }, edits.map { "QUILL_FUZZ_EDITS=\($0)" }].compactMap { $0 }
        let reproduce = overrides.isEmpty ? "the check as is (default seeds)" : overrides.joined(separator: " ")
        var results: [String] = []
        results.append(Fuzz(name: "defaults", settings: defaults, words: 600, seed: seed ?? 0xA11CE,
                            edits: edits ?? 2_000, gradientEvery: 0, sabotage: sabotage, reproduce: reproduce).run())
        results.append(Fuzz(name: "everything on", settings: everything, words: 400, seed: seed.map { $0 &+ 1 } ?? 0xB0B,
                            edits: edits.map { max(1, $0 / 3) } ?? 600, gradientEvery: 0, sabotage: false, reproduce: reproduce).run())
        results.append(Fuzz(name: "gradient focus", settings: gradient, words: 600, seed: seed.map { $0 &+ 2 } ?? 0xC0FFEE,
                            edits: edits.map { max(1, $0 / 10) } ?? 300, gradientEvery: 10, sabotage: false, reproduce: reproduce).run())
        let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
        print("Passed: incremental styling matches a full restyle after every random edit (\(results.joined(separator: "; "))) in \(seconds)s.")
    }
}

// MARK: - A document to commit and save

/// Stands in for the window's document: it counts as edited while typing is pending and asks the editor to commit before
/// saving, exactly as AppKit's NSDocument does for any document.
final class FuzzDocument: NSDocument {
    var read: () -> String = { "" }
    override func data(ofType typeName: String) throws -> Data { Data(read().utf8) }
}

final class SaveWaiter: NSObject {
    var saved: Bool?
    @objc func document(_ document: NSDocument, didSave: Bool, contextInfo: UnsafeMutableRawPointer?) { saved = didSave }
}

// MARK: - Comparing styling

struct StyleRun: Equatable {
    var range: NSRange
    var attributes: String
}

@MainActor
enum StyleSnapshot {
    private static let appearances = [NSAppearance(named: .aqua)!, NSAppearance(named: .darkAqua)!]
    /// The temporary attributes Sable itself sets; spelling and grammar marks belong to AppKit.
    static let ownedTemporaryKeys: Set<NSAttributedString.Key> = [.foregroundColor, .strikethroughStyle, .strikethroughColor]

    /// A value in a form that compares by what it looks like, not by object identity. Dynamic colors are new objects on
    /// every styling pass, so they are resolved in both light and dark.
    static func describe(_ value: Any) -> String {
        switch value {
        case let font as NSFont:
            return "\(font.fontName)@\(font.pointSize)"
        case let color as NSColor:
            return appearances.map { appearance in
                var text = color.description
                appearance.performAsCurrentDrawingAppearance {
                    if let rgb = color.usingColorSpace(.sRGB) {
                        text = String(format: "%.4f,%.4f,%.4f,%.4f", rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent)
                    }
                }
                return text
            }.joined(separator: "|")
        case let style as NSParagraphStyle:
            return "paragraph(\(style.lineSpacing),\(style.paragraphSpacing),\(style.paragraphSpacingBefore),\(style.alignment.rawValue),"
                + "\(style.headIndent),\(style.firstLineHeadIndent),\(style.tailIndent),\(style.lineHeightMultiple),"
                + "\(style.minimumLineHeight),\(style.maximumLineHeight),\(style.tabStops.count),\(style.defaultTabInterval))"
        case let url as URL:
            return url.absoluteString
        default:
            return String(describing: value)
        }
    }

    static func describe(_ attributes: [NSAttributedString.Key: Any]) -> String {
        attributes.keys.sorted { $0.rawValue < $1.rawValue }.map { "\($0.rawValue)=\(describe(attributes[$0]!))" }.joined(separator: "; ")
    }

    private static func append(_ runs: inout [StyleRun], _ range: NSRange, _ attributes: String) {
        if let last = runs.last, last.attributes == attributes, NSMaxRange(last.range) == range.location {
            runs[runs.count - 1].range.length += range.length
        } else {
            runs.append(StyleRun(range: range, attributes: attributes))
        }
    }

    static func storage(of view: NSTextView) -> [StyleRun] {
        var runs: [StyleRun] = []
        guard let storage = view.textStorage else { return runs }
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attributes, range, _ in
            append(&runs, range, describe(attributes))
        }
        return runs
    }

    static func temporary(of view: NSTextView, keys: Set<NSAttributedString.Key>) -> [StyleRun] {
        var runs: [StyleRun] = []
        guard let layout = view.layoutManager, let length = view.textStorage?.length else { return runs }
        var index = 0
        while index < length {
            var effective = NSRange(location: 0, length: 0)
            let attributes = layout.temporaryAttributes(atCharacterIndex: index, longestEffectiveRange: &effective,
                                                        in: NSRange(location: index, length: length - index))
            let end = max(NSMaxRange(effective), index + 1)
            append(&runs, NSRange(location: index, length: end - index), describe(attributes.filter { keys.contains($0.key) }))
            index = end
        }
        return runs
    }

    /// Where two run lists first disagree, with the text there, or nil when they match.
    static func difference(_ incremental: [StyleRun], _ full: [StyleRun], text: String) -> String? {
        guard incremental != full else { return nil }
        let index = zip(incremental, full).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(incremental.count, full.count)
        func show(_ runs: [StyleRun]) -> String {
            let source = text as NSString
            let shown = runs[min(index, runs.count)..<min(index + 2, runs.count)].map { run in
                let excerpt = NSMaxRange(run.range) <= source.length ? source.substring(with: NSRange(location: run.range.location, length: min(run.range.length, 60))) : "?"
                return "\(run.range) \(excerpt.debugDescription)\n        \(run.attributes)"
            }
            return shown.isEmpty ? "(no more runs)" : shown.joined(separator: "\n      ")
        }
        return "first difference at run \(index):\n    incremental: \(show(incremental))\n    full:        \(show(full))"
    }
}

// MARK: - Random edits

@MainActor
struct Fuzz {
    let name: String
    var settings: EditorSettings
    let words: Int
    let seed: UInt64
    let edits: Int
    /// Every this many edits, compare gradient focus against an identically hosted view (0 = never).
    let gradientEvery: Int
    let sabotage: Bool
    /// How to run this exact sequence again.
    let reproduce: String

    private static let letters = Array("etaoinshrdlucmfwypvbgkjqxz ETAOIN     ")
    private static let symbols = Array("*_`~#>-|[]()!<.,;:'\"\n")
    private static let lineTokens = ["```\n", "```", "~~~\n", "---\n", "---", "<!--", "-->", "<!-- ", "# ", "## ", "===\n", "> ",
                                     "- [ ] ", "- [x] ", "- ", "1. ", "| a | b |\n", "* * *\n", "\n", "***", "__"]
    private static let inlineTokens = ["*", "**", "***", "`", "_", "__", "~~", "[", "](https://example.com)", "![", "<!--", "-->",
                                       "```", "[^9]", "\\", "\n\n", "Marren", "the Pier", "very"]
    private static let removableTokens = ["```", "~~~", "---", "<!--", "-->", "**", "*", "`", "# ", "> ", "[", "]", "|", "\n", "_"]
    private static let replacements = ["tide", "Marren Vale", "*lantern*", "just", "`key`", "**", "", "\"", "—", "🌙"]
    private static let noWhere = NSRange(location: NSNotFound, length: 0)

    func run() -> String {
        let started = Date()
        var rng = SeededRandom(seed: seed)
        let initial = ManuscriptFixture.novel(words: words, seed: seed)
        let host = HostedEditor(text: initial, settings: settings)
        let editor = host.editor
        let document = FuzzDocument()
        document.read = { [unowned host] in host.text }
        host.document = document
        host.apply(host.settings)
        var settles: [String: Int] = [:]
        let passesBefore = (editor.style.fullPasses, editor.style.regionPasses)
        let initialLength = (initial as NSString).length
        var caret = initialLength / 2
        var counts: [String: Int] = [:]
        var gradientComparisons = 0

        func location() -> Int {
            let length = (editor.string as NSString).length
            if rng.chance(0.7) { return min(length, max(0, caret + rng.int(-200...200))) }
            return rng.int(0...length)
        }
        func place(_ at: Int, length: Int = 0) {
            let total = (editor.string as NSString).length
            let start = min(max(0, at), total)
            editor.setSelectedRange(NSRange(location: start, length: min(length, total - start)))
        }
        func type(_ text: String) { editor.insertText(text, replacementRange: Self.noWhere) }

        for step in 1...edits {
            let length = (editor.string as NSString).length
            // Keep the document near its starting size: grow it when it shrinks, trim it when it swells.
            let roll = length > initialLength * 2 ? rng.int(40..<52) : (length < initialLength / 2 ? rng.int(64..<70) : rng.int(0..<100))
            var operation = ""
            host.undo.beginUndoGrouping()
            switch roll {
            case 0..<30:
                let character = String(rng.chance(0.8) ? rng.pick(Self.letters) : rng.pick(Self.symbols))
                place(location())
                type(character)
                operation = "type \(character.debugDescription)"
            case 30..<36:
                place(location())
                editor.insertNewline(nil)
                operation = "return"
            case 36..<46:
                place(location())
                editor.deleteBackward(nil)
                operation = "delete backward"
            case 46..<50:
                place(location())
                editor.deleteForward(nil)
                operation = "delete forward"
            case 50..<55:
                place(location(), length: rng.chance(0.3) ? rng.int(40...600) : rng.int(1...40))
                operation = "delete range \(editor.selectedRange())"
                editor.deleteBackward(nil)
            case 55..<59:
                place(location(), length: rng.int(1...40))
                let replacement = rng.pick(Self.replacements)
                operation = "replace \(editor.selectedRange()) with \(replacement.debugDescription)"
                if replacement.isEmpty { editor.deleteBackward(nil) } else { type(replacement) }
            case 59..<64:
                place(location(), length: rng.chance(0.2) ? rng.int(1...80) : 0)
                let chunk = ManuscriptFixture.chunk(&rng)
                operation = "paste \((chunk as NSString).length) characters over \(editor.selectedRange())"
                type(chunk)
            case 64..<74:
                let source = editor.string as NSString
                let lineStart = rng.chance(0.05) ? 0 : source.lineRange(for: NSRange(location: min(location(), source.length), length: 0)).location
                let token = rng.pick(Self.lineTokens)
                place(lineStart)
                type(token)
                operation = "line token \(token.debugDescription) at \(lineStart)"
            case 74..<80:
                let token = rng.pick(Self.inlineTokens)
                place(location())
                type(token)
                operation = "inline token \(token.debugDescription)"
            case 80..<86:
                let token = rng.pick(Self.removableTokens)
                let source = editor.string as NSString
                let from = rng.int(0...source.length)
                var found = source.range(of: token, range: NSRange(location: from, length: source.length - from))
                if found.location == NSNotFound { found = source.range(of: token) }
                if found.location != NSNotFound {
                    place(found.location, length: found.length)
                    editor.deleteBackward(nil)
                }
                operation = "remove \(token.debugDescription) at \(found.location)"
            case 86..<91:
                operation = "undo"
            case 91..<93:
                operation = "redo"
            case 93..<97:
                place(location())
                editor.setMarkedText("k", selectedRange: NSRange(location: 1, length: 0), replacementRange: Self.noWhere)
                editor.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0), replacementRange: Self.noWhere)
                precondition(editor.hasMarkedText(), "Marked text is in place")
                if rng.chance(0.75) {
                    type("家")
                    operation = "marked text, committed"
                } else {
                    // Without a commit AppKit sends no text change; the editor restyles what was composed when it unmarks.
                    editor.unmarkText()
                    operation = "marked text, unmarked"
                }
            default:
                var changed = host.settings
                switch rng.int(0..<5) {
                case 0: changed.theme = rng.pick(WritingTheme.all.map(\.id)); operation = "theme \(changed.theme)"
                case 1: changed.dimMarkers.toggle(); operation = "dim markers \(changed.dimMarkers)"
                case 2: changed.names.toggle(); operation = "names \(changed.names)"
                case 3: changed.review.toggle(); operation = "review \(changed.review)"
                default: changed.fontSize = rng.pick([16, 19, 22]); operation = "font size \(changed.fontSize)"
                }
                host.apply(changed)
            }
            host.undo.endUndoGrouping()
            if operation == "undo", host.undo.canUndo { host.undo.undo() }
            if operation == "redo", host.undo.canRedo { host.undo.redo() }
            editor.breakUndoCoalescing()
            counts[operation.split(separator: " ").prefix(2).joined(separator: " "), default: 0] += 1
            caret = editor.selectedRange().location
            host.flush()

            if sabotage, step == edits / 2, editor.textStorage!.length > 20 {
                editor.textStorage!.addAttribute(.kern, value: 3, range: NSRange(location: 10, length: 2))
            }
            guard !editor.hasMarkedText() else { continue }
            settles[settle(host, document: document, rng: &rng, step: step, operation: operation), default: 0] += 1
            compare(host, step: step, operation: operation)
            if gradientEvery > 0, step % gradientEvery == 0 {
                compareGradient(host, step: step, operation: operation)
                gradientComparisons += 1
            }
        }
        host.commitText()
        compare(host, step: edits, operation: "final commit")
        if sabotage { fail(host, step: edits, operation: "sabotage", "the sabotaged attribute went unnoticed") }
        let ops = counts.values.reduce(0, +)
        let extra = gradientComparisons > 0 ? ", \(gradientComparisons) gradient comparisons" : ""
        let full = editor.style.fullPasses - passesBefore.0, region = editor.style.regionPasses - passesBefore.1
        // Most edits are typing in prose; if they stopped taking the region path, typing would be slow again.
        if region <= full { fail(host, step: edits, operation: "all", "only \(region) of \(region + full) styling passes restyled a region") }
        let how = settles.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
        return "\(name): \(ops) edits from seed \(seed)\(extra), \(region) region and \(full) full passes, binding settled by \(how), \(String(format: "%.1f", Date().timeIntervalSince(started)))s"
    }

    /// Hands pending typing to the binding one of the ways the app does, or leaves it pending. Returns how it settled.
    private func settle(_ host: HostedEditor, document: FuzzDocument, rng: inout SeededRandom, step: Int, operation: String) -> String {
        let editor = host.editor, coordinator = host.coordinator
        guard coordinator.hasPendingText else { return "nothing pending" }
        if host.text != coordinator.syncedText { fail(host, step: step, operation: operation, "the binding changed while typing was pending") }
        if !document.isDocumentEdited { fail(host, step: step, operation: operation, "a document with pending typing doesn't count as edited") }
        let typed = editor.string
        switch rng.int(0..<100) {
        case 0..<30:
            return "staying pending"
        case 30..<55:
            host.commitText()
            return "a pause"
        case 55..<70:
            return saveThroughAppKit(host, document: document, step: step, operation: operation)
        case 70..<82:
            // SwiftUI redraws for some other reason while the binding still holds the older text.
            host.apply(host.settings)
            if editor.string != typed { fail(host, step: step, operation: operation, "a SwiftUI update with the binding's older text replaced pending typing") }
            host.commitText()
            return "a redraw, then a pause"
        case 82..<90:
            host.window.makeFirstResponder(nil)
            host.window.makeFirstResponder(editor)
            return "losing focus"
        case 90..<93:
            // An autosave ran while typing was pending, so it saved older text: the document must stay edited.
            document.updateChangeCount(.changeCleared)
            document.fileModificationDate = Date()
            host.commitText()
            if !document.isDocumentEdited { fail(host, step: step, operation: operation, "typing that missed an autosave left the document looking saved") }
            document.updateChangeCount(.changeCleared)
            return "an autosave"
        case 93..<95 where step % 4 == 0:
            // The real idle timer.
            let deadline = Date().addingTimeInterval(NativeEditor.Coordinator.longestWait + 0.5)
            while coordinator.hasPendingText, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
            if coordinator.hasPendingText { fail(host, step: step, operation: operation, "the pause timer never handed typing over") }
            return "the timer"
        default:
            host.commitText()
            return "a pause"
        }
    }

    /// A real NSDocument save, which must commit the editor's pending typing before it writes.
    private func saveThroughAppKit(_ host: HostedEditor, document: FuzzDocument, step: Int, operation: String) -> String {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("quill-fuzz-save.md")
        let waiter = SaveWaiter()
        document.save(to: url, ofType: "net.daringfireball.markdown", for: .saveOperation, delegate: waiter,
                      didSave: #selector(SaveWaiter.document(_:didSave:contextInfo:)), contextInfo: nil)
        let deadline = Date().addingTimeInterval(10)
        while waiter.saved == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        guard waiter.saved == true, let written = try? String(contentsOf: url, encoding: .utf8) else {
            fail(host, step: step, operation: operation, "saving the document failed")
        }
        if written != host.editor.string { fail(host, step: step, operation: operation, "a save wrote text without the pending typing") }
        document.updateChangeCount(.changeCleared)
        return "a save"
    }

    /// A fresh view, never edited, styled from scratch with the same settings.
    private func reference(for host: HostedEditor) -> WritingTextView {
        let view = WritingTextView(frame: host.editor.frame)
        view.isRichText = false
        HostedEditor.configure(view, host.settings, highlighter: host.highlighter)
        view.string = host.editor.string
        view.setSelectedRange(host.editor.selectedRange())
        view.decorate()
        return view
    }

    private func compare(_ host: HostedEditor, step: Int, operation: String) {
        let editor = host.editor
        let text = editor.string
        if !host.coordinator.hasPendingText {
            if host.text != text { fail(host, step: step, operation: operation, "the SwiftUI binding holds different text from the editor") }
            let cuts = host.settings.review ? Prose.suggestions(in: text, words: host.settings.words).count : nil
            let stats = host.commands.stats
            if stats?.text != text || stats?.words != Prose.wordCount(text) || stats?.cuts != cuts {
                fail(host, step: step, operation: operation, "the status bar's counts are \(stats.map { "\($0.words) words, \($0.cuts.map(String.init) ?? "no") cuts" } ?? "missing"), not \(Prose.wordCount(text)) words, \(cuts.map(String.init) ?? "no") cuts")
            }
        }
        let full = reference(for: host)
        precondition(full.string == text, "Styling never changes the Markdown")
        if let difference = StyleSnapshot.difference(StyleSnapshot.storage(of: editor), StyleSnapshot.storage(of: full), text: text) {
            fail(host, step: step, operation: operation, "text attributes differ, \(difference)")
        }
        // Gradient dimming depends on layout and scrolling, so it's compared separately against a hosted view.
        var keys = StyleSnapshot.ownedTemporaryKeys
        if host.settings.focusParagraph && host.settings.focusGradient { keys.remove(.foregroundColor) }
        if let difference = StyleSnapshot.difference(StyleSnapshot.temporary(of: editor, keys: keys), StyleSnapshot.temporary(of: full, keys: keys), text: text) {
            fail(host, step: step, operation: operation, "temporary attributes (focus or prose suggestions) differ, \(difference)")
        }
        if editor.nameRanges != full.nameRanges {
            fail(host, step: step, operation: operation, "name ranges differ: \(editor.nameRanges.prefix(8)) vs \(full.nameRanges.prefix(8))")
        }
    }

    private func compareGradient(_ host: HostedEditor, step: Int, operation: String) {
        let full = HostedEditor(text: host.editor.string, settings: host.settings)
        full.editor.setSelectedRange(host.editor.selectedRange())
        let origin = host.scroll.contentView.bounds.origin
        for view in [host.editor, full.editor] {
            view.layoutManager!.ensureLayout(for: view.textContainer!)
            view.sizeToFit()
        }
        full.scroll.contentView.scroll(to: origin)
        full.scroll.reflectScrolledClipView(full.scroll.contentView)
        full.editor.updateFocus()
        precondition(full.scroll.contentView.bounds.origin == origin, "Both views look at the same part of the page")
        let keys: Set<NSAttributedString.Key> = [.foregroundColor]
        if let difference = StyleSnapshot.difference(StyleSnapshot.temporary(of: host.editor, keys: keys), StyleSnapshot.temporary(of: full.editor, keys: keys), text: host.editor.string) {
            fail(host, step: step, operation: operation, "gradient focus differs, \(difference)")
        }
    }

    private func fail(_ host: HostedEditor, step: Int, operation: String, _ message: String) -> Never {
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("quill-fuzz-failure.md")
        try? host.editor.string.write(to: file, atomically: true, encoding: .utf8)
        print("""
        FAILED [\(name)] seed \(seed), edit \(step) of \(edits), after: \(operation)
        caret \(host.editor.selectedRange()), \((host.editor.string as NSString).length) characters
        \(message)
        The document at that moment is in \(file.path)
        Reproduce with \(reproduce)
        """)
        exit(1)
    }
}
