import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WritingTheme: Identifiable {
    let id: String
    let name: String
    let paper: String
    let ink: String
    let dark: Bool
    var background: NSColor { NSColor(quillHex: paper)! }
    var foreground: NSColor { NSColor(quillHex: ink)! }
    static let all = [
        WritingTheme(id: "graphite", name: "Graphite", paper: "242424", ink: "E0DDD7", dark: true),
        WritingTheme(id: "midnight", name: "Midnight", paper: "131820", ink: "D6DEE8", dark: true),
        WritingTheme(id: "forest", name: "Forest", paper: "1D2925", ink: "DCE4D9", dark: true),
        WritingTheme(id: "parchment", name: "Parchment", paper: "F3EBDD", ink: "40382E", dark: false),
        WritingTheme(id: "paper", name: "Paper", paper: "FAFAF8", ink: "30302E", dark: false)
    ]
    static func named(_ id: String) -> WritingTheme { all.first { $0.id == id } ?? all[0] }
}

@MainActor enum WritingZoom {
    static var value: Double { UserDefaults.standard.object(forKey: "editorZoom") as? Double ?? 1 }
    static func set(_ value: Double) { UserDefaults.standard.set(min(2, max(0.65, value)), forKey: "editorZoom") }
    static func step(_ delta: Double) { set(value + delta) }
}

final class WritingScrollView: NSScrollView {
    var sidebarGesture: (() -> Void)?
    private var horizontalGestureDistance: CGFloat = 0
    private var handledHorizontalGesture = false

    override func magnify(with event: NSEvent) {
        guard UserDefaults.standard.object(forKey: "pinchToZoom") as? Bool ?? true else { return }
        WritingZoom.set(WritingZoom.value * (1 + event.magnification))
    }

    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began {
            horizontalGestureDistance = 0
            handledHorizontalGesture = false
        }
        guard event.hasPreciseScrollingDeltas,
              abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
              abs(event.scrollingDeltaX) > 0 else {
            super.scrollWheel(with: event)
            return
        }
        if !handledHorizontalGesture {
            horizontalGestureDistance += event.scrollingDeltaX
        }
        if !handledHorizontalGesture && abs(horizontalGestureDistance) > 42 {
            handledHorizontalGesture = true
            sidebarGesture?()
        }
        if event.phase == .ended || event.momentumPhase == .ended {
            horizontalGestureDistance = 0
            handledHorizontalGesture = false
        }
    }
}

/// What the app does when it starts with nothing open: it should never greet the writer with a
/// file-picker. It reopens the last document, or starts a blank one.
@MainActor enum LaunchBehavior {
    static let lastDocumentKey = "lastDocumentPath"

    /// AppKit shows an Open panel instead of a blank document unless told otherwise.
    /// Must run before the document controller decides, so the App calls it in `init`.
    static func register() {
        UserDefaults.standard.register(defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false])
    }

    static func remember(_ url: URL?) {
        guard let url, url.isFileURL else { return }
        if UserDefaults.standard.string(forKey: lastDocumentKey) != url.path {
            UserDefaults.standard.set(url.path, forKey: lastDocumentKey)
        }
    }

    static func openStartupDocument() {
        let controller = NSDocumentController.shared
        guard let path = UserDefaults.standard.string(forKey: lastDocumentKey),
              FileManager.default.isReadableFile(atPath: path) else {
            controller.newDocument(nil)
            return
        }
        controller.openDocument(withContentsOf: URL(fileURLWithPath: path), display: true) { document, _, _ in
            if document == nil { controller.newDocument(nil) }
        }
    }
}

@MainActor final class QuillAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) { LaunchBehavior.register() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        // Give macOS a moment to restore windows itself before deciding nothing is open.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if NSDocumentController.shared.documents.isEmpty { LaunchBehavior.openStartupDocument() }
        }
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        LaunchBehavior.openStartupDocument()
        return true
    }
}

/// All primary-document changes pass through one close/save decision, whether
/// they originate in the writing desk or the File menu.
///
/// Switching files keeps the same window: the new file's text is loaded into the
/// current document, so nothing flashes closed and reopened, and full screen is
/// preserved. Only when no editor is attached does it fall back to opening a window.
@MainActor
final class SingleDocumentCoordinator: NSObject {
    static let shared = SingleDocumentCoordinator()
    private var operation: SingleDocumentOperation?
    private let editors = NSHashTable<EditorCommands>.weakObjects()

    func register(_ commands: EditorCommands) { editors.add(commands) }

    private func commands(for document: NSDocument) -> EditorCommands? {
        editors.allObjects.first { $0.editor?.window?.windowController?.document === document && $0.loadText != nil }
    }

