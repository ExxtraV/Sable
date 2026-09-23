import AppKit
import SwiftUI
import QuillCore

// A made-up novel for the typing benchmark and the incremental-styling check. It is generated from a seed, so every
// run sees exactly the same text, and it holds every construct the editor styles: front matter, chapters, dialogue,
// emphasis, lists, quotes, notes, fenced code, tables, footnotes, links, images, emoji, and the cast's names.
// Compile it alongside the check or benchmark that uses it; it has no `main` of its own.

/// SplitMix64: small, fast, and the same sequence on every machine for the same seed.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    /// A value in `range`, by modulo; the bias is irrelevant here and the result never depends on the stdlib's algorithm.
    mutating func int(_ range: Range<Int>) -> Int { range.lowerBound + Int(next() % UInt64(range.count)) }
    mutating func int(_ range: ClosedRange<Int>) -> Int { int(range.lowerBound..<(range.upperBound + 1)) }
    mutating func chance(_ probability: Double) -> Bool { Double(next() >> 11) / Double(1 << 53) < probability }
    mutating func pick<T>(_ items: [T]) -> T { items[int(0..<items.count)] }
}

enum ManuscriptFixture {
    static let characters = ["Marren Vale", "Idris Okonkwo", "Tamsin Rook", "Benedikt Aske", "Yevgenia Thorne"]
    static let places = ["The Pier", "Saltmarsh Row", "Harrowgate Light", "the Undercroft"]
    static let lore = ["Tidewright Compact", "Drowned Bell"]

    /// Cards for the cast, the same shape the project's card index builds.
    static var cards: [IndexedCard] {
        func card(_ name: String, _ kind: CardKind, aliases: [String] = []) -> IndexedCard {
            IndexedCard(url: URL(fileURLWithPath: "/fixture/\(kind.rawValue)/\(name).md"), kind: kind, stem: name, title: name,
                        subtitle: "", aliases: aliases, modified: nil)
        }
        return characters.map { card($0, .character, aliases: $0 == "Idris Okonkwo" ? ["the Ferryman"] : []) }
            + places.map { card($0, .location) } + lore.map { card($0, .lore) }
    }

    static var highlighter: NameHighlighter { NameHighlighter.build(from: cards) }

    // MARK: Vocabulary

    private static let pronouns = ["she", "he", "they", "we", "I"]
    private static let firstNames = ["Marren", "Idris", "Tamsin", "Benedikt", "Yevgenia", "Vale", "Rook"]
    private static let verbs = ["watched", "carried", "remembered", "counted", "followed", "folded", "weighed", "answered",
                                "measured", "lifted", "crossed", "circled", "doubted", "mended", "buried", "traced", "kept"]
    private static let adjectives = ["grey", "salt-stiff", "narrow", "patient", "cold", "crooked", "quiet", "tarnished", "low",
                                     "brittle", "familiar", "heavy", "pale", "unlit", "second", "last"]
    private static let nouns = ["lantern", "tide", "rope", "ledger", "window", "harbour", "door", "letter", "bell", "boat",
                                "coat", "stair", "net", "shore", "map", "key", "fog", "candle", "gull", "wall", "promise"]
    private static let adverbs = ["slowly", "again", "carefully", "at last", "without a word", "twice", "before dawn",
                                  "for a long time", "almost", "very", "just", "really", "quite"]
    private static let dialogueLines = ["You said the tide would turn", "Nobody rings it anymore", "Leave the lantern where it is",
                                        "I counted them twice", "Tell me what the letter says", "It was never about the boat",
                                        "We should have gone north", "Do you still keep the key", "That isn't how I remember it",
                                        "The fog will lift by morning"]
    private static let tags = ["said", "asked", "whispered", "muttered", "called", "admitted"]
    private static let emoji = ["🌙", "⚓️", "🕯️", "🌊"]

    // MARK: Pieces

    private static func name(_ rng: inout SeededRandom) -> String {
        rng.chance(0.25) ? rng.pick(places) : (rng.chance(0.1) ? rng.pick(lore) : rng.pick(characters + firstNames))
    }

    private static func sentence(_ rng: inout SeededRandom) -> String {
        let subject = rng.chance(0.4) ? name(&rng) : rng.pick(pronouns)
        var words = "\(subject) \(rng.pick(verbs)) the \(rng.pick(adjectives)) \(rng.pick(nouns))"
        if rng.chance(0.5) { words += " \(rng.pick(adverbs))" }
        if rng.chance(0.35) { words += ", and the \(rng.pick(nouns)) \(rng.pick(verbs)) \(rng.chance(0.3) ? name(&rng) : "the \(rng.pick(nouns))")" }
        if rng.chance(0.2) { words += " near \(rng.pick(places))" }
        return words.prefix(1).uppercased() + words.dropFirst() + (rng.chance(0.08) ? "?" : ".")
    }

