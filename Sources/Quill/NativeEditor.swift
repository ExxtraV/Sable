import AppKit
import Combine
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
    /// The project's cards, so right-clicking a highlighted name can offer to open its file or show its card.
    var nameCards: [IndexedCard] = []
    var openNameFile: ((URL) -> Void)? = nil
    var showNameCard: ((URL) -> Void)? = nil
    /// Dim the symbols of Markdown (the stars, hashes, and brackets) so the words stand out.
    var dimMarkers: Bool = true
    /// Curly quotes, em dashes, and ellipses as you type.
    var smartTypography: Bool = false
    /// The page is drawn behind the editor (edge shading), so the editor paints nothing of its own.
    var transparentBackground: Bool = false
    var documentUndoManager: UndoManager? = nil
    /// The document whose saves must wait for typing to reach `text` (the window's document when nil).
    var editingDocument: NSDocument? = nil
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
        context.coordinator.attach(editor, text: text)
        scroll.contentView = RoomClipView()
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? WritingTextView else { return }
        context.coordinator.syncFromBinding(editor)
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
        editor.nameCards = nameCards
        editor.openNameFile = openNameFile
        editor.showNameCard = showNameCard
        editor.dimMarkers = dimMarkers
        editor.smartTypography = smartTypography
        editor.updatePageMargins()
        editor.updateScrollRoom()
        editor.appearance = darker ? NSAppearance(named: .darkAqua) : nil
        let paper = WritingTheme.named(editor.themeName).background
        editor.backgroundColor = transparentBackground ? .clear : paper
        editor.drawsBackground = !transparentBackground
        scroll.drawsBackground = !transparentBackground
        scroll.contentView.drawsBackground = !transparentBackground
        scroll.contentView.backgroundColor = transparentBackground ? .clear : paper
        editor.insertionPointColor = WritingTheme.named(editor.themeName).foreground
        editor.reviewEnabled = review
        editor.reviewWords = words
        editor.decorate()
        (scroll as? WritingScrollView)?.zoomDidApply(zoom)
        context.coordinator.publishStatsIfSettled()
    }
    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.flush()
    }

    /// Typing stays in the text view and reaches SwiftUI's copy of the text (`text`) in batches: after a short pause, at
    /// least every `longestWait` while typing goes on, and at once before anything else could read it (a save, closing,
    /// a menu, a click, a shortcut, leaving the editor). Handing a whole novel to SwiftUI on every keystroke made it
    /// recount and redraw everything that depends on the text.
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeEditor
        weak var editor: WritingTextView?
        /// The binding's text when the editor and SwiftUI last agreed.
        private(set) var syncedText: String?
        /// The editor holds typing that SwiftUI hasn't seen yet.
        private(set) var hasPendingText = false
        private var pendingSince: TimeInterval = 0
        private var flushTimer: Timer?
        private weak var registeredDocument: NSDocument?
        private var fileDateWhenPending: Date?
        static let pause: TimeInterval = 0.3
        static let longestWait: TimeInterval = 1.5

        init(_ parent: NativeEditor) {
            self.parent = parent
            super.init()
            PendingText.register(self)
        }
        func attach(_ editor: WritingTextView, text: String) {
            self.editor = editor
            syncedText = text
        }
        func undoManager(for view: NSTextView) -> UndoManager? { parent.documentUndoManager ?? view.window?.undoManager }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard let editor = notification.object as? WritingTextView else { return }
            editor.updateFocus()
            parent.commands.reportSelection(in: editor)
            if !WritingTextView.isPointerDriven(NSApp.currentEvent) { editor.centerCaretIfNeeded() }
        }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? WritingTextView else { return }
            self.editor = editor
            editor.decorate()
            editor.centerCaretIfNeeded()
            parent.commands.typing.send()
            if !hasPendingText {
                hasPendingText = true
                pendingSince = ProcessInfo.processInfo.systemUptime
                // While typing is pending the document counts as edited and commits it before saving or closing.
                let document = parent.editingDocument ?? editor.window?.windowController?.document as? NSDocument
                fileDateWhenPending = document?.fileModificationDate
                document?.objectDidBeginEditing(self)
                registeredDocument = document
            }
            let waited = ProcessInfo.processInfo.systemUptime - pendingSince
            let timer = Timer(timeInterval: max(0, min(Self.pause, Self.longestWait - waited)), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.flush() }
            }
            flushTimer?.invalidate()
            RunLoop.main.add(timer, forMode: .common)
            flushTimer = timer
        }

        /// Hands pending typing to SwiftUI, with the status bar's counts for it.
        func flush() {
            flushTimer?.invalidate()
            flushTimer = nil
            guard hasPendingText, let editor else { return }
            hasPendingText = false
            let text = editor.string
            syncedText = text
            parent.text = text
            if let document = registeredDocument {
                registeredDocument = nil
                document.objectDidEndEditing(self)
                // Autosave doesn't wait for editors. If one ran while typing was pending, it saved the older text, so the
                // document must still count as changed.
                if document.fileModificationDate != fileDateWhenPending { document.updateChangeCount(.changeDone) }
            }
            parent.commands.publish(editor.documentStats(text: text), knownToDiffer: true)
        }

        /// Takes the binding's text when something other than typing changed it (opening a file, a scene tag, a
        /// front-matter edit), but never lets the binding's older copy overwrite typing it hasn't received yet.
        func syncFromBinding(_ editor: WritingTextView) {
            self.editor = editor
            let text = parent.text
            if let syncedText, text == syncedText { return }
            syncedText = text
            if hasPendingText {
                hasPendingText = false
                flushTimer?.invalidate()
                flushTimer = nil
                registeredDocument?.objectDidEndEditing(self)
                registeredDocument = nil
            }
            guard editor.string != text else { return }
            let selection = editor.selectedRange()
            editor.string = text
            let length = (text as NSString).length
            editor.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        }

        /// After a SwiftUI update restyled the text (a new file, a changed setting), refresh the status bar's counts.
        func publishStatsIfSettled() {
            guard !hasPendingText, let editor, let text = syncedText, parent.commands.stats != editor.documentStats(text: text) else { return }
            // Not during SwiftUI's update. Counted again when it runs, since typing may have been handed over by then.
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.hasPendingText, let editor = self.editor, let text = self.syncedText else { return }
                self.parent.commands.publish(editor.documentStats(text: text))
            }
        }
    }
}