    func switchDocument(from source: NSDocument?, to target: URL, completion: @escaping (Error?) -> Void) {
        guard let source else {
            open(target, completion: completion)
            return
        }
        if source.fileURL?.standardizedFileURL == target.standardizedFileURL {
            source.windowControllers.first?.window?.makeKeyAndOrderFront(nil)
            completion(nil)
            return
        }
        if let existing = NSDocumentController.shared.document(for: target), existing !== source {
            existing.showWindows()
            existing.windowControllers.first?.window?.makeKeyAndOrderFront(nil)
            completion(nil)
            return
        }
        if let commands = commands(for: source) {
            begin(source: source, closing: false) { [weak self] in
                self?.replace(source, with: target, using: commands, completion: completion)
            }
        } else {
            begin(source: source) { [weak self] in self?.open(target, completion: completion) }
        }
    }

    func chooseDocument() {
        let panel = NSOpenPanel()
        panel.title = "Open Markdown File"
        panel.prompt = "Open"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
            .plainText
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            let source = NSApp.keyWindow?.windowController?.document as? NSDocument
            self?.switchDocument(from: source, to: url) { error in
                if let error { NSApp.presentError(error) }
            }
        }
    }

    func newDocument() {
        guard let source = NSApp.keyWindow?.windowController?.document as? NSDocument else {
            NSDocumentController.shared.newDocument(nil)
            return
        }
        begin(source: source) {
            NSDocumentController.shared.newDocument(nil)
        }
    }

    private func begin(source: NSDocument, closing: Bool = true, action: @escaping () -> Void) {
        operation = SingleDocumentOperation(source: source, closing: closing) { [weak self] shouldContinue in
            self?.operation = nil
            if shouldContinue { action() }
        }
        operation?.start()
    }

    /// Reads the file before touching the open document, so a read failure leaves it as it was.
    private func replace(_ source: NSDocument, with target: URL, using commands: EditorCommands, completion: @escaping (Error?) -> Void) {
        let scoped = target.startAccessingSecurityScopedResource()
        defer { if scoped { target.stopAccessingSecurityScopedResource() } }
        let text: String
        do { text = try String(contentsOf: target, encoding: .utf8) }
        catch { completion(error); return }
        let modified = (try? target.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        commands.loadText?(text, target)
        source.fileURL = target
        source.fileModificationDate = modified
        source.undoManager?.removeAllActions()
        commands.editor?.undoManager?.removeAllActions()
        commands.editor?.setSelectedRange(NSRange(location: 0, length: 0))
        commands.editor?.scrollToBeginningOfDocument(nil)
        source.windowControllers.first?.synchronizeWindowTitleWithDocumentName()
        // Loading text registers as an edit; the file on disk already matches, so clear it once SwiftUI has settled.
        source.updateChangeCount(.changeCleared)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { source.updateChangeCount(.changeCleared) }
        completion(nil)
    }

    private func open(_ target: URL, completion: @escaping (Error?) -> Void) {
        let scoped = target.startAccessingSecurityScopedResource()
        NSDocumentController.shared.openDocument(withContentsOf: target, display: true) { _, _, error in
            if scoped { target.stopAccessingSecurityScopedResource() }
            completion(error)
        }
    }
}

@MainActor
private final class SingleDocumentOperation: NSObject {
    private let source: NSDocument
    private let closing: Bool
    private let finish: (Bool) -> Void

    init(source: NSDocument, closing: Bool, finish: @escaping (Bool) -> Void) {
        self.source = source
        self.closing = closing
        self.finish = finish
    }

    func start() {
        source.canClose(withDelegate: self, shouldClose: #selector(canClose(_:shouldClose:contextInfo:)), contextInfo: nil)
    }

    @objc private func canClose(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        guard shouldClose else {
            finish(false)
            return
        }
        if closing { source.close() }
        finish(true)
    }
}

// NSDocument's callback reports actual save completion, including cancellation.
@MainActor final class SaveFeedback: NSObject, ObservableObject {
    @Published var message = ""
    func save(_ document: NSDocument?) {
        guard let document else { return }
        message = "Saving…"
        document.save(withDelegate: self, didSave: #selector(didSave(_:didSave:contextInfo:)), contextInfo: nil)
    }
    @objc private func didSave(_ document: NSDocument, didSave success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        message = success ? "Saved · \(Date.now.formatted(date: .omitted, time: .shortened))" : "Save not completed"
    }
}

/// Window-level setup that SwiftUI does not expose. The toolbar itself is drawn by
/// `HoverToolbar` inside the content, so it can slide instead of popping in and out.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ConfiguratorView { ConfiguratorView() }
    func updateNSView(_ view: ConfiguratorView, context: Context) {}
}

final class ConfiguratorView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.tabbingMode = .disallowed
    }
}