    /// Wraps one word of `text` in an inline construct, now and then.
    private static func decorate(_ text: String, _ rng: inout SeededRandom, footnote: inout Int) -> String {
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard words.count > 4 else { return text }
        func wrap(_ open: String, _ close: String) {
            let at = rng.int(1..<(words.count - 1))
            guard words[at].allSatisfy({ $0.isLetter }) else { return }
            words[at] = open + words[at] + close
        }
        if rng.chance(0.12) { wrap("*", "*") }
        if rng.chance(0.05) { wrap("**", "**") }
        if rng.chance(0.03) { wrap("_", "_") }
        if rng.chance(0.01) { wrap("***", "***") }
        if rng.chance(0.012) { wrap("~~", "~~") }
        if rng.chance(0.01) { wrap("`", "`") }
        if rng.chance(0.015) { wrap("[", "](https://example.com/\(rng.pick(nouns)))") }
        if rng.chance(0.02) { words[rng.int(1..<words.count)] += " \(rng.pick(emoji))" }
        if rng.chance(0.01) { footnote += 1; words[words.count - 1] += "[^\(footnote)]" }
        return words.joined(separator: " ")
    }

    static func narration(_ rng: inout SeededRandom, footnote: inout Int) -> String {
        var sentences: [String] = []
        let target = rng.int(40...180)
        var count = 0
        while count < target {
            let next = sentence(&rng)
            count += next.split(separator: " ").count
            sentences.append(next)
        }
        return decorate(sentences.joined(separator: " "), &rng, footnote: &footnote)
    }

    static func dialogue(_ rng: inout SeededRandom, footnote: inout Int) -> String {
        let curly = rng.chance(0.4)
        let (open, close) = curly ? ("\u{201C}", "\u{201D}") : ("\"", "\"")
        let speaker = rng.pick(characters + firstNames)
        var text = "\(open)\(rng.pick(dialogueLines)),\(close) \(speaker) \(rng.pick(tags))."
        if rng.chance(0.6) { text += " \(open)\(rng.pick(dialogueLines)).\(close)" }
        if rng.chance(0.5) { text += " " + sentence(&rng) }
        return decorate(text, &rng, footnote: &footnote)
    }

    /// Everything that isn't a plain paragraph, keyed by name so the specimen can include each once.
    static let blockKinds = ["quote", "bullets", "numbers", "tasks", "comment", "longComment", "sceneBreak", "scene",
                             "table", "image", "backtickFence", "tildeFence", "setext", "rule"]

    static func block(_ kind: String, _ rng: inout SeededRandom) -> String {
        switch kind {
        case "quote":
            return (0..<rng.int(1...3)).map { _ in "> " + sentence(&rng) }.joined(separator: "\n")
        case "bullets":
            return (0..<rng.int(2...4)).map { _ in "- the \(rng.pick(adjectives)) \(rng.pick(nouns))" }.joined(separator: "\n")
        case "numbers":
            return (1...rng.int(2...4)).map { "\($0). \(rng.pick(verbs)) the \(rng.pick(nouns))" }.joined(separator: "\n")
        case "tasks":
            return (0..<rng.int(2...3)).map { _ in "- [\(rng.chance(0.5) ? "x" : " ")] check the \(rng.pick(nouns))" }.joined(separator: "\n")
        case "comment":
            return "<!-- TODO: \(rng.pick(verbs)) this \(rng.pick(nouns)) later -->"
        case "longComment":
            return "<!--\nNote to self: \(sentence(&rng))\n\(sentence(&rng))\n-->"
        case "sceneBreak":
            return rng.pick(["* * *", "***", "---", "- - -"])
        case "scene":
            return "## \(rng.pick(adjectives).capitalized) \(rng.pick(nouns).capitalized)"
        case "table":
            return "| Tide | Hour | Bell |\n| --- | --- | --- |\n| high | \(rng.int(1...12)):00 | rung |\n| low | \(rng.int(1...12)):30 | silent |"
        case "image":
            return "![A map of \(rng.pick(places))](images/\(rng.pick(nouns)).png)"
        case "backtickFence":
            return "```text\nTIDE TABLE — \(rng.pick(places))\n  *not emphasis*  <!-- not a note -->\n# not a heading\n```"
        case "tildeFence":
            return "~~~\nLEDGER \(rng.int(100...999))\n**still not bold**\n~~~"
        case "setext":
            return "\(sentence(&rng))\n\(rng.chance(0.5) ? "===" : "---")"
        default: // "rule"
            return "___"
        }
    }

    private static func chapterTitle(_ rng: inout SeededRandom) -> String {
        "The \(rng.pick(adjectives).capitalized) \(rng.pick(nouns).capitalized)"
    }

