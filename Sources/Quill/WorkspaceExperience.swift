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

@MainActor final class QuillAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        if NSDocumentController.shared.documents.isEmpty {
            NSDocumentController.shared.newDocument(nil)
        }
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        NSDocumentController.shared.newDocument(nil)
        return true
    }
}

/// All primary-document changes pass through one close/save decision, whether
/// they originate in the writing desk or the File menu.
@MainActor
final class SingleDocumentCoordinator: NSObject {
    static let shared = SingleDocumentCoordinator()
    private var operation: SingleDocumentOperation?

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
        begin(source: source) { [weak self] in self?.open(target, completion: completion) }
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

    private func begin(source: NSDocument, action: @escaping () -> Void) {
        operation = SingleDocumentOperation(source: source) { [weak self] shouldClose in
            self?.operation = nil
            if shouldClose { action() }
        }
        operation?.start()
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
    private let finish: (Bool) -> Void

    init(source: NSDocument, finish: @escaping (Bool) -> Void) {
        self.source = source
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
        source.close()
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

/// The toolbar is available at the top edge without occupying the writing page.
struct ToolbarHoverTracker: NSViewRepresentable {
    func makeNSView(context: Context) -> ToolbarHoverView { ToolbarHoverView() }
    func updateNSView(_ view: ToolbarHoverView, context: Context) {}
}

final class ToolbarHoverView: NSView {
    private weak var trackedWindow: NSWindow?
    private var monitor: Any?
    private var hideWork: DispatchWorkItem?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window !== trackedWindow else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        trackedWindow = window
        guard let window else { return }
        window.tabbingMode = .disallowed
        DispatchQueue.main.async { [weak window] in window?.toolbar?.isVisible = false }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.updateToolbar(for: event)
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

    private func updateToolbar(for event: NSEvent) {
        guard let window = trackedWindow, event.window === window else { return }
        let top = window.contentLayoutRect.maxY
        if event.locationInWindow.y >= top - 18 {
            hideWork?.cancel()
            window.toolbar?.isVisible = true
        } else if window.toolbar?.isVisible == true, event.locationInWindow.y < top - 72 {
            hideWork?.cancel()
            let work = DispatchWorkItem { [weak window] in window?.toolbar?.isVisible = false }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
        }
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
    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Toggle("Show Writing Desk", isOn: $sidebar).keyboardShortcut("s", modifiers: [.command, .control])
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