enum ToolbarEdge: String, CaseIterable, Sendable {
    case top, left, right
    var title: String { rawValue.capitalized }
    var vertical: Bool { self != .top }
    var alignment: Alignment {
        switch self { case .top: return .top; case .left: return .leading; case .right: return .trailing }
    }
    /// Distance from this edge for a point in top-left-origin coordinates.
    func distance(of point: CGPoint, in size: CGSize) -> CGFloat {
        switch self { case .top: return point.y; case .left: return point.x; case .right: return size.width - point.x }
    }
    var hiddenOffset: CGSize {
        switch self { case .top: return CGSize(width: 0, height: -110); case .left: return CGSize(width: -110, height: 0); case .right: return CGSize(width: 110, height: 0) }
    }
}

/// Reports the pointer's position inside the view it backs, without taking any clicks:
/// a hot zone can be generous because it never blocks the text underneath.
struct PointerTracker: NSViewRepresentable {
    let onMove: (CGPoint?, CGSize) -> Void
    func makeNSView(context: Context) -> PointerTrackingView {
        let view = PointerTrackingView()
        view.onMove = onMove
        return view
    }
    func updateNSView(_ view: PointerTrackingView, context: Context) { view.onMove = onMove }
}

final class PointerTrackingView: NSView {
    var onMove: ((CGPoint?, CGSize) -> Void)?
    private var monitor: Any?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard let window else { return }
        window.acceptsMouseMovedEvents = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            let point = self.convert(event.locationInWindow, from: nil)
            self.onMove?(self.bounds.contains(point) ? point : nil, self.bounds.size)
            return event
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }
}

/// The writing toolbar. Anchored to the top, left, or right edge; either always shown
/// or auto-hidden, sliding in when the pointer comes within reach of its edge.
struct HoverToolbar<Content: View>: View {
    let edge: ToolbarEdge
    var enabled = true
    let autoHide: Bool
    var keepOpen = false
    let content: Content
    @State private var revealed = false
    @State private var showTask: Task<Void, Never>?
    @State private var hideTask: Task<Void, Never>?

    /// How close the pointer must come to reveal the bar, and how far it can stray before it hides.
    private let revealDistance: CGFloat = 84
    private let keepDistance: CGFloat = 128

    init(edge: ToolbarEdge, enabled: Bool = true, autoHide: Bool, keepOpen: Bool = false, @ViewBuilder content: () -> Content) {
        self.edge = edge; self.enabled = enabled; self.autoHide = autoHide; self.keepOpen = keepOpen; self.content = content()
    }

    private var shown: Bool { enabled && (!autoHide || revealed || keepOpen) }

    var body: some View {
        content
            .padding(edge.vertical ? .horizontal : .vertical, 6)
            .padding(edge.vertical ? .vertical : .horizontal, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.2), radius: 12, y: 3)
            .padding(edge == .top ? .top : (edge == .left ? .leading : .trailing), 10)
            .offset(shown ? .zero : edge.hiddenOffset)
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge.alignment)
            .background(PointerTracker(onMove: track))
            .animation(.smooth(duration: 0.32), value: shown)
            .onChange(of: autoHide) { _, _ in revealed = false }
    }

    private func track(_ point: CGPoint?, _ size: CGSize) {
        guard enabled, autoHide else { return }
        guard let point else { schedule(hide: true); return }
        let distance = edge.distance(of: point, in: size)
        if revealed {
            schedule(hide: distance > keepDistance)
        } else if distance < revealDistance && NSEvent.pressedMouseButtons == 0 {
            // A brief dwell keeps a fast flick past the edge, or a text selection, from summoning the bar.
            hideTask?.cancel()
            if showTask == nil {
                showTask = Task {
                    try? await Task.sleep(for: .milliseconds(140))
                    if !Task.isCancelled { revealed = true }
                    showTask = nil
                }
            }
        } else {
            showTask?.cancel(); showTask = nil
        }
    }

    private func schedule(hide: Bool) {
        showTask?.cancel(); showTask = nil
        hideTask?.cancel()
        guard hide else { return }
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            if !Task.isCancelled { revealed = false }
        }
    }
}

struct BarButton: View {
    let icon: String
    let label: String
    var help: String?
    var active = false
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .regular))
                .frame(width: 38, height: 34)
                .foregroundStyle(active ? Color.accentColor : Color.primary)
                .background(active ? Color.accentColor.opacity(0.16) : (hovering && enabled ? Color.primary.opacity(0.08) : .clear), in: RoundedRectangle(cornerRadius: 8))
                .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.plain).onHover { hovering = $0 }
        .help(help ?? label).accessibilityLabel(label)
    }
}