    /// A novel of at least `words` words (as `Prose.wordCount` counts them).
    static func novel(words target: Int, seed: UInt64 = 0x5AB1E) -> String {
        var rng = SeededRandom(seed: seed)
        var parts: [String] = ["---\ntitle: The Drowned Bell\ndraft: \(rng.int(2...9))\ntags: [fixture, benchmark]\n---"]
        var count = 0
        var footnote = 0
        var definedFootnotes = 0
        var chapter = 0
        var chapterWords = Int.max
        func add(_ part: String) {
            parts.append(part)
            count += Prose.wordCount(part)
            chapterWords += Prose.wordCount(part)
        }
        func closeChapter() {
            while definedFootnotes < footnote {
                definedFootnotes += 1
                parts.append("[^\(definedFootnotes)]: \(sentence(&rng))")
            }
        }
        while count < target {
            if chapterWords > 3_500 {
                closeChapter()
                chapter += 1
                chapterWords = 0
                add("# Chapter \(chapter): \(chapterTitle(&rng))")
                if chapter == 1 {
                    // One of everything, so even a small fixture covers every construct.
                    add(narration(&rng, footnote: &footnote))
                    add("A line with *italic*, _also italic_, **bold**, __also bold__, ***both***, ~~struck~~, `code`, [a link](https://example.com), and a note[^\(footnote + 1)].")
                    footnote += 1
                    add(dialogue(&rng, footnote: &footnote))
                    for kind in blockKinds { add(block(kind, &rng)); add(sentence(&rng)) }
                    add("Marren Vale walked to the Pier with the Ferryman 🌙, and Tamsin said nothing about the Drowned Bell.")
                }
                continue
            }
            let roll = rng.int(0..<1000)
            switch roll {
            case 0..<620: add(narration(&rng, footnote: &footnote))
            case 620..<940: add(dialogue(&rng, footnote: &footnote))
            case 940..<960: add(block("sceneBreak", &rng))
            case 960..<972: add(block("quote", &rng))
            case 972..<980: add(block("comment", &rng))
            case 980..<985: add(block("scene", &rng))
            case 985..<989: add(block("bullets", &rng))
            case 989..<992: add(block("numbers", &rng))
            case 992..<994: add(block("tasks", &rng))
            case 994..<996: add(block("longComment", &rng))
            case 996: add(block("table", &rng))
            case 997: add(block("image", &rng))
            case 998: add(block(rng.pick(["backtickFence", "tildeFence"]), &rng))
            default: add(block("setext", &rng))
            }
        }
        closeChapter()
        return parts.joined(separator: "\n\n") + "\n"
    }

    /// A few paragraphs or blocks, for pasting in the random-edit check.
    static func chunk(_ rng: inout SeededRandom) -> String {
        var footnote = 0
        return (0..<rng.int(1...3)).map { _ in
            rng.chance(0.3) ? block(rng.pick(blockKinds), &rng) : (rng.chance(0.4) ? dialogue(&rng, footnote: &footnote) : narration(&rng, footnote: &footnote))
        }.joined(separator: "\n\n")
    }
}

// MARK: - Hosting the editor the way the app does

/// The settings `NativeEditor` passes down from Writing Style. The defaults match a new install writing in a project.
struct EditorSettings {
    var review = true
    var words = Prose.defaultWords
    var fontSize = 19.0
    var pageWidth = 680.0
    var fontFamily = "Charter"
    var lineSpacing = 0.28
    var focusParagraph = false
    var focusGradient = true
    var syntaxClasses = 0
    var colorVersion = 0
    var theme = "graphite"
    var typewriterMode = "room"
    var names = true
    var nameKinds = Set(CardKind.allCases)
    var nameShimmer = true
    var dimMarkers = true
    var smartTypography = false
    var spellCheck = true

    static let defaults = EditorSettings()
    /// Every per-keystroke feature switched on.
    static var everything: EditorSettings {
        var settings = EditorSettings()
        settings.focusParagraph = true
        settings.syntaxClasses = WordClass.allCases.reduce(0) { $0 | $1.rawValue }
        settings.smartTypography = true
        settings.typewriterMode = "center"
        return settings
    }
}

/// A `WritingTextView` in an offscreen window, in the same scroll view, clip view, and configuration `makeNSView` builds,
/// with the real `NativeEditor.Coordinator` as its delegate. `text` stands in for the SwiftUI document binding.
@MainActor
final class HostedEditor {
    let window: NSWindow
    let scroll: WritingScrollView
    let editor: WritingTextView
    let coordinator: NativeEditor.Coordinator
    let undo = UndoManager()
    let commands = EditorCommands()
    let highlighter = ManuscriptFixture.highlighter
    private(set) var settings: EditorSettings
    /// What SwiftUI's `document.text` holds. The editor hands typing to it in batches; `commitText()` hands it over now.
    var text: String
    /// The document whose saves wait for pending typing, as the window's document does in the app (optional here).
    var document: NSDocument?