extension NativeEditor.Coordinator: NSEditor {
    func commitEditing() -> Bool {
        flush()
        return true
    }
    func commitEditingWithoutPresentingError() throws { flush() }
    func discardEditing() { flush() }
    func commitEditing(withDelegate delegate: Any?, didCommit didCommitSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        flush()
        guard let delegate = delegate as AnyObject?, let didCommitSelector else { return }
        typealias DidCommit = @convention(c) (AnyObject, Selector, AnyObject, Bool, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(delegate.method(for: didCommitSelector), to: DidCommit.self)(delegate, didCommitSelector, self, true, contextInfo)
    }
}

/// Every editor with typing SwiftUI hasn't seen yet hands it over before anything that could read the document: a click
/// anywhere, a keyboard shortcut, a menu opening, the app going to the background or quitting.
@MainActor
enum PendingText {
    private static let coordinators = NSHashTable<NativeEditor.Coordinator>.weakObjects()
    private static var watching = false

    static func register(_ coordinator: NativeEditor.Coordinator) {
        coordinators.add(coordinator)
        guard !watching else { return }
        watching = true
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { event in
            if event.type != .keyDown || !event.modifierFlags.intersection([.command, .control]).isEmpty {
                MainActor.assumeIsolated { flushAll() }
            }
            return event
        }
        for name in [NSMenu.didBeginTrackingNotification, NSApplication.willResignActiveNotification, NSApplication.willTerminateNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in MainActor.assumeIsolated { flushAll() } }
        }
    }