struct WritingActions {
    var reading: () -> Void
    var focus: () -> Void
    var style: () -> Void
    var sentences: () -> Void
}
struct WritingActionsKey: FocusedValueKey { typealias Value = WritingActions }
extension FocusedValues {
    var writingActions: WritingActions? {
        get { self[WritingActionsKey.self] }
        set { self[WritingActionsKey.self] = newValue }
    }
}

struct WritingCommands: Commands {
    @FocusedValue(\.writingActions) private var actions
    @AppStorage("showWritingDesk") private var sidebar = true
    @AppStorage("toolbarEdge") private var toolbarEdge = ToolbarEdge.top.rawValue
    @AppStorage("toolbarAutoHide") private var toolbarAutoHide = true
    @AppStorage("toolbarEnabled") private var toolbarEnabled = true
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Toggle("Show Writing Desk", isOn: $sidebar).keyboardShortcut("s", modifiers: [.command, .control])
            Toggle("Show Toolbar", isOn: $toolbarEnabled).keyboardShortcut("t", modifiers: [.command, .option])
            Menu("Toolbar") {
                Picker("Position", selection: $toolbarEdge) {
                    ForEach(ToolbarEdge.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }.pickerStyle(.inline)
                Toggle("Auto-Hide", isOn: $toolbarAutoHide)
            }
            Divider()
            Button("Reading Mode") { actions?.reading() }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(actions == nil)
            Button("Paragraph Focus") { actions?.focus() }.keyboardShortcut("f", modifiers: [.command, .shift]).disabled(actions == nil)
            Button("Writing Style…") { actions?.style() }.keyboardShortcut(",", modifiers: [.command, .option]).disabled(actions == nil)
            Button("Sentence Structure…") { actions?.sentences() }.keyboardShortcut("j", modifiers: [.command, .option]).disabled(actions == nil)
            Divider()
            Button("Zoom In") { WritingZoom.step(0.1) }.keyboardShortcut("=", modifiers: .command)
            Button("Zoom Out") { WritingZoom.step(-0.1) }.keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { WritingZoom.set(1) }.keyboardShortcut("0", modifiers: .command)
        }
        CommandGroup(replacing: .help) {
            Button("New Quill Guide") { Tutorial.open() }
        }
    }
}

@MainActor enum Tutorial {
    static func install(in folder: URL) throws -> URL {
        guard let source = Bundle.main.url(forResource: "New Quill Guide", withExtension: "md") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let destination = folder.appendingPathComponent("New Quill Guide.md")
        if !FileManager.default.fileExists(atPath: destination.path) {
            try Data(contentsOf: source).write(to: destination, options: .withoutOverwriting)
        }
        return destination
    }
    /// Writes a fresh copy of the guide. Replacing overwrites "New Quill Guide.md"; otherwise the copy gets a numbered name.
    static func regenerate(in folder: URL, replacing: Bool) throws -> URL {
        guard let source = Bundle.main.url(forResource: "New Quill Guide", withExtension: "md") else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var destination = folder.appendingPathComponent("New Quill Guide.md")
        if !replacing {
            var number = 2
            while FileManager.default.fileExists(atPath: destination.path) {
                destination = folder.appendingPathComponent("New Quill Guide \(number).md")
                number += 1
            }
        }
        try Data(contentsOf: source).write(to: destination, options: replacing ? .atomic : .withoutOverwriting)
        return destination
    }
    static func guideExists(in folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent("New Quill Guide.md").path)
    }
    static func open(in folder: URL? = nil) {
        do {
            let browser = FolderBrowser()
            let directory = folder ?? browser.root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("New Quill")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = try install(in: directory)
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                if let error { NSApp.presentError(error) }
            }
        } catch { NSApp.presentError(error) }
    }
}

struct WritingFolderSetup: View {
    @EnvironmentObject private var browser: FolderBrowser
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    @State private var includeGuide = true
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "folder.badge.plus").font(.largeTitle).foregroundStyle(.secondary)
            Text("A home for your writing").font(.title2.weight(.semibold))
            Text("Choose or create a folder for your Markdown files. You can still open and save documents anywhere.")
            Text("We recommend a folder in iCloud Drive, Dropbox, or OneDrive so your writing is available on your other devices. Your chosen service handles syncing.").foregroundStyle(.secondary)
            Toggle("Include the New Quill Markdown guide", isOn: $includeGuide)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Choose or Create Folder…") { choose() }.keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 440).interactiveDismissDisabled()
    }
    private func choose() {
        let panel = NSOpenPanel()
        panel.title = "Choose your writing folder"
        panel.prompt = "Use Writing Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try browser.choose(url)
                if includeGuide { _ = try Tutorial.install(in: url); browser.refresh() }
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
