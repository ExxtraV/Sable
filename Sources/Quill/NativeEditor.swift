import AppKit
import SwiftUI
import QuillCore

struct NativeEditor: NSViewRepresentable {
    @Binding var text: String
    var review: Bool
    var words: String
    var fontSize: Double
    var pageWidth: Double
    var commands: EditorCommands
    var fontFamily: String = "Charter"
    var lineSpacing: Double = 0.28
    var focusParagraph: Bool = false
    var readOnly: Bool = false
    var darker: Bool = false
    var syntaxClasses: Int = 0
    var colorVersion: Int = 0
    var spellCheckEnabled: Bool = true
    var documentUndoManager: UndoManager? = nil
    var saveAction: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 760, height: 600))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.findBarPosition = .aboveContent
        let editor = WritingTextView(frame: scroll.contentView.bounds)
        editor.isRichText = false
        editor.allowsUndo = true
        editor.isEditable = !readOnly
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
        commands.editor = editor
        editor.isIncrementalSearchingEnabled = true
        editor.usesFindBar = true
        editor.delegate = context.coordinator
        editor.string = text
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? WritingTextView else { return }
        if editor.string != text {
            let selection = editor.selectedRange()
            editor.string = text
            let length = (text as NSString).length
            editor.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        }
        commands.editor = editor
        editor.isEditable = !readOnly
        editor.isContinuousSpellCheckingEnabled = spellCheckEnabled
        editor.isGrammarCheckingEnabled = spellCheckEnabled
        editor.saveAction = saveAction
        editor.syntaxClasses = syntaxClasses
        editor.colorVersion = colorVersion
        editor.bodyFontFamily = fontFamily
        editor.lineSpacingRatio = lineSpacing
        editor.focusParagraph = focusParagraph && !readOnly
        editor.bodySize = fontSize
        editor.pageWidth = pageWidth
        editor.updatePageMargins()
        editor.appearance = darker ? NSAppearance(named: .darkAqua) : nil
        editor.backgroundColor = darker ? NSColor(white: 0.075, alpha: 1) : .textBackgroundColor
        editor.reviewEnabled = review
        editor.reviewWords = words
        editor.decorate()
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeEditor
        init(_ parent: NativeEditor) { self.parent = parent }
        func undoManager(for view: NSTextView) -> UndoManager? { parent.documentUndoManager ?? view.window?.undoManager }
        func textViewDidChangeSelection(_ notification: Notification) {
            (notification.object as? WritingTextView)?.updateFocus()
        }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? WritingTextView else { return }
            parent.text = editor.string
            editor.decorate()
        }
    }
}