    static func flushAll() {
        for coordinator in coordinators.allObjects { coordinator.flush() }
    }
}

final class WritingTextView: NSTextView {
    var reviewEnabled = true
    var reviewWords = Prose.defaultWords
    var syntaxClasses = 0
    var colorVersion = 0
    var saveAction: (() -> Void)?
    var themeName = "graphite"
    var bodyFontFamily = "Charter"
    var lineSpacingRatio = 0.28
    var focusParagraph = false
    /// True fades text smoothly with distance from the paragraph being written; false dims it all evenly.
    var focusGradient = true
    private var scrollObserver: NSObjectProtocol?
    var bodySize: Double = 19
    var pageWidth: Double = 680
    private var contextRange: NSRange?
    /// True while a styling pass is changing attributes, so nothing else touches them at the same time.
    var styling = false
    /// What the last styling pass left behind, so the next one can restyle only what an edit changed.
    let style = EditorStyleState()
    /// Between asking to change the text and the change being done.
    private var changingText = false
    /// Paragraph focus has dimmed some of the text, so the next update has to clear it first.
    private var focusPainted = false
    var nameHighlighter: NameHighlighter?
    var nameShimmer = true
    var nameKinds = Set(CardKind.allCases)
    var nameCards: [IndexedCard] = []
    var openNameFile: ((URL) -> Void)?
    var showNameCard: ((URL) -> Void)?
    var dimMarkers = true
    var smartTypography = false
    var nameKey: String {
        (nameHighlighter?.signature ?? "") + (nameShimmer ? "#shimmer" : "#color") + nameKinds.map(\.rawValue).sorted().joined(separator: ",")
    }
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
        let length = textStorage?.length ?? 0
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
    /// `defaults write local.quill.editor debugCentering -bool true` makes the page-centering code log what it decides to
    /// /tmp/sable-centering.log, which is how a scrolling problem gets tracked down.
    static var debugCentering: Bool { UserDefaults.standard.bool(forKey: "debugCentering") }
    static func logCentering(_ message: @autoclosure () -> String) {
        guard debugCentering else { return }
        let line = "\(Date().formatted(.iso8601)) \(message())\n"
        let url = URL(fileURLWithPath: "/tmp/sable-centering.log")
        if let handle = try? FileHandle(forWritingTo: url) { handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }

    func centerCaretIfNeeded(animated: Bool = true) {
        guard typewriterMode == "center", window?.firstResponder === self,
              let scroll = enclosingScrollView, let lineRect = caretLineRect() else { return }
        let clip = scroll.contentView
        // AppKit can leave the text view's own frame origin away from zero (it shifts it as the page is laid out), and the
        // clip view's scroll position is measured in the space around that frame. Measure the line the same way.
        let rect = convert(lineRect, to: clip)
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
        Self.logCentering("center caretMid=\(Int(rect.midY)) clipOrigin=\(Int(clip.bounds.origin.y)) clipH=\(Int(clip.bounds.height)) wanted=\(Int(wanted.origin.y)) target=\(Int(target.y)) docRect=\(clip.documentRect) frame=\(frame) rooms=\((clip as? RoomClipView).map { "\($0.topRoom)/\($0.bottomRoom)" } ?? "-") len=\(textStorage?.length ?? 0) sel=\(selectedRange().location)")
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
        let inset = NSSize(width: margin, height: 84)
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
        // Inside a list or quote, Return continues it (and on an empty item, ends it).
        if isEditable, !hasMarkedText(), let edit = MarkdownEditing.newline(in: string, selection: selectedRange()) {
            apply(edit)
            return
        }
        super.insertNewline(sender)
    }

    override func insertTab(_ sender: Any?) {
        if isEditable, let edit = MarkdownEditing.indent(in: string, selection: selectedRange(), outdent: false) { apply(edit); return }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if isEditable, let edit = MarkdownEditing.indent(in: string, selection: selectedRange(), outdent: true) { apply(edit); return }
        super.insertBacktab(sender)
    }

    /// Curly quotes, dashes, and ellipses as you type, when that is turned on.
    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if smartTypography, isEditable, !hasMarkedText(), replacementRange.location == NSNotFound,
           let typed = insertString as? String, typed.count == 1, selectedRange().length == 0 {
            let caret = selectedRange().location
            if let change = SmartTypography.change(typing: typed, in: string, at: caret) {
                apply(TextEdit(range: NSRange(location: caret - change.deleteCount, length: change.deleteCount),
                               replacement: change.insert,
                               selection: NSRange(location: caret - change.deleteCount + (change.insert as NSString).length, length: 0)))
                return
            }
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    private func apply(_ edit: TextEdit) {
        replace(edit.range, with: edit.replacement, selection: edit.selection)
    }

    @discardableResult
    private func leaveFormatting() -> Bool {
        guard let offset = MarkdownSyntax.exitOffset(in: string, selection: selectedRange(), blocks: currentBlocks()) else { return false }
        setSelectedRange(NSRange(location: offset, length: 0))
        return true
    }

    @objc func exitFormatting(_ sender: Any?) { _ = leaveFormatting() }

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
        let length = textStorage?.length ?? 0
        for range in nameRanges where NSMaxRange(range) <= length && focusActive == nil {
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
        }
    }

    private func shimmerTick() {
        guard let layoutManager, let container = textContainer, window != nil, !styling else { return }
        let defaults = UserDefaults.standard
        let strength = min(1, max(0, defaults.object(forKey: "nameShimmerStrength") as? Double ?? 0.6))
        let speed = min(3, max(0.2, defaults.object(forKey: "nameShimmerSpeed") as? Double ?? 1))
        let length = textStorage?.length ?? 0
        let visibleGlyphs = layoutManager.glyphRange(forBoundingRect: visibleRect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y), in: container)
        let visible = layoutManager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
        let dark = WritingTheme.named(themeName).dark
        let time = Date().timeIntervalSince(shimmerStart) * speed
        for (index, range) in nameRanges.enumerated() where NSMaxRange(range) <= length && NSIntersectionRange(range, visible).length > 0 {
            if let active = focusActive, NSIntersectionRange(range, active).length == 0 { continue }
            var base = Self.nameColor(style.nameKinds[index])
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
        (delegate as? NativeEditor.Coordinator)?.flush()
        if let saveAction { saveAction() }
        else { _ = nextResponder?.tryToPerform(#selector(saveDocument(_:)), with: sender) }
    }

    /// The gradient depends on what is on screen, so it has to follow the scroll position.
    private func observeScrollingForFocus() {
        guard scrollObserver == nil, let clip = enclosingScrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if Self.debugCentering {
                    Self.logCentering("scroll origin=\(Int(clip.bounds.origin.y)) via \(Thread.callStackSymbols.dropFirst(2).prefix(7).map { String($0.split(separator: " ", omittingEmptySubsequences: true).dropFirst(3).joined(separator: " ").prefix(70)) }.joined(separator: " <- "))")
                }
                guard self.focusParagraph, self.focusGradient else { return }
                self.updateFocus()
            }
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            (delegate as? NativeEditor.Coordinator)?.flush()
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
        let length = textStorage?.length ?? 0
        // Clearing the whole text costs time in proportion to its length, so only do it when there is dimming to clear.
        if focusPainted {
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: length))
            focusPainted = false
        }
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
            focusPainted = true
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
        // The clip view's bounds are in its own space; AppKit can leave this view's frame origin away from zero (see
        // centerCaretIfNeeded), so convert before measuring, or the "near the screen" band lands far from the caret.
        let seen = enclosingScrollView.map { convert($0.contentView.bounds, from: $0.contentView) } ?? visibleRect
        var area = seen.offsetBy(dx: -origin.x, dy: -origin.y)
        area = area.insetBy(dx: 0, dy: -area.height)
        let nearGlyphs = layoutManager.glyphRange(forBoundingRect: area, in: container)
        let nearChars = layoutManager.characterRange(forGlyphRange: nearGlyphs, actualGlyphRange: nil)
        // A paragraph taller than the band (a long one at a large zoom) reaches past it, and stays undimmed there too.
        func fadeAroundActive(_ alpha: CGFloat, _ range: NSRange) {
            fade(alpha, NSRange(location: range.location, length: max(0, min(NSMaxRange(range), active.location) - range.location)))
            let after = max(range.location, NSMaxRange(active))
            fade(alpha, NSRange(location: after, length: max(0, NSMaxRange(range) - after)))
        }
        fadeAroundActive(floorAlpha, NSRange(location: 0, length: nearChars.location))
        fadeAroundActive(floorAlpha, NSRange(location: NSMaxRange(nearChars), length: length - NSMaxRange(nearChars)))
        layoutManager.enumerateLineFragments(forGlyphRange: nearGlyphs) { rect, _, _, glyphRange, _ in
            let chars = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            if NSIntersectionRange(chars, active).length > 0 { return }
            let distance = rect.maxY <= activeTop ? activeTop - rect.maxY : max(0, rect.minY - activeBottom)
            fade(alpha(forDistance: distance), chars)
        }
    }

