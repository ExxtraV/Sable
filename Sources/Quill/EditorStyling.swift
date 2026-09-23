import AppKit
import QuillCore

/// Everything the editor remembers between styling passes so that a keystroke restyles only the lines around it.
/// A full restyle (new text, a theme, font, or size change) and a keystroke's restyle run the same code, one over the
/// whole text and one over a region, so they can't drift apart. A setting change on text that hasn't changed paints the
/// whole text from the spans, sentence tags, and names kept here instead of parsing and tagging it again.
/// `scripts/check-incremental-styling.swift` holds all of them to the same result after thousands of random edits.
@MainActor
final class EditorStyleState {
    /// The storage settings the text was last styled with; any change restyles everything.
    struct Key: Equatable {
        var size: Double, family: String, spacing: Double, syntaxClasses: Int, colorVersion: Int, theme: String
        var names: String, dimMarkers: Bool
    }
    var key: Key?
    /// The prose-review words last applied, or nil when review was off.
    var reviewKey: String??
    /// The text as last styled, and where it has changed since.
    var previous: NSString?
    var edits = EditTracker()
    var frontMatterEnd = 0
    /// Fenced code and notes (Markdown styling) and fences and front matter (prose review), kept in step with the text.
    var blocks: [MarkdownSpan] = []
    var proseBlocks: [NSRange] = []
    var nameRanges: [NSRange] = []
    var nameKinds: [CardKind] = []
    /// Every span except the blocks, over the whole text. None crosses a line, so a region pass splices its lines in.
    var lineSpans: [MarkdownSpan] = []
    /// Sentence tags over the whole text for every word class, so choosing other classes needs no tagging. Nil while
    /// sentence colors are off (it isn't kept up to date then).
    var tags: [TaggedWord]?
    var suggestions: [NSRange] = []
    /// Words in the whole text, kept up to date region by region; nil after a full pass until someone asks.
    var wordCount: Int?
    /// How many styling passes of each kind have run (not counting ones that only redo prose review), for the checks and
    /// the benchmark.
    var fullPasses = 0
    var regionPasses = 0
    /// Full passes that painted from the kept spans and tags because only a setting changed.
    var repaints = 0
}

/// The open document's text for views that only read it (the writing desk, cards, scene tags). SwiftUI compares a view's
/// inputs on every update, and comparing two versions of a novel character by character takes tens of milliseconds, so
/// these compare by revision instead.
struct LiveText: Equatable {
    var text: String
    var revision: Int
    static func == (lhs: LiveText, rhs: LiveText) -> Bool { lhs.revision == rhs.revision }
}

/// What the status bar shows about the open document, measured by the editor so SwiftUI never has to count.
struct DocumentStats: Equatable {
    /// The text these numbers describe (shares storage with the binding's copy, so comparing it is cheap).
    var text: String
    var words: Int
    /// Prose suggestions, or nil while review is off.
    var cuts: Int?
    /// Goes up by one each time the published text changes (not part of equality).
    var revision = 0

    /// Comparing two novels character by character takes milliseconds, so the counts and lengths go first.
    static func == (lhs: DocumentStats, rhs: DocumentStats) -> Bool {
        lhs.words == rhs.words && lhs.cuts == rhs.cuts && lhs.text.utf16.count == rhs.text.utf16.count && lhs.text == rhs.text
    }
}