final class WritingTextView: NSTextView {
    var reviewEnabled = true
    var reviewWords = Prose.defaultWords
    var syntaxClasses = 0
    var colorVersion = 0
    var saveAction: (() -> Void)?
    var bodyFontFamily = "Charter"
    var lineSpacingRatio = 0.28
    var focusParagraph = false
    var bodySize: Double = 19
    var pageWidth: Double = 680
    private var contextRange: NSRange?
    private var styling = false
    private var lastStyledText: String?
    private var lastStyledSize: Double = 0
    private var lastStyledFamily = ""
    private var lastStyledSpacing: Double = -1
    private var lastSyntaxClasses = -1
    private var lastColorVersion = -1
    private var didSetInitialFocus = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.titlebarAppearsTransparent = true
        window?.titlebarSeparatorStyle = .none
        window?.backgroundColor = .windowBackgroundColor
        guard isEditable, window != nil, !didSetInitialFocus else { return }
        didSetInitialFocus = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isEditable else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updatePageMargins()
    }

    func updatePageMargins() {
        let margin = max(28, (bounds.width - pageWidth) / 2)
        let inset = NSSize(width: margin, height: 48)
        if textContainerInset != inset { textContainerInset = inset }
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if (event.keyCode == 48 || event.keyCode == 53), modifiers.isEmpty, leaveFormatting() { return }
        super.keyDown(with: event)
    }

    override func insertNewline(_ sender: Any?) {
        _ = leaveFormatting()
        super.insertNewline(sender)
    }

    @discardableResult
    private func leaveFormatting() -> Bool {
        guard let offset = MarkdownSyntax.exitOffset(in: string, selection: selectedRange()) else { return false }
        setSelectedRange(NSRange(location: offset, length: 0))
        return true
    }

    @objc func exitFormatting(_ sender: Any?) { _ = leaveFormatting() }

    private func styleMarkdown() {
        guard !styling, !hasMarkedText(), let storage = textStorage else { return }
        guard lastStyledText != string || lastStyledSize != bodySize || lastStyledFamily != bodyFontFamily || lastStyledSpacing != lineSpacingRatio || lastSyntaxClasses != syntaxClasses || lastColorVersion != colorVersion else { return }
        styling = true
        defer { styling = false }
        let full = NSRange(location: 0, length: storage.length)
        let base = NSFontManager.shared.font(withFamily: bodyFontFamily, traits: [], weight: 5, size: bodySize) ?? .systemFont(ofSize: bodySize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = bodySize * lineSpacingRatio
        paragraph.paragraphSpacing = bodySize * 0.25
        let attributes: [NSAttributedString.Key: Any] = [.font: base, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        storage.beginEditing()
        storage.setAttributes(attributes, range: full)
        let spans = MarkdownSyntax.spans(in: string)
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
                    let address = (string as NSString).substring(with: destination)
                    if let url = URL(string: address), ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                        storage.addAttributes([.link: url, .toolTip: address], range: span.content)
                    }
                }
            case .quote:
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: span.range)
            case .strike:
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: span.content)
            default: break
            }
        }
        for span in spans {
            for marker in span.markers {
                storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: marker)
            }
        }
        for word in SentenceStructure.words(in: string, enabled: syntaxClasses) {
            storage.addAttribute(.foregroundColor, value: Self.wordColor(word.kind), range: word.range)
        }
        storage.endEditing()
        typingAttributes = attributes
        lastStyledText = string
        lastStyledSize = bodySize
        lastStyledFamily = bodyFontFamily
        lastStyledSpacing = lineSpacingRatio
        lastSyntaxClasses = syntaxClasses
        lastColorVersion = colorVersion
    }

    static func wordColor(_ kind: WordClass) -> NSColor {
        if let hex = UserDefaults.standard.string(forKey: "wordColor.\(kind.rawValue)"), let custom = NSColor(quillHex: hex) {
            return custom
        }
        return defaultWordColor(kind)
    }
    private static func defaultWordColor(_ kind: WordClass) -> NSColor {
        // Soft, low-saturation defaults so highlighted parts of speech read as gentle tints, not neon.
        switch kind {
        case .noun: pastel(light: NSColor(red: 0.20, green: 0.47, blue: 0.49, alpha: 1), dark: NSColor(red: 0.62, green: 0.85, blue: 0.86, alpha: 1))
        case .verb: pastel(light: NSColor(red: 0.62, green: 0.42, blue: 0.14, alpha: 1), dark: NSColor(red: 0.93, green: 0.78, blue: 0.55, alpha: 1))
        case .adjective: pastel(light: NSColor(red: 0.24, green: 0.38, blue: 0.62, alpha: 1), dark: NSColor(red: 0.68, green: 0.78, blue: 0.95, alpha: 1))
        case .adverb: pastel(light: NSColor(red: 0.62, green: 0.30, blue: 0.46, alpha: 1), dark: NSColor(red: 0.93, green: 0.70, blue: 0.83, alpha: 1))
        case .pronoun: pastel(light: NSColor(red: 0.30, green: 0.50, blue: 0.32, alpha: 1), dark: NSColor(red: 0.72, green: 0.88, blue: 0.73, alpha: 1))
        }
    }
    private static func pastel(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
    @objc func saveDocument(_ sender: Any?) {
        if let saveAction { saveAction() }
        else { _ = nextResponder?.tryToPerform(#selector(saveDocument(_:)), with: sender) }
    }

    func updateFocus() {
        guard !styling, let layoutManager else { return }
        let length = (string as NSString).length
        let whole = NSRange(location: 0, length: length)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)
        guard focusParagraph else { return }
        let active = FocusParagraph.range(in: string, caret: selectedRange().location)
        // withAlphaComponent bakes labelColor into a concrete RGBA using whatever appearance
        // happens to be current, rather than staying dynamic — resolve it under this view's
        // own appearance so the fade is correct in both light and dark windows.
        var faded = NSColor.labelColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            faded = NSColor.labelColor.withAlphaComponent(0.25)
        }
        if active.location > 0 {
            layoutManager.addTemporaryAttribute(.foregroundColor, value: faded, forCharacterRange: NSRange(location: 0, length: active.location))
        }
        if NSMaxRange(active) < length {
            layoutManager.addTemporaryAttribute(.foregroundColor, value: faded, forCharacterRange: NSRange(location: NSMaxRange(active), length: length - NSMaxRange(active)))
        }
    }

    func decorate() {
        styleMarkdown()
        updateFocus()
        guard let layoutManager else { return }
        let whole = NSRange(location: 0, length: (string as NSString).length)
        layoutManager.removeTemporaryAttribute(.strikethroughStyle, forCharacterRange: whole)
        layoutManager.removeTemporaryAttribute(.strikethroughColor, forCharacterRange: whole)
        guard reviewEnabled else { return }
        for range in Prose.suggestions(in: string, words: reviewWords) {
            layoutManager.addTemporaryAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: NSColor.secondaryLabelColor
            ], forCharacterRange: range)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        contextRange = reviewEnabled ? Prose.suggestions(in: string, words: reviewWords).first { NSLocationInRange(index, $0) } : nil
        if contextRange != nil {
            menu.addItem(.separator())
            let remove = NSMenuItem(title: "Remove suggested word", action: #selector(removeSuggestion(_:)), keyEquivalent: "")
            remove.target = self
            menu.addItem(remove)
            let ignore = NSMenuItem(title: "Stop suggesting this word", action: #selector(ignoreSuggestion(_:)), keyEquivalent: "")
            ignore.target = self
            menu.addItem(ignore)
        }
        return menu
    }
    @objc private func removeSuggestion(_ sender: Any?) {
        guard let range = contextRange, NSMaxRange(range) <= (string as NSString).length else { return }
        replace(range, with: "", selection: NSRange(location: range.location, length: 0))
    }
    @objc private func ignoreSuggestion(_ sender: Any?) {
        guard let range = contextRange, NSMaxRange(range) <= (string as NSString).length else { return }
        let word = (string as NSString).substring(with: range)
        reviewWords = reviewWords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.caseInsensitiveCompare(word) != .orderedSame }.joined(separator: ", ")
        UserDefaults.standard.set(reviewWords, forKey: "reviewWords")
        decorate()
    }
    private func replace(_ range: NSRange, with replacement: String, selection: NSRange) {
        guard isEditable, shouldChangeText(in: range, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        setSelectedRange(selection)
    }
    private func wrap(_ marker: String) {
        let range = selectedRange()
        let source = string as NSString
        if range.length == 0, range.location < source.length,
           source.substring(from: range.location).hasPrefix(marker), leaveFormatting() { return }
        let selected = source.substring(with: range)
        let size = (marker as NSString).length
        if selected.hasPrefix(marker), selected.hasSuffix(marker), range.length >= size * 2 {
            let inner = (selected as NSString).substring(with: NSRange(location: size, length: range.length - size * 2))
            replace(range, with: inner, selection: NSRange(location: range.location, length: (inner as NSString).length))
        } else if range.location >= size, NSMaxRange(range) + size <= source.length,
                  source.substring(with: NSRange(location: range.location - size, length: size)) == marker,
                  source.substring(with: NSRange(location: NSMaxRange(range), length: size)) == marker {
            replace(NSRange(location: range.location - size, length: range.length + size * 2), with: selected,
                    selection: NSRange(location: range.location - size, length: range.length))
        } else {
            replace(range, with: marker + selected + marker,
                    selection: NSRange(location: range.location + size, length: range.length))
        }
    }
    @objc func markBold(_ sender: Any?) { wrap("**") }
    @objc func markItalic(_ sender: Any?) { wrap("*") }
    @objc func markLink(_ sender: Any?) {
        let range = selectedRange()
        let selected = (string as NSString).substring(with: range)
        replace(range, with: "[" + selected + "](url)", selection: NSRange(location: range.location + range.length + 3, length: 3))
    }
    @objc func markHeading(_ sender: Any?) {
        let range = (string as NSString).lineRange(for: selectedRange())
        replace(NSRange(location: range.location, length: 0), with: "## ", selection: NSRange(location: range.location + 3, length: 0))
    }
}

extension NSColor {
    convenience init?(quillHex hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmed.count == 6 else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: trimmed).scanHexInt64(&value) else { return nil }
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
    var quillHex: String {
        let converted = usingColorSpace(.deviceRGB) ?? self
        return String(format: "#%02X%02X%02X", Int(converted.redComponent * 255), Int(converted.greenComponent * 255), Int(converted.blueComponent * 255))
    }
}

@MainActor
final class EditorCommands: ObservableObject {
    weak var editor: WritingTextView?
    func jump(to range: NSRange) {
        guard let editor, NSMaxRange(range) <= (editor.string as NSString).length else { return }
        editor.window?.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: range.location, length: 0))
        editor.scrollRangeToVisible(range)
        editor.showFindIndicator(for: range)
    }
    func openInTab(_ url: URL, completion: @escaping (Error?) -> Void) {
        let sourceWindow = editor?.window
        let scoped = url.startAccessingSecurityScopedResource()
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, error in
            if scoped { url.stopAccessingSecurityScopedResource() }
            if let target = document?.windowControllers.first?.window {
                if let sourceWindow, target !== sourceWindow, !(sourceWindow.tabbedWindows ?? []).contains(target) {
                    sourceWindow.addTabbedWindow(target, ordered: .above)
                }
                target.makeKeyAndOrderFront(nil)
                @MainActor func writingEditor(in view: NSView) -> WritingTextView? {
                    if let editor = view as? WritingTextView, editor.isEditable { return editor }
                    for child in view.subviews { if let editor = writingEditor(in: child) { return editor } }
                    return nil
                }
                if let content = target.contentView, let editor = writingEditor(in: content) {
                    target.makeFirstResponder(editor)
                }
            }
            completion(error)
        }
    }
    func format(_ action: Selector) {
        guard let editor else { return }
        editor.window?.makeFirstResponder(editor)
        NSApp.sendAction(action, to: editor, from: nil)
    }
}
