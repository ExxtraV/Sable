import AppKit
import SwiftUI
import QuillCore

/// A clip view that lets the text scroll past its ends, so the line you're writing can rest in the middle of the
/// window instead of being stuck near the top or bottom.
final class RoomClipView: NSClipView {
    var bottomRoom: CGFloat = 0 { didSet { if oldValue != bottomRoom { refresh() } } }
    var topRoom: CGFloat = 0 { didSet { if oldValue != topRoom { refresh() } } }
    private func refresh() { (superview as? NSScrollView)?.reflectScrolledClipView(self) }
    override var documentRect: NSRect {
        var rect = super.documentRect
        rect.origin.y -= topRoom
        rect.size.height += topRoom + bottomRoom
        return rect
    }
}

struct NativeEditor: NSViewRepresentable {
    @AppStorage("writingTheme") private var themeName = "graphite"
    @AppStorage("editorZoom") private var globalZoom = 1.0
    /// A surface that scales on its own (the parallel pane) passes its own zoom and key.
    var zoom: Double? = nil
    var zoomKey: String = WritingZoom.mainKey
    @Binding var text: String
    var review: Bool
    var words: String
    var fontSize: Double
    var pageWidth: Double
    var commands: EditorCommands
    var fontFamily: String = "Charter"
    var lineSpacing: Double = 0.28
    var focusParagraph: Bool = false
    var focusGradient: Bool = true
    var readOnly: Bool = false
    var darker: Bool = false
    var syntaxClasses: Int = 0
    var colorVersion: Int = 0
    var spellCheckEnabled: Bool = true
    /// "off", "room" (scroll past the last line), or "center" (also keep the line you're writing centered).
    var typewriterMode: String = "off"
    /// Names of the project's characters, places, and world notes to make stand out (nil when off).
    var nameHighlighter: NameHighlighter? = nil
    /// Whether highlighted names shimmer (a soft moving light inside the letters) instead of just taking a color.
    var nameShimmer: Bool = true
    var nameKinds: Set<CardKind> = Set(CardKind.allCases)
    var documentUndoManager: UndoManager? = nil
    var saveAction: (() -> Void)? = nil
    var sidebarGesture: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = WritingScrollView(frame: NSRect(x: 0, y: 0, width: 760, height: 600))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.findBarPosition = .aboveContent
        scroll.sidebarGesture = sidebarGesture
        scroll.zoomKey = zoomKey
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
        scroll.contentView = RoomClipView()
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
        (scroll as? WritingScrollView)?.sidebarGesture = sidebarGesture
        (scroll as? WritingScrollView)?.zoomKey = zoomKey
        let zoom = self.zoom ?? globalZoom
        editor.syntaxClasses = syntaxClasses
        editor.colorVersion = colorVersion
        editor.bodyFontFamily = fontFamily
        editor.lineSpacingRatio = lineSpacing
        editor.focusParagraph = focusParagraph && !readOnly
        editor.focusGradient = focusGradient
        editor.bodySize = fontSize * zoom
        editor.themeName = darker ? "midnight" : themeName
        editor.pageWidth = pageWidth * zoom
        editor.typewriterMode = typewriterMode
        editor.nameHighlighter = nameHighlighter
        editor.nameShimmer = nameShimmer
        editor.nameKinds = nameKinds
        editor.updatePageMargins()
        editor.updateScrollRoom()
        editor.appearance = darker ? NSAppearance(named: .darkAqua) : nil
        editor.backgroundColor = WritingTheme.named(editor.themeName).background
        scroll.contentView.backgroundColor = WritingTheme.named(editor.themeName).background
        editor.insertionPointColor = WritingTheme.named(editor.themeName).foreground
        editor.reviewEnabled = review
        editor.reviewWords = words
        editor.decorate()
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeEditor
        init(_ parent: NativeEditor) { self.parent = parent }
        func undoManager(for view: NSTextView) -> UndoManager? { parent.documentUndoManager ?? view.window?.undoManager }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let editor = notification.object as? WritingTextView else { return }
            editor.updateFocus()
            if !WritingTextView.isPointerDriven(NSApp.currentEvent) { editor.centerCaretIfNeeded() }
        }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? WritingTextView else { return }
            guard parent.text != editor.string else { return }
            parent.text = editor.string
            editor.decorate()
            editor.centerCaretIfNeeded()
        }
    }
}