    init(text: String, settings: EditorSettings, size: NSSize = NSSize(width: 1100, height: 800)) {
        _ = NSApplication.shared
        self.text = text
        self.settings = settings
        undo.groupsByEvent = false
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        scroll = WritingScrollView(frame: NSRect(origin: .zero, size: size))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        editor = WritingTextView(frame: scroll.contentView.bounds)
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isContinuousSpellCheckingEnabled = true
        editor.isGrammarCheckingEnabled = true
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 700, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 40, height: 40)
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        coordinator = NativeEditor.Coordinator(NativeEditor(text: .constant(""), review: true, words: "", fontSize: 19, pageWidth: 680, commands: commands))
        editor.delegate = coordinator
        editor.string = text
        coordinator.attach(editor, text: text)
        scroll.contentView = RoomClipView()
        scroll.documentView = editor
        window.contentView = scroll
        window.makeFirstResponder(editor)
        apply(settings)
    }

    /// What `updateNSView` does when SwiftUI hands the editor new settings.
    func apply(_ settings: EditorSettings) {
        self.settings = settings
        let binding = Binding<String>(get: { [unowned self] in self.text }, set: { [unowned self] in self.text = $0 })
        coordinator.parent = NativeEditor(text: binding, review: settings.review, words: settings.words, fontSize: settings.fontSize,
                                          pageWidth: settings.pageWidth, commands: commands, fontFamily: settings.fontFamily,
                                          lineSpacing: settings.lineSpacing, focusParagraph: settings.focusParagraph,
                                          focusGradient: settings.focusGradient, syntaxClasses: settings.syntaxClasses,
                                          colorVersion: settings.colorVersion, spellCheckEnabled: settings.spellCheck,
                                          typewriterMode: settings.typewriterMode, nameHighlighter: settings.names ? highlighter : nil,
                                          nameShimmer: settings.nameShimmer, nameKinds: settings.nameKinds, nameCards: ManuscriptFixture.cards,
                                          dimMarkers: settings.dimMarkers, smartTypography: settings.smartTypography,
                                          documentUndoManager: undo, editingDocument: document)
        coordinator.syncFromBinding(editor)
        HostedEditor.configure(editor, settings, highlighter: highlighter)
        editor.updatePageMargins()
        editor.updateScrollRoom()
        let paper = WritingTheme.named(editor.themeName).background
        editor.backgroundColor = paper
        editor.drawsBackground = true
        scroll.drawsBackground = true
        scroll.contentView.drawsBackground = true
        scroll.contentView.backgroundColor = paper
        editor.insertionPointColor = WritingTheme.named(editor.themeName).foreground
        editor.decorate()
        coordinator.publishStatsIfSettled()
    }

    /// Hands pending typing to the binding now, as a pause in typing, a save, or a click would.
    func commitText() { coordinator.flush() }

    /// The editor's own settings, the part of `updateNSView` a bare, unhosted view needs too.
    static func configure(_ editor: WritingTextView, _ settings: EditorSettings, highlighter: NameHighlighter) {
        editor.isContinuousSpellCheckingEnabled = settings.spellCheck
        editor.isGrammarCheckingEnabled = settings.spellCheck
        editor.syntaxClasses = settings.syntaxClasses
        editor.colorVersion = settings.colorVersion
        editor.bodyFontFamily = settings.fontFamily
        editor.lineSpacingRatio = settings.lineSpacing
        editor.focusParagraph = settings.focusParagraph
        editor.focusGradient = settings.focusGradient
        editor.bodySize = settings.fontSize
        editor.themeName = settings.theme
        editor.pageWidth = settings.pageWidth
        editor.typewriterMode = settings.typewriterMode
        editor.nameHighlighter = settings.names ? highlighter : nil
        editor.nameShimmer = settings.nameShimmer
        editor.nameKinds = settings.nameKinds
        editor.nameCards = ManuscriptFixture.cards
        editor.dimMarkers = settings.dimMarkers
        editor.smartTypography = settings.smartTypography
        editor.reviewEnabled = settings.review
        editor.reviewWords = settings.words
    }

    /// One user action as one undo group. The app's undo manager groups by run-loop event; this one is driven directly.
    func edit(_ change: () -> Void) {
        undo.beginUndoGrouping()
        change()
        undo.endUndoGrouping()
    }

    /// Lets queued main-thread work run, as it would between keystrokes.
    func flush() {
        // The main queue runs in order, so once this block has run, everything queued before it has too.
        final class Flag { var raised = false }
        let drained = Flag()
        DispatchQueue.main.async { drained.raised = true }
        while !drained.raised { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01)) }
    }
}