extension WritingTextView: @preconcurrency NSTextStorageDelegate {
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        style.edits.record(editedRange: editedRange, length: textStorage.length)
    }

    var nameRanges: [NSRange] { style.nameRanges }

    /// True when the attributes on screen match the text: nothing has been typed since the last pass.
    var isStyleCurrent: Bool { style.previous != nil && style.edits.isClean && textStorage?.delegate === self }

    private var styleKey: EditorStyleState.Key {
        EditorStyleState.Key(size: bodySize, family: bodyFontFamily, spacing: lineSpacingRatio, syntaxClasses: syntaxClasses,
                             colorVersion: colorVersion, theme: themeName, names: nameKey, dimMarkers: dimMarkers)
    }
    private var reviewKey: String? { reviewEnabled ? reviewWords : nil }

    /// Brings the text's styling up to date: nothing if nothing changed, the lines around the edits after typing, and
    /// everything after a setting change or when an edit could change the meaning of text farther away.
    func styleText() {
        guard !styling, !hasMarkedText(), let storage = textStorage else { return }
        if storage.delegate !== self {
            storage.delegate = self
            style.previous = nil
        }
        let key = styleKey, review = reviewKey
        let textChanged = style.previous == nil || !style.edits.isClean
        let restyle = style.key != key, rereview = style.reviewKey != .some(review)
        guard textChanged || restyle || rereview else { return }
        styling = true
        defer { styling = false }

        let text = storage.mutableString.copy() as! NSString
        let whole = NSRange(location: 0, length: text.length)
        var region = whole, oldRegion = NSRange(location: 0, length: style.previous?.length ?? 0)
        var full = true
        if textChanged, let previous = style.previous, !restyle, nameHighlighter?.staysOnOneLine ?? true, Prose.wordsStayOnOneLine(reviewWords),
           case let .region(range, old) = IncrementalStyling.plan(previous: .init(text: previous, frontMatterEnd: style.frontMatterEnd), text: text, edit: style.edits) {
            let start = style.edits.prefix, delta = text.length - previous.length
            let oldEnd = previous.length - style.edits.suffix
            style.blocks = IncrementalStyling.shift(style.blocks, editStart: start, oldEditEnd: oldEnd, delta: delta, oldLength: previous.length)
            style.proseBlocks = style.proseBlocks.map { IncrementalStyling.shift($0, editStart: start, oldEditEnd: oldEnd, delta: delta, oldLength: previous.length) }
            if let count = style.wordCount {
                style.wordCount = count - Prose.wordCount(previous.substring(with: old)) + Prose.wordCount(text.substring(with: range))
            }
            (region, oldRegion, full) = (range, old, false)
        } else if textChanged {
            style.blocks = MarkdownSyntax.blocks(in: text as String)
            style.proseBlocks = Prose.protectedBlocks(in: text as String)
            style.wordCount = nil
        }
        if textChanged || restyle {
            // Only a setting changed: the text is exactly as last styled, so what was found in it still holds.
            let repaint = !textChanged
            applyStyle(full || restyle ? whole : region, replacing: oldRegion, in: text, storage: storage,
                       repaint: repaint, keepNames: repaint && style.key?.names == key.names)
            if repaint { style.repaints += 1 }
            if full || restyle { style.fullPasses += 1 } else { style.regionPasses += 1 }
        }
        if textChanged || rereview {
            applyReview(full || rereview ? whole : region, replacing: oldRegion, in: text)
        }
        style.previous = text
        style.edits.reset()
        style.key = key
        style.reviewKey = .some(review)
        if textChanged {
            let source = text as String
            let names = NameHighlighter.frontMatterLength(in: text)
            style.frontMatterEnd = max(NSMaxRange(MarkdownLines.frontMatterRange(in: source)), Prose.frontMatterEnd(in: source), names)
        }
    }

    /// Styles `range` from scratch. `old` is where that range was in the previous text (the whole previous text for a
    /// full pass), so the remembered spans, tags, and name ranges outside it can be kept. `repaint` paints the whole,
    /// unchanged text from what was kept instead of parsing it again, and `keepNames` keeps its names too.
    private func applyStyle(_ range: NSRange, replacing old: NSRange, in text: NSString, storage: NSTextStorage,
                            repaint: Bool, keepNames: Bool) {
        let string = text as String
        let whole = range.location == 0 && range.length == text.length
        let lineSpans = repaint ? style.lineSpans : MarkdownSyntax.lineSpans(in: string, range: range, blocks: style.blocks)
        let spans = MarkdownSyntax.blockParts(in: range, blocks: style.blocks) + lineSpans
        var tags = repaint ? style.tags : nil
        if syntaxClasses != 0, tags == nil {
            tags = SentenceStructure.words(in: string, enabled: SentenceStructure.allClasses, range: range, spans: spans)
        }
        let base = NSFontManager.shared.font(withFamily: bodyFontFamily, traits: [], weight: 5, size: bodySize) ?? .systemFont(ofSize: bodySize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = bodySize * lineSpacingRatio
        paragraph.paragraphSpacing = bodySize * 0.25
        let attributes: [NSAttributedString.Key: Any] = [.font: base, .foregroundColor: WritingTheme.named(themeName).foreground, .paragraphStyle: paragraph]
        storage.beginEditing()
        storage.setAttributes(attributes, range: range)
        // Heading sizes precede inline traits so bold/italic can compose with headings.
        for span in spans {
            if case let .heading(level) = span.kind {
                let size = bodySize + Double(max(0, 4 - level)) * 3
                let font = NSFontManager.shared.font(withFamily: bodyFontFamily, traits: .boldFontMask, weight: 9, size: size) ?? .systemFont(ofSize: size, weight: .semibold)
                storage.addAttribute(.font, value: font, range: span.range)
            }
        }
        for span in spans {
            switch span.kind {
            case .bold, .italic, .boldItalic:
                var runs: [(NSRange, NSFont)] = []
                storage.enumerateAttribute(.font, in: span.content) { value, range, _ in
                    var traits: NSFontTraitMask = []
                    if case .bold = span.kind { traits = .boldFontMask }
                    if case .italic = span.kind { traits = .italicFontMask }
                    if case .boldItalic = span.kind { traits = [.boldFontMask, .italicFontMask] }
                    runs.append((range, NSFontManager.shared.convert(value as? NSFont ?? base, toHaveTrait: traits)))
                }
                for (range, font) in runs { storage.addAttribute(.font, value: font, range: range) }
            case .code:
                storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: bodySize * 0.87, weight: .regular), .backgroundColor: NSColor.quaternaryLabelColor], range: span.range)
            case .link:
                storage.addAttributes([.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue], range: span.content)
                if let destination = span.destination {
                    let address = text.substring(with: destination)
                    if let url = URL(string: address), ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                        storage.addAttributes([.link: url, .toolTip: address], range: span.content)
                    }
                }
            case .quote:
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: span.range)
            case .strike:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: span.content)
            case .rule:
                storage.addAttributes([.foregroundColor: NSColor.tertiaryLabelColor, .kern: bodySize * 0.3], range: span.range)
            case .comment:
                storage.addAttributes([.foregroundColor: NSColor.tertiaryLabelColor, .font: NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)], range: span.range)
            case .image:
                storage.addAttributes([.foregroundColor: NSColor.secondaryLabelColor, .font: NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)], range: span.range)
                if let destination = span.destination {
                    storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: destination)
                }
            case let .task(done):
                storage.addAttributes([.foregroundColor: NSColor.linkColor, .font: NSFont.monospacedSystemFont(ofSize: bodySize * 0.9, weight: .regular)], range: span.content)
                if done { storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: NSRange(location: NSMaxRange(span.content), length: NSMaxRange(span.range) - NSMaxRange(span.content))) }
            case .table:
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: bodySize * 0.86, weight: .regular), range: span.range)
            case .footnote:
                storage.addAttributes([.foregroundColor: NSColor.linkColor, .baselineOffset: bodySize * 0.28, .font: NSFont.systemFont(ofSize: bodySize * 0.72)], range: span.range)
            default: break
            }
        }
        if dimMarkers {
            for span in spans {
                for marker in span.markers {
                    storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: marker)
                }
            }
        }
        if syntaxClasses != 0, let tags {
            let colors = Dictionary(uniqueKeysWithValues: WordClass.allCases.map { ($0, Self.wordColor($0)) })
            for word in tags where syntaxClasses & word.kind.rawValue != 0 {
                storage.addAttribute(.foregroundColor, value: colors[word.kind]!, range: word.range)
            }
        }
        // Names of characters, places, and world notes stand out on top of everything else, by color and optionally a glow.
        var found: [(range: NSRange, kind: CardKind)] = []
        if keepNames {
            found = zip(style.nameRanges, style.nameKinds).map { ($0, $1) }
        } else if let namer = nameHighlighter, !namer.isEmpty {
            found = namer.matches(in: string, kinds: nameKinds, range: range)
        }
        let nameColors = Dictionary(uniqueKeysWithValues: CardKind.allCases.map { ($0, Self.nameColor($0)) })
        for match in found {
            storage.addAttribute(.foregroundColor, value: nameColors[match.kind]!, range: match.range)
        }
        storage.endEditing()
        // The shimmer paints names with temporary colors; any left on text that was just restyled may no longer be a name.
        // Paragraph focus repaints its own dimming right after this.
        layoutManager?.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
        let delta = range.length - old.length
        if !repaint {
            style.lineSpans = whole ? lineSpans : IncrementalStyling.splice(style.lineSpans, old: old, delta: delta, replacement: lineSpans,
                                                                            range: { $0.range }, moved: { $0.shifted(by: $1) })
        }
        if whole {
            style.tags = tags
        } else if let tags, let kept = style.tags {
            style.tags = IncrementalStyling.splice(kept, old: old, delta: delta, replacement: tags, range: { $0.range }, moved: { $0.shifted(by: $1) })
        } else {
            style.tags = nil
        }
        let kept = IncrementalStyling.splice(Array(zip(style.nameRanges, style.nameKinds)), old: old, delta: delta,
                                            replacement: found.map { ($0.range, $0.kind) }, range: { $0.0 },
                                            moved: { (NSRange(location: $0.0.location + $1, length: $0.0.length), $0.1) })
        style.nameRanges = kept.map(\.0)
        style.nameKinds = kept.map(\.1)
        typingAttributes = attributes
        updateShimmer()
    }

    /// Prose suggestions are drawn as temporary strikethroughs, so they never touch the text's own attributes.
    private func applyReview(_ range: NSRange, replacing old: NSRange, in text: NSString) {
        guard let layoutManager else { return }
        layoutManager.removeTemporaryAttribute(.strikethroughStyle, forCharacterRange: range)
        layoutManager.removeTemporaryAttribute(.strikethroughColor, forCharacterRange: range)
        guard reviewEnabled else {
            style.suggestions = []
            return
        }
        let found = Prose.suggestions(in: text as String, words: reviewWords, range: range, blocks: style.proseBlocks)
        for suggestion in found {
            layoutManager.addTemporaryAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: NSColor.secondaryLabelColor
            ], forCharacterRange: suggestion)
        }
        let whole = range.location == 0 && range.length == text.length
        style.suggestions = whole ? found : IncrementalStyling.splice(style.suggestions, old: old, delta: range.length - old.length, replacement: found,
                                                                        range: { $0 }, moved: { NSRange(location: $0.location + $1, length: $0.length) })
    }

    /// Prose suggestions as of the last pass, or a fresh search if the text has changed since.
    func currentSuggestions() -> [NSRange] {
        guard reviewEnabled else { return [] }
        if isStyleCurrent, style.reviewKey == .some(reviewKey) { return style.suggestions }
        return Prose.suggestions(in: string, words: reviewWords)
    }

    /// Fences and notes as of the last pass, or found afresh if the text has changed since.
    func currentBlocks() -> [MarkdownSpan] {
        isStyleCurrent ? style.blocks : MarkdownSyntax.blocks(in: string)
    }

    /// Word and suggestion counts for the status bar. Cheap after typing; a full count only after a full restyle.
    func documentStats(text: String) -> DocumentStats {
        let words: Int
        if isStyleCurrent, let count = style.wordCount {
            words = count
        } else {
            words = Prose.wordCount(text)
            if isStyleCurrent { style.wordCount = words }
        }
        return DocumentStats(text: text, words: words, cuts: reviewEnabled ? currentSuggestions().count : nil)
    }
}