final class WritingTextView: NSTextView {
    var reviewEnabled = true
    var reviewWords = Prose.defaultWords
    var syntaxClasses = 0
    var colorVersion = 0
    var saveAction: (() -> Void)?
    var themeName = "graphite"
    private var lastThemeName = ""
    var bodyFontFamily = "Charter"
    var lineSpacingRatio = 0.28
    var focusParagraph = false
    /// True fades text smoothly with distance from the paragraph being written; false dims it all evenly.
    var focusGradient = true
    private var scrollObserver: NSObjectProtocol?
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
    private var lastNameKey = ""
    var nameHighlighter: NameHighlighter?
    var nameShimmer = true
    var nameKinds = Set(CardKind.allCases)
    /// Where names were found on the last styling pass, so the shimmer knows where to play.
    private(set) var nameRanges: [NSRange] = []
    private var nameKey: String {
        (nameHighlighter?.signature ?? "") + (nameShimmer ? "#shimmer" : "#color") + nameKinds.map(\.rawValue).sorted().joined(separator: ",")
    }
    private var nameRangeKinds: [CardKind] = []
    private var shimmerTimer: Timer?
    private var shimmerStart = Date()
    /// The paragraph being written while paragraph focus is on; names elsewhere are dimmed and stay still.
    private var focusActive: NSRange?
    private var didSetInitialFocus = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeScrollingForFocus()
        updateShimmer()
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
        updateScrollRoom()
    }

    /// "room" leaves half a window of empty scroll space below the last line. "center" does too, and also keeps the line
    /// you're writing in the middle once the text has reached it. The top of the page is never scrolled past: near the
    /// start of a file the text stays where it is instead of sliding down to the middle of the window.
    var typewriterMode = "off"

    func updateScrollRoom() {
        guard let clip = enclosingScrollView?.contentView as? RoomClipView else { return }
        let half = max(0, clip.bounds.height / 2 - 24)
        clip.bottomRoom = typewriterMode == "off" ? 0 : half
        clip.topRoom = 0
    }

    /// The caret's line, in this view's coordinates.
    private func caretLineRect() -> NSRect? {
        guard let layoutManager else { return nil }
        let length = (string as NSString).length
        let location = selectedRange().location
        var rect: NSRect
        if location >= length {
            rect = layoutManager.extraLineFragmentRect
            if rect.isEmpty {
                guard layoutManager.numberOfGlyphs > 0 else { return nil }
                rect = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.numberOfGlyphs - 1, effectiveRange: nil)
            }
        } else {
            rect = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: location), effectiveRange: nil)
        }
        rect.origin.y += textContainerOrigin.y
        return rect
    }

    /// While the page is being kept centered, typing and arrow keys are the only things that move it, and they do so through
    /// `centerCaretIfNeeded`. AppKit's own scroll-to-the-caret would pull the page a different way at the same moment.
    override func scrollRangeToVisible(_ range: NSRange) {
        if typewriterMode == "center", window?.firstResponder === self, NSApp.currentEvent?.type == .keyDown, enclosingScrollView?.contentView is RoomClipView { return }
        super.scrollRangeToVisible(range)
    }

    /// Clicks and scrolling with the pointer never re-center the page; only typing and keyboard movement do.
    static func isPointerDriven(_ event: NSEvent?) -> Bool {
        switch event?.type {
        case .leftMouseDown?, .leftMouseUp?, .leftMouseDragged?, .rightMouseDown?, .otherMouseDown?, .scrollWheel?: return true
        default: return false
        }
    }

    /// In "center" mode, glides the page so the line you're writing sits in the middle of the window, wherever
    /// on the page you started, except that the page never slides down past its first line. It moves a line at a time, smoothly, and stays put while you stay on a line.
    func centerCaretIfNeeded(animated: Bool = true) {
        guard typewriterMode == "center", window?.firstResponder === self,
              let scroll = enclosingScrollView, let rect = caretLineRect() else { return }
        let clip = scroll.contentView
        // scroll(to:) doesn't clamp, so ask the clip view where that position is allowed to be.
        let wanted = NSRect(x: clip.bounds.minX, y: rect.midY - clip.bounds.height / 2, width: clip.bounds.width, height: clip.bounds.height)
        // Layout is lazy: after an edit only the text near the top may be laid out, which makes the page look short and would
        // clamp the target to a false "bottom". If the target reaches past what is known, lay out the whole page first.
        if wanted.maxY > clip.documentRect.maxY, let layoutManager, let container = textContainer {
            layoutManager.ensureLayout(for: container)
            sizeToFit()
            scroll.reflectScrolledClipView(clip)
        }
        let target = clip.constrainBoundsRect(wanted).origin
        guard abs(target.y - clip.bounds.origin.y) > rect.height * 0.4 else { return }
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            clip.scroll(to: target)
            scroll.reflectScrolledClipView(clip)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            clip.animator().setBoundsOrigin(target)
        }
    }

    func updatePageMargins() {
        let margin = max(28, (bounds.width - pageWidth) / 2)
        let inset = NSSize(width: margin, height: 48)
        if textContainerInset != inset { textContainerInset = inset }
    }

    // A color well can send changeColor through the first-responder chain.
    // Markdown colors are display preferences, never rich-text document mutations.
    override func changeColor(_ sender: Any?) {}

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
        guard lastStyledText != string || lastStyledSize != bodySize || lastStyledFamily != bodyFontFamily || lastStyledSpacing != lineSpacingRatio || lastSyntaxClasses != syntaxClasses || lastColorVersion != colorVersion || lastThemeName != themeName || lastNameKey != nameKey else { return }
        styling = true
        defer { styling = false }
        let full = NSRange(location: 0, length: storage.length)
        let base = NSFontManager.shared.font(withFamily: bodyFontFamily, traits: [], weight: 5, size: bodySize) ?? .systemFont(ofSize: bodySize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = bodySize * lineSpacingRatio
        paragraph.paragraphSpacing = bodySize * 0.25
        let attributes: [NSAttributedString.Key: Any] = [.font: base, .foregroundColor: WritingTheme.named(themeName).foreground, .paragraphStyle: paragraph]
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
        // Names of characters, places, and world notes stand out on top of everything else, by color and optionally a glow.
        nameRanges = []
        nameRangeKinds = []
        if let namer = nameHighlighter, !namer.isEmpty {
            for match in namer.matches(in: string, kinds: nameKinds) {
                storage.addAttribute(.foregroundColor, value: Self.nameColor(match.kind), range: match.range)
                nameRanges.append(match.range)
                nameRangeKinds.append(match.kind)
            }
        }
        storage.endEditing()
        typingAttributes = attributes
        lastStyledText = string
        lastStyledSize = bodySize
        lastStyledFamily = bodyFontFamily
        lastStyledSpacing = lineSpacingRatio
        lastSyntaxClasses = syntaxClasses
        lastColorVersion = colorVersion
        lastThemeName = themeName
        lastNameKey = nameKey
        updateShimmer()
    }

    /// The color for a kind of name: your own choice, or a warm gold for characters, teal for places, violet for world notes.
    static func nameColor(_ kind: CardKind) -> NSColor {
        if let hex = UserDefaults.standard.string(forKey: "nameColor.\(kind.rawValue)"), let custom = NSColor(quillHex: hex) { return custom }
        switch kind {
        case .character: return pastel(light: NSColor(red: 0.64, green: 0.40, blue: 0.02, alpha: 1), dark: NSColor(red: 1.00, green: 0.83, blue: 0.42, alpha: 1))
        case .location: return pastel(light: NSColor(red: 0.02, green: 0.47, blue: 0.52, alpha: 1), dark: NSColor(red: 0.45, green: 0.93, blue: 0.96, alpha: 1))
        case .lore: return pastel(light: NSColor(red: 0.44, green: 0.26, blue: 0.72, alpha: 1), dark: NSColor(red: 0.82, green: 0.70, blue: 1.00, alpha: 1))
        }
    }

    // MARK: Name shimmer

    /// A soft light drifting through the letters of each name, then fading back to its color. It runs only while names are
    /// on screen, never in Reduce Motion, and its strength and speed are set in Writing Style.
    func updateShimmer() {
        let strength = UserDefaults.standard.object(forKey: "nameShimmerStrength") as? Double ?? 0.6
        let wanted = nameShimmer && strength > 0.01 && !nameRanges.isEmpty && window != nil && isEditable
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if wanted {
            guard shimmerTimer == nil else { return }
            shimmerStart = Date()
            let timer = Timer(timeInterval: 1.0 / 24, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.shimmerTick() } }
            RunLoop.main.add(timer, forMode: .common)
            shimmerTimer = timer
        } else if shimmerTimer != nil {
            shimmerTimer?.invalidate()
            shimmerTimer = nil
            restoreNameColors()
        }
    }

    private func restoreNameColors() {
        guard let layoutManager else { return }
        let length = (string as NSString).length
        for range in nameRanges where NSMaxRange(range) <= length && focusActive == nil {
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
        }
    }

    private func shimmerTick() {
        guard let layoutManager, let container = textContainer, window != nil, !styling else { return }
        let defaults = UserDefaults.standard
        let strength = min(1, max(0, defaults.object(forKey: "nameShimmerStrength") as? Double ?? 0.6))
        let speed = min(3, max(0.2, defaults.object(forKey: "nameShimmerSpeed") as? Double ?? 1))
        let length = (string as NSString).length
        let visibleGlyphs = layoutManager.glyphRange(forBoundingRect: visibleRect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y), in: container)
        let visible = layoutManager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
        let dark = WritingTheme.named(themeName).dark
        let time = Date().timeIntervalSince(shimmerStart) * speed
        for (index, range) in nameRanges.enumerated() where NSMaxRange(range) <= length && NSIntersectionRange(range, visible).length > 0 {
            if let active = focusActive, NSIntersectionRange(range, active).length == 0 { continue }
            var base = Self.nameColor(nameRangeKinds[index])
            effectiveAppearance.performAsCurrentDrawingAppearance { base = base.usingColorSpace(.sRGB) ?? base }
            let target = dark ? NSColor.white : NSColor.black
            // A band of light travels along the name, once every couple of seconds, with a rest between passes.
            for offset in 0..<range.length {
                let phase = (time * 0.55 - Double(offset) * 0.09).truncatingRemainder(dividingBy: 1.6)
                let position = phase < 0 ? phase + 1.6 : phase
                let band = position < 1 ? sin(position * .pi) : 0
                let mix = CGFloat(band * strength * (dark ? 0.7 : 0.55))
                let color = base.blended(withFraction: mix, of: target) ?? base
                layoutManager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: NSRange(location: range.location + offset, length: 1))
            }
        }
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

    /// The gradient depends on what is on screen, so it has to follow the scroll position.
    private func observeScrollingForFocus() {
        guard scrollObserver == nil, let clip = enclosingScrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.focusParagraph, self.focusGradient else { return }
                self.updateFocus()
            }
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            shimmerTimer?.invalidate()
            shimmerTimer = nil
        }
        if newWindow == nil, let scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
            self.scrollObserver = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func updateFocus() {
        guard !styling, let layoutManager, let container = textContainer else { return }
        let length = (string as NSString).length
        let whole = NSRange(location: 0, length: length)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)
        focusActive = nil
        guard focusParagraph, length > 0 else { return }
        let active = FocusParagraph.range(in: string, caret: selectedRange().location)
        focusActive = active
        // withAlphaComponent bakes a dynamic color into concrete RGBA using whatever appearance
        // happens to be current, so resolve under this view's own appearance for correct fades.
        var base = NSColor.labelColor
        effectiveAppearance.performAsCurrentDrawingAppearance { base = WritingTheme.named(themeName).foreground }
        func fade(_ alpha: CGFloat, _ range: NSRange) {
            guard range.length > 0 else { return }
            layoutManager.addTemporaryAttribute(.foregroundColor, value: base.withAlphaComponent(alpha), forCharacterRange: range)
        }
        guard focusGradient else {
            fade(0.25, NSRange(location: 0, length: active.location))
            fade(0.25, NSRange(location: NSMaxRange(active), length: max(0, length - NSMaxRange(active))))
            return
        }

        // Vertical extent of the paragraph being written.
        let activeTop: CGFloat, activeBottom: CGFloat
        if active.length > 0 {
            let glyphs = layoutManager.glyphRange(forCharacterRange: active, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
            (activeTop, activeBottom) = (rect.minY, rect.maxY)
        } else if active.location >= length {
            let rect = layoutManager.extraLineFragmentRect
            (activeTop, activeBottom) = rect.isEmpty ? (0, 0) : (rect.minY, rect.maxY)
        } else {
            let rect = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: active.location), effectiveRange: nil)
            (activeTop, activeBottom) = (rect.minY, rect.maxY)
        }

        // Fade smoothly with distance from that paragraph. Only lines near the screen are computed;
        // everything farther away sits at the floor.
        let floorAlpha: CGFloat = 0.07, nearAlpha: CGFloat = 0.62
        let span = CGFloat(bodySize) * 20
        func alpha(forDistance d: CGFloat) -> CGFloat {
            let t = min(1, max(0, d / span))
            return nearAlpha + (floorAlpha - nearAlpha) * (t * t * (3 - 2 * t))
        }
        let origin = textContainerOrigin
        var area = (enclosingScrollView?.contentView.bounds ?? visibleRect).offsetBy(dx: -origin.x, dy: -origin.y)
        area = area.insetBy(dx: 0, dy: -area.height)
        let nearGlyphs = layoutManager.glyphRange(forBoundingRect: area, in: container)
        let nearChars = layoutManager.characterRange(forGlyphRange: nearGlyphs, actualGlyphRange: nil)
        fade(floorAlpha, NSRange(location: 0, length: nearChars.location))
        fade(floorAlpha, NSRange(location: NSMaxRange(nearChars), length: length - NSMaxRange(nearChars)))
        layoutManager.enumerateLineFragments(forGlyphRange: nearGlyphs) { rect, _, _, glyphRange, _ in
            let chars = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            if NSIntersectionRange(chars, active).length > 0 { return }
            let distance = rect.maxY <= activeTop ? activeTop - rect.maxY : max(0, rect.minY - activeBottom)
            fade(alpha(forDistance: distance), chars)
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
        guard let converted = usingColorSpace(.sRGB) else { return "#808080" }
        return String(format: "#%02X%02X%02X", Int(min(1, max(0, converted.redComponent)) * 255), Int(min(1, max(0, converted.greenComponent)) * 255), Int(min(1, max(0, converted.blueComponent)) * 255))
    }
}

@MainActor
final class EditorCommands: ObservableObject {
    weak var editor: WritingTextView?
    /// Replaces the open document's text in place; set by the view that owns the document binding.
    var loadText: ((String, URL?) -> Void)?
    init() { SingleDocumentCoordinator.shared.register(self) }
    func jump(to range: NSRange) {
        guard let editor, NSMaxRange(range) <= (editor.string as NSString).length else { return }
        editor.window?.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: range.location, length: 0))
        editor.scrollRangeToVisible(range)
        editor.showFindIndicator(for: range)
    }
    func switchTo(_ url: URL, completion: @escaping (Error?) -> Void) {
        let source = editor?.window?.windowController?.document as? NSDocument
        SingleDocumentCoordinator.shared.switchDocument(from: source, to: url, completion: completion)
    }
    func format(_ action: Selector) {
        guard let editor else { return }
        editor.window?.makeFirstResponder(editor)
        NSApp.sendAction(action, to: editor, from: nil)
    }
}