    /// Styling, prose suggestions, and paragraph focus, brought up to date with the text (see EditorStyling.swift).
    func decorate() {
        styleText()
        updateFocus()
    }

    override func shouldChangeText(inRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
        let allowed = super.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings)
        if allowed { changingText = true }
        return allowed
    }

    override func didChangeText() {
        changingText = false
        super.didChangeText()
    }

    /// Ending an input method's composition without committing it changes no text, so nothing else would restyle what
    /// was composed until the next edit.
    override func unmarkText() {
        super.unmarkText()
        if !changingText, !hasMarkedText() { decorate() }
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { (delegate as? NativeEditor.Coordinator)?.flush() }
        return resigned
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        if let card = namedCard(at: index) {
            let open = NSMenuItem(title: "Open “\(card.stem)”", action: #selector(openNamedFile(_:)), keyEquivalent: "")
            open.target = self
            open.representedObject = card.url
            let show = NSMenuItem(title: "Show \(card.kind.title) Card", action: #selector(showNamedCard(_:)), keyEquivalent: "")
            show.target = self
            show.representedObject = card.url
            menu.insertItem(.separator(), at: 0)
            menu.insertItem(show, at: 0)
            menu.insertItem(open, at: 0)
        }
        contextRange = currentSuggestions().first { NSLocationInRange(index, $0) }
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
    /// The card behind the highlighted name at `index`, if there is one.
    private func namedCard(at index: Int) -> IndexedCard? {
        guard !nameCards.isEmpty else { return nil }
        for (range, kind) in zip(nameRanges, style.nameKinds) where NSLocationInRange(index, range) {
            let text = (string as NSString).substring(with: range)
            return CardIndex.match(text, kind: kind, in: nameCards)
        }
        return nil
    }
    @objc private func openNamedFile(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        openNameFile?(url)
    }
    @objc private func showNamedCard(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        showNameCard?(url)
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
    @objc func markStrikethrough(_ sender: Any?) { wrap("~~") }
    @objc func markCode(_ sender: Any?) { wrap("`") }
    @objc func markLink(_ sender: Any?) {
        apply(MarkdownEditing.link(in: string, selection: selectedRange(), clipboard: NSPasteboard.general.string(forType: .string)))
    }
    @objc func markHeading(_ sender: Any?) { apply(MarkdownEditing.cycleHeading(in: string, selection: selectedRange())) }
    @objc func markQuote(_ sender: Any?) { apply(MarkdownEditing.toggleLine(.quote, in: string, selection: selectedRange())) }
    @objc func markBulletList(_ sender: Any?) { apply(MarkdownEditing.toggleLine(.bullet, in: string, selection: selectedRange())) }
    @objc func markNumberedList(_ sender: Any?) { apply(MarkdownEditing.toggleLine(.numbered, in: string, selection: selectedRange())) }
    @objc func markTaskList(_ sender: Any?) { apply(MarkdownEditing.toggleLine(.task, in: string, selection: selectedRange())) }
    @objc func markSceneBreak(_ sender: Any?) { apply(MarkdownEditing.horizontalRule(in: string, selection: selectedRange())) }

    /// Paste from Word, Google Docs, or a web page with its italics, bold, headings, lists, and links as Markdown.
    @objc func pasteAsMarkdown(_ sender: Any?) {
        guard isEditable else { return }
        let board = NSPasteboard.general
        var rich: NSAttributedString?
        if let data = board.data(forType: .rtf) { rich = NSAttributedString(rtf: data, documentAttributes: nil) }
        else if let data = board.data(forType: .html) { rich = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) }
        if let rich, rich.length > 0 {
            let markdown = RichTextMarkdown.markdown(from: rich)
            let range = selectedRange()
            replace(range, with: markdown, selection: NSRange(location: range.location + (markdown as NSString).length, length: 0))
        } else {
            pasteAsPlainText(sender)
        }
    }

    /// Replaces the whole text in one undoable step, keeping the caret where it was.
    func replaceEntireText(_ text: String) {
        let old = selectedRange()
        let length = (text as NSString).length
        replace(NSRange(location: 0, length: (string as NSString).length), with: text,
                selection: NSRange(location: min(old.location, length), length: 0))
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
    /// Words in the selection, for the status bar (0 when nothing is selected).
    @Published var selectionWords = 0
    /// The document's word and suggestion counts, published whenever the editor hands its text to SwiftUI.
    @Published private(set) var stats: DocumentStats?
    /// Fires on every keystroke, for views that react to typing itself rather than to the text (fading scene tags).
    let typing = PassthroughSubject<Void, Never>()
    /// `knownToDiffer` skips comparing with the last stats, for new text (comparing two versions of a novel is slow).
    func publish(_ stats: DocumentStats, knownToDiffer: Bool = false) {
        guard knownToDiffer || self.stats != stats else { return }
        var stats = stats
        stats.revision = (self.stats?.revision ?? 0) + 1
        self.stats = stats
    }
    /// `text` for views that only read it, compared by revision rather than character by character.
    func liveText(_ text: String) -> LiveText { LiveText(text: text, revision: stats?.revision ?? 0) }
    /// Hands any typing the editor is still holding to SwiftUI now. Call before reading or replacing the document's text.
    func flushText() {
        (editor?.delegate as? NativeEditor.Coordinator)?.flush()
    }
    /// The status bar's word count for `text`: the editor's, when it describes this text, or a fresh count.
    func words(in text: String) -> Int {
        if let stats, stats.text == text { return stats.words }
        return Prose.wordCount(text)
    }
    /// Prose suggestions in `text`, from the editor when it can say.
    func cuts(in text: String, words: String) -> Int {
        if let stats, let cuts = stats.cuts, stats.text == text { return cuts }
        return Prose.suggestions(in: text, words: words).count
    }
    func reportSelection(in editor: WritingTextView) {
        let range = editor.selectedRange()
        let count = range.length > 0 && range.length < 400_000 ? Prose.wordCount((editor.string as NSString).substring(with: range)) : 0
        DispatchQueue.main.async { [weak self] in
            if self?.selectionWords != count { self?.selectionWords = count }
        }
    }
    func format(_ action: Selector) {
        guard let editor else { return }
        editor.window?.makeFirstResponder(editor)
        NSApp.sendAction(action, to: editor, from: nil)
    }
}
