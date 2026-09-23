import Combine
import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

// Character, location, and world-note files can float over the page as cards while you write.
// A card is only a view of an ordinary Markdown file: nothing is stored anywhere else, and editing
// the file (here or in another editor) updates the card.

enum CardCorner: CaseIterable, Sendable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing
    var alignment: Alignment {
        switch self {
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }
    /// The corner nearest to where a card was dropped.
    static func nearest(to point: CGPoint, in size: CGSize) -> CardCorner {
        switch (point.x < size.width / 2, point.y < size.height / 2) {
        case (true, true): return .topLeading
        case (false, true): return .topTrailing
        case (true, false): return .bottomLeading
        case (false, false): return .bottomTrailing
        }
    }
}

struct OpenCard: Identifiable, Equatable {
    let url: URL
    var corner: CardCorner = .topTrailing
    /// Pinned cards stay open. Unpinned ones shrink to a small tab and open when the pointer rests on them.
    var pinned = true
    /// A size chosen by dragging the card's corner; nil lets the card size itself.
    var size: CGSize? = nil
    var id: URL { url }
}

/// A card's color as a SwiftUI color: one of the named colors, or a hex value.
func cardSwiftUIColor(_ raw: String?) -> Color? {
    guard let raw else { return nil }
    if let named = MarkColor(rawValue: raw) { return named.color }
    return NSColor(quillHex: raw).map(Color.init(nsColor:))
}

enum CardImage {
    static func cgThumbnail(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel, kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// A modest-size version of a picture, so a large photo never slows the page down.
    static func thumbnail(_ url: URL, maxPixel: Int = 480) -> NSImage? {
        cgThumbnail(url, maxPixel: maxPixel).map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    }

    /// The picture as a card shows it: the chosen crop, at enough resolution to stay sharp on a large card.
    static func portrait(_ url: URL, crop: CropRect?) -> NSImage? {
        guard let crop else { return thumbnail(url, maxPixel: 640) }
        guard let full = cgThumbnail(url, maxPixel: 1600) else { return nil }
        let w = Double(full.width), h = Double(full.height)
        let area = CGRect(x: crop.x * w, y: crop.y * h, width: crop.width * w, height: crop.height * h).integral
        guard let cut = full.cropping(to: area) else { return NSImage(cgImage: full, size: NSSize(width: full.width, height: full.height)) }
        return NSImage(cgImage: cut, size: NSSize(width: cut.width, height: cut.height))
    }
}

enum CardStore {
    /// Sets one front-matter field in a file on disk, coordinated so cloud sync and other apps stay in step.
    static func setField(_ key: String, to value: String, in url: URL) throws {
        var coordinationError: NSError?
        var failure: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], writingItemAt: url, options: .forMerging, error: &coordinationError) { reader, writer in
            do {
                let text = try String(contentsOf: reader, encoding: .utf8)
                try FrontMatter.setting(key, to: value, in: text).write(to: writer, atomically: true, encoding: .utf8)
            } catch { failure = error }
        }
        if let error = coordinationError ?? failure { throw error }
    }
}

@MainActor
final class CardModel: ObservableObject {
    let url: URL
    let projectRoot: URL
    @Published private(set) var info: CardInfo?
    @Published private(set) var image: NSImage?
    @Published private(set) var missing = false
    private var lastText: String?
    private var lastModified: Date?

    init(url: URL, projectRoot: URL) {
        self.url = url
        self.projectRoot = projectRoot
    }

    /// Re-reads the file (or uses the live text when it is the open document) and rebuilds the card if anything changed.
    func refresh(liveText: String?) {
        let text: String
        if let liveText {
            text = liveText
            missing = false
        } else {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if modified != nil, modified == lastModified, image != nil || info?.imageRef == nil { return }
            guard let read = try? String(contentsOf: url, encoding: .utf8) else { missing = true; return }
            lastModified = modified
            text = read
            missing = false
        }
        let parsed = CardParsing.info(for: url, text: text, projectRoot: projectRoot, fallback: .lore)
        if text != lastText || (parsed?.imageRef != nil && image == nil) {
            lastText = text
            if let ref = parsed?.imageRef, let file = CardParsing.resolveImage(ref, card: url, projectRoot: projectRoot) {
                image = CardImage.portrait(file, crop: parsed?.imageCrop)
            } else { image = nil }
            info = parsed
        }
    }
}

/// The formatted body of a card, using the same reading style as the rest of the app.
private struct CardBodyText: NSViewRepresentable {
    let markdown: String
    let family: String
    var size: Double = 12.5
    final class Coordinator { var size = 0.0 }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let text = NSTextView()
        text.isEditable = false; text.isSelectable = true; text.drawsBackground = false
        text.isVerticallyResizable = true; text.autoresizingMask = [.width]
        text.textContainerInset = NSSize(width: 0, height: 2)
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        let rendered = MarkdownReading.render(markdown, family: family, size: size, spacing: 0.22)
        if text.attributedString().string != rendered.string || context.coordinator.size != size {
            text.textStorage?.setAttributedString(rendered)
            context.coordinator.size = size
        }
    }
}

struct CardView: View {
    @Binding var card: OpenCard
    let liveText: String?
    let onClose: () -> Void
    let onEditBeside: () -> Void
    let onOpenInEditor: () -> Void
    let onSetField: (String, String, URL) -> Void
    let onProblem: (String) -> Void
    let dragChanged: (DragGesture.Value) -> Void
    let dragEnded: (DragGesture.Value) -> Void
    let dockSize: CGSize
    var dimWhenIdle = false
    @StateObject private var model: CardModel
    @State private var measured = CGSize(width: 276, height: 200)
    @State private var resizeStart: CGSize?
    @State private var cropRequest: CropRequest?
    @State private var hovering = false
    @State private var collapseTask: Task<Void, Never>?
    @State private var dropTargeted = false
    @AppStorage("fontFamily") private var family = "Charter"
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    init(card: Binding<OpenCard>, writingRoot: URL?, liveText: String?, onClose: @escaping () -> Void, onEditBeside: @escaping () -> Void,
         onOpenInEditor: @escaping () -> Void, onSetField: @escaping (String, String, URL) -> Void, onProblem: @escaping (String) -> Void,
         dragChanged: @escaping (DragGesture.Value) -> Void, dragEnded: @escaping (DragGesture.Value) -> Void, dockSize: CGSize, dimWhenIdle: Bool = false) {
        _card = card
        self.liveText = liveText
        self.onClose = onClose; self.onEditBeside = onEditBeside; self.onOpenInEditor = onOpenInEditor
        self.onSetField = onSetField; self.onProblem = onProblem
        self.dragChanged = dragChanged; self.dragEnded = dragEnded; self.dockSize = dockSize; self.dimWhenIdle = dimWhenIdle
        let url = card.wrappedValue.url
        let root = writingRoot.flatMap { FictionProject.projectRoot(containing: url, within: $0) } ?? url.deletingLastPathComponent()
        _model = StateObject(wrappedValue: CardModel(url: url, projectRoot: root))
    }

    private var expanded: Bool { card.pinned || hovering }
    private var kind: CardKind { model.info?.kind ?? .lore }
    private var title: String { model.info?.title ?? card.url.deletingPathExtension().lastPathComponent }
    private var tint: Color? { cardSwiftUIColor(model.info?.color) }

    var body: some View {
        Group { if expanded { full } else { tab } }
            .onHover(perform: hover)
            .onAppear { model.refresh(liveText: liveText) }
            .onChange(of: liveText) { _, text in model.refresh(liveText: text) }
            .onReceive(poll) { _ in if liveText == nil { model.refresh(liveText: nil) } }
            .dropDestination(for: URL.self) { urls, _ in
                guard let picture = urls.first(where: CardParsing.isImage) else { return false }
                tagImage(picture)
                return true
            } isTargeted: { dropTargeted = $0 }
            .animation(.smooth(duration: 0.22), value: expanded)
            .sheet(item: $cropRequest) { request in
                CropSheet(request: request, title: title, onDone: { finishCrop(request, $0) }, onCancel: { cropRequest = nil })
            }
    }

    private func hover(_ inside: Bool) {
        collapseTask?.cancel()
        if inside { hovering = true; return }
        collapseTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            if !Task.isCancelled { hovering = false }
        }
    }

    // MARK: Pieces

    private static let baseWidth: CGFloat = 276
    private var width: CGFloat { card.size?.width ?? Self.baseWidth }
    /// Everything inside grows and shrinks with the card's width.
    private var scale: CGFloat { min(1.9, max(0.8, width / Self.baseWidth)) }

    private var full: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let tags = model.info?.tags, !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag).font(.system(size: 10.5 * scale)).padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.14), in: Capsule())
                        }
                    }
                }
            }
            if model.missing {
                Text("This file can’t be found. It may have been moved or renamed.").font(.caption).foregroundStyle(.secondary)
            } else if let body = model.info?.body, !body.isEmpty {
                Divider()
                CardBodyText(markdown: body, family: family, size: Double(12.5 * scale))
                    .frame(height: card.size == nil ? bodyHeight(for: body) : nil)
                    .frame(maxHeight: card.size == nil ? nil : .infinity)
            } else if card.size != nil { Spacer(minLength: 0) }
        }
        .padding(14).frame(width: width, height: card.size?.height)
        .background(GeometryReader { proxy in
            Color.clear.onAppear { measured = proxy.size }.onChange(of: proxy.size) { _, new in measured = new }
        })
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(dropTargeted ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: dropTargeted ? 2 : 0.7))
        .overlay(alignment: .top) { if let tint { Capsule().fill(tint).frame(width: 46, height: 4).padding(.top, 5) } }
        .overlay(alignment: gripAlignment) { resizeGrip }
        .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
    }

    private func bodyHeight(for text: String) -> CGFloat {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).reduce(0) { $0 + max(1, $1.count / 36 + 1) }
        return min(230, max(56, CGFloat(lines) * 19))
    }

    // MARK: Resizing

    private var anchoredTrailing: Bool { card.corner == .topTrailing || card.corner == .bottomTrailing }
    private var anchoredTop: Bool { card.corner == .topLeading || card.corner == .topTrailing }
    /// The grip sits on the corner farthest from the one the card is anchored to, so dragging it outward grows the card.
    private var gripAlignment: Alignment {
        switch card.corner {
        case .topTrailing: return .bottomLeading
        case .topLeading: return .bottomTrailing
        case .bottomTrailing: return .topLeading
        case .bottomLeading: return .topTrailing
        }
    }

    private var resizeGrip: some View {
        let diagonalDown = gripAlignment == .bottomTrailing || gripAlignment == .topLeading
        return Image(systemName: "line.diagonal")
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            .scaleEffect(x: diagonalDown ? 1 : -1, y: 1)
            .frame(width: 22, height: 22).padding(3).contentShape(Rectangle())
            .onHover { inside in if inside { NSCursor.crosshair.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { drag in
                    let start = resizeStart ?? card.size ?? measured
                    resizeStart = start
                    let proposed = CGSize(width: start.width + (anchoredTrailing ? -1 : 1) * drag.translation.width,
                                          height: start.height + (anchoredTop ? 1 : -1) * drag.translation.height)
                    card.size = CGSize(width: min(max(220, proposed.width), max(220, dockSize.width - 32)),
                                       height: min(max(150, proposed.height), max(150, dockSize.height - 90)))
                }
                .onEnded { _ in resizeStart = nil })
            .onTapGesture(count: 2) { withAnimation(.smooth) { card.size = nil } }
            .help("Drag to resize this card. Double-click to reset its size.")
            .accessibilityLabel("Resize card")
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            portrait(width: 64 * scale, height: 80 * scale)
            VStack(alignment: .leading, spacing: 3) {
                Label(kind.title.uppercased(), systemImage: kind.symbol).labelStyle(.titleAndIcon)
                    .font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundStyle(tint ?? .secondary)
                Text(title).font(.custom(family, size: 17 * scale).weight(.semibold)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                if let subtitle = model.info?.subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                iconButton(card.pinned ? "pin.fill" : "pin", help: card.pinned ? "Unpin: shrink to a tab when you move away" : "Pin: keep this card open") { card.pinned.toggle() }
                Menu {
                    Button("Edit Beside Your Draft", action: onEditBeside)
                    Button("Open in the Editor", action: onOpenInEditor)
                    Divider()
                    Menu("Color") {
                        ForEach(MarkColor.allCases, id: \.self) { color in
                            Button { onSetField("color", color.rawValue, card.url) } label: {
                                Label { Text(color.name + (model.info?.color == color.rawValue ? " ✓" : "")) } icon: { Image(nsImage: color.swatch) }
                            }
                        }
                        if model.info?.color != nil { Divider(); Button("No Color") { onSetField("color", "", card.url) } }
                    }
                    Button(model.info?.imageRef == nil ? "Add Image…" : "Change Image…", action: chooseImage)
                    if model.info?.imageRef != nil {
                        Button("Adjust Crop…", action: adjustCrop)
                        Button("Remove Image") { onSetField("image", "", card.url); onSetField("image-crop", "", card.url) }
                    }
                    Divider()
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([card.url]) }
                } label: { Image(systemName: "ellipsis").font(.system(size: 11)).frame(width: 20, height: 18) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More")
                iconButton("xmark", help: "Close this card", action: onClose)
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("cardDock")).onChanged(dragChanged).onEnded(dragEnded))
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 11)).frame(width: 20, height: 18).foregroundStyle(.secondary) }
            .buttonStyle(.plain).help(help).accessibilityLabel(help)
    }

    private func portrait(width: CGFloat, height: CGFloat, round: Bool = false) -> some View {
        Button(action: chooseImage) {
            ZStack {
                if let image = model.image {
                    Image(nsImage: image).resizable().scaledToFill().frame(width: width, height: height)
                } else {
                    Rectangle().fill(Color.accentColor.opacity(0.12))
                    VStack(spacing: 3) {
                        Image(systemName: kind.symbol).font(.system(size: height > 40 ? 22 : 12))
                        if height > 40 { Text("Add image").font(.system(size: 9)) }
                    }.foregroundStyle(Color.accentColor.opacity(0.8))
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: round ? height / 2 : 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: round ? height / 2 : 9, style: .continuous).strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.6))
        }
        .buttonStyle(.plain).help(model.info?.imageRef == nil ? "Add an image to this card" : "Change this card’s image")
    }

    /// The collapsed form: just a face and a name, tucked into the corner until you need it.
    private var tab: some View {
        HStack(spacing: 8) {
            portrait(width: 28, height: 28, round: true)
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .padding(.leading, 6).padding(.trailing, 12).padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(tint?.opacity(0.85) ?? Color.primary.opacity(0.12), lineWidth: tint == nil ? 0.7 : 1.4))
        .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
        // In focus mode, cards you aren't using step back so the page is the brightest thing.
        .opacity(dimWhenIdle ? 0.32 : 1)
        .animation(.easeInOut(duration: 0.3), value: dimWhenIdle)
        .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("cardDock")).onChanged(dragChanged).onEnded(dragEnded))
    }

    // MARK: Images

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.title = "Choose an image for \(title)"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            tagImage(url)
        }
    }

    /// A new picture is framed before it is added, so cancelling leaves nothing behind.
    private func tagImage(_ source: URL) { beginCrop(source: source, isNew: true, initial: nil) }

    private func adjustCrop() {
        guard let ref = model.info?.imageRef, let file = CardParsing.resolveImage(ref, card: card.url, projectRoot: model.projectRoot) else { return }
        beginCrop(source: file, isNew: false, initial: model.info?.imageCrop)
    }

    private func beginCrop(source: URL, isNew: Bool, initial: CropRect?) {
        guard let image = CardImage.thumbnail(source, maxPixel: 1600) else {
            onProblem("Sable couldn’t read “\(source.lastPathComponent)” as an image.")
            return
        }
        cropRequest = CropRequest(source: source, isNew: isNew, image: image, initial: initial)
    }

    private func finishCrop(_ request: CropRequest, _ crop: CropRect?) {
        cropRequest = nil
        do {
            if request.isNew { onSetField("image", try CardParsing.importImage(request.source, into: model.projectRoot), card.url) }
            onSetField("image-crop", crop?.formatted ?? "", card.url)
        } catch { onProblem(error.localizedDescription) }
    }
}

struct CropRequest: Identifiable {
    let id = UUID()
    let source: URL
    let isNew: Bool
    let image: NSImage
    let initial: CropRect?
}

/// Frame the part of a picture a card shows: drag to reposition, slide to zoom.
struct CropSheet: View {
    let request: CropRequest
    let title: String
    let onDone: (CropRect?) -> Void
    let onCancel: () -> Void
    @State private var zoom = 1.0
    @State private var center = CGPoint(x: 0.5, y: 0.5)
    @State private var dragStart: CGPoint?
    private let window = CGSize(width: 240, height: 300)

    private var crop: CropRect { CropRect.make(imageSize: request.image.size, zoom: zoom, centerX: center.x, centerY: center.y) }

    var body: some View {
        VStack(spacing: 14) {
            Text("Frame \(title)’s portrait").font(.headline)
            cropWindow
            HStack(spacing: 8) {
                Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
                Slider(value: $zoom, in: 1...CropRect.maxZoom).accessibilityLabel("Zoom")
                Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
            }.frame(width: window.width)
            Text("Drag to reposition. The card shows what’s inside the frame.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack {
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Whole Picture") { onDone(nil) }
                Button("Use This Frame") { onDone(crop) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22).frame(width: 300)
        .onAppear {
            if let initial = request.initial {
                zoom = initial.zoom(imageSize: request.image.size)
                center = CGPoint(x: initial.centerX, y: initial.centerY)
            }
        }
    }

    private var cropWindow: some View {
        let r = crop
        return ZStack(alignment: .topLeading) {
            Image(nsImage: request.image).resizable()
                .frame(width: window.width / r.width, height: window.height / r.height)
                .offset(x: -r.x * window.width / r.width, y: -r.y * window.height / r.height)
        }
        .frame(width: window.width, height: window.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.3), lineWidth: 1))
        .contentShape(Rectangle())
        .gesture(DragGesture()
            .onChanged { drag in
                let start = dragStart ?? center
                dragStart = start
                let moved = CropRect.make(imageSize: request.image.size, zoom: zoom,
                                          centerX: start.x - drag.translation.width / window.width * r.width,
                                          centerY: start.y - drag.translation.height / window.height * r.height)
                center = CGPoint(x: moved.centerX, y: moved.centerY)
            }
            .onEnded { _ in dragStart = nil })
        .accessibilityLabel("Portrait frame. Drag to reposition.")
    }
}

/// Lays out every open card in its corner, lets you drag one anywhere, and snaps it to the nearest corner when you let go.
struct CardDock: View {
    @Binding var cards: [OpenCard]
    /// A corner where the scene-tag strip sits, so cards stack clear of it.
    var reservedCorner: CardCorner? = nil
    /// Dims collapsed card tabs (used in paragraph focus).
    var dimIdleCards = false
    let writingRoot: URL?
    let activeURL: URL?
    let liveText: String
    let onEditBeside: (URL) -> Void
    let onOpenInEditor: (URL) -> Void
    let onSetField: (String, String, URL) -> Void
    let onProblem: (String) -> Void
    @State private var draggingID: URL?
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(CardCorner.allCases, id: \.self) { corner in
                    VStack(spacing: 10) {
                        ForEach($cards) { $card in
                            if card.corner == corner { cardView($card, size: proxy.size) }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
                    .padding(insets(for: corner))
                }
            }
            .coordinateSpace(name: "cardDock")
        }
    }

    private func insets(for corner: CardCorner) -> EdgeInsets {
        let top = corner == .topLeading || corner == .topTrailing
        let extra: CGFloat = corner == reservedCorner ? 64 : 0
        return EdgeInsets(top: (top ? 56 : 14) + (top ? extra : 0), leading: 14, bottom: 14 + (top ? 0 : extra), trailing: 14)
    }

    private func cardView(_ card: Binding<OpenCard>, size: CGSize) -> some View {
        let url = card.wrappedValue.url
        let isActive = activeURL?.standardizedFileURL == url.standardizedFileURL
        return CardView(
            card: card, writingRoot: writingRoot, liveText: isActive ? liveText : nil,
            onClose: { withAnimation(.smooth) { cards.removeAll { $0.url == url } } },
            onEditBeside: { onEditBeside(url) }, onOpenInEditor: { onOpenInEditor(url) },
            onSetField: onSetField, onProblem: onProblem,
            dragChanged: { value in draggingID = url; dragOffset = value.translation },
            dragEnded: { value in
                let corner = CardCorner.nearest(to: value.location, in: size)
                withAnimation(.smooth(duration: 0.3)) {
                    card.wrappedValue.corner = corner
                    draggingID = nil
                    dragOffset = .zero
                }
            }, dockSize: size, dimWhenIdle: dimIdleCards)
        .offset(draggingID == url ? dragOffset : .zero)
        .zIndex(draggingID == url ? 5 : 0)
        .transition(.scale(scale: 0.92).combined(with: .opacity))
    }
}

// MARK: - Scene tags

/// Left-to-right layout that wraps to a new line when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > limit { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

extension CardKind {
    var tagSymbol: String {
        switch self { case .location: return "mappin"; case .character: return "person.fill"; case .lore: return "book.closed.fill" }
    }
    var folderHint: String {
        switch self { case .location: return "Locations"; case .character: return "Characters"; case .lore: return "World" }
    }
}

@MainActor
final class SceneIndexModel: ObservableObject {
    @Published private(set) var cards: [IndexedCard] = []
    /// The names in those cards, ready for the editor to highlight.
    @Published private(set) var highlighter = NameHighlighter.empty
    private var task: Task<Void, Never>?

    func reload(project: URL?) {
        guard let project else {
            if !cards.isEmpty { cards = []; highlighter = .empty }
            return
        }
        let previous = cards
        task?.cancel()
        task = Task {
            let result = await Task.detached(priority: .utility) { () -> ([IndexedCard], NameHighlighter?) in
                let loaded = CardIndex.load(project: project, reusing: previous)
                return (loaded, loaded == previous ? nil : NameHighlighter.build(from: loaded))
            }.value
            guard !Task.isCancelled, let built = result.1 else { return }
            cards = result.0
            highlighter = built
        }
    }
}

/// A quiet strip of the people and places in the chapter you're writing. Chips open the card, so you can check a
/// detail without leaving the page. It fades almost away while you type and returns when you pause.
struct SceneTagsLayer: View {
    @EnvironmentObject private var browser: FolderBrowser
    @AppStorage("sceneTagsPlacement") private var placement = "bottom"
    @AppStorage("sceneTagsFade") private var fadeWhileTyping = true
    @AppStorage("sceneTagsColor") private var colorCoded = true
    let activeURL: URL?
    let liveText: String
    /// Fires on each keystroke; the text itself reaches `liveText` only after a pause in typing.
    let typing: PassthroughSubject<Void, Never>
    let editSignal: Int
    /// Paragraph focus is on: the strip steps back until you point at it.
    var focusDim = false
    let openCard: (URL) -> Void
    let setTags: (CardKind, [String]) -> Void
    let createCard: (CardKind, String) -> Void
    @ObservedObject var index: SceneIndexModel
    @State private var quiet = false
    @State private var quietTask: Task<Void, Never>?
    @State private var editing = false
    @State private var pointerOver = false
    private let poll = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    /// Chapters always offer the strip; other project files only when they already carry tags.
    private var tags: SceneTags? {
        guard placement != "off", let url = activeURL, let projectURL = browser.projectURL, FolderMove.isInside(url, of: projectURL),
              ["md", "markdown"].contains(url.pathExtension.lowercased()) else { return nil }
        let parsed = SceneTags.parse(String(liveText.prefix(4000)))   // tags live at the top of the file
        return parsed.isEmpty && !browser.isChapter(url) ? nil : parsed
    }
    private var alignment: Alignment {
        switch placement {
        case "topLeading": return .topLeading
        case "topTrailing": return .topTrailing
        case "bottomLeading": return .bottomLeading
        case "bottomTrailing": return .bottomTrailing
        default: return .bottom
        }
    }
    private var insets: EdgeInsets {
        switch placement {
        case "topLeading", "topTrailing": return EdgeInsets(top: 56, leading: 14, bottom: 0, trailing: 14)
        case "bottomLeading", "bottomTrailing": return EdgeInsets(top: 0, leading: 14, bottom: 14, trailing: 14)
        default: return EdgeInsets(top: 0, leading: 60, bottom: 12, trailing: 60)
        }
    }

    var body: some View {
        ZStack(alignment: alignment) {
            Color.clear.allowsHitTesting(false)
            if let tags { bar(tags).padding(insets) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { index.reload(project: browser.projectURL) }
        .onChange(of: browser.projectURL) { _, project in index.reload(project: project) }
        .onReceive(poll) { _ in if browser.projectURL != nil { index.reload(project: browser.projectURL) } }
        .onReceive(typing) { _ in noteTyping() }
        .onChange(of: editSignal) { _, _ in if tags != nil { editing = true } }
    }

    private func noteTyping() {
        guard fadeWhileTyping else { return }
        quiet = true
        quietTask?.cancel()
        quietTask = Task {
            try? await Task.sleep(for: .milliseconds(2200))
            if !Task.isCancelled { quiet = false }
        }
    }

    private func bar(_ tags: SceneTags) -> some View {
        let chips = SceneTags.kinds.flatMap { kind in tags.names(for: kind).map { (kind: kind, name: $0) } }
        let corner = placement != "bottom"
        return FlowLayout(spacing: 5) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in tagChip(kind: chip.kind, name: chip.name) }
            editButton(empty: chips.isEmpty)
        }
        .frame(maxWidth: corner ? 270 : 640, alignment: corner ? .leading : .center)
        .opacity(quiet ? 0.12 : (focusDim && !pointerOver ? 0.35 : 1))
        .animation(.easeInOut(duration: 0.5), value: quiet)
        .animation(.easeInOut(duration: 0.3), value: focusDim)
        .onHover { pointerOver = $0 }
        .contextMenu { placementMenu }
    }

    /// The card's own color, or the color given to its file in the desk.
    private func color(of card: IndexedCard?) -> Color? {
        guard colorCoded, let card else { return nil }
        return cardSwiftUIColor(card.color) ?? browser.color(of: card.url)?.color
    }

    private func tagChip(kind: CardKind, name: String) -> some View {
        let card = CardIndex.match(name, kind: kind, in: index.cards)
        let tint = color(of: card)
        return Button { if let card { openCard(card.url) } else { createCard(kind, name) } } label: {
            HStack(spacing: 4) {
                Image(systemName: kind.tagSymbol).font(.system(size: 9)).foregroundStyle(tint ?? .primary)
                Text(card?.title ?? name).lineLimit(1)
            }
            .font(.system(size: 11)).padding(.horizontal, 8).padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
            .background(Capsule().fill((tint ?? .clear).opacity(0.2)))
            .overlay(Capsule().strokeBorder(tint?.opacity(0.6) ?? Color.primary.opacity(card == nil ? 0.3 : 0.14), style: StrokeStyle(lineWidth: 0.8, dash: card == nil ? [3, 2] : [])))
            .opacity(card == nil ? 0.8 : 1)
        }
        .buttonStyle(.plain)
        .help(card.map { $0.subtitle.isEmpty ? "Show \($0.title)’s card" : "\($0.title) — \($0.subtitle)" } ?? "There’s no card called “\(name)” yet. Click to create one.")
    }

    private func editButton(empty: Bool) -> some View {
        Button { editing.toggle() } label: {
            HStack(spacing: 4) {
                Image(systemName: empty ? "tag" : "plus").font(.system(size: 9, weight: .semibold))
                if empty { Text("Tag this scene").font(.system(size: 11)) }
            }
            .padding(.horizontal, empty ? 8 : 6).padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .foregroundStyle(.secondary).opacity(empty ? 0.6 : 0.85)
        }
        .buttonStyle(.plain).help("Choose the location and characters in this scene")
        .popover(isPresented: $editing, arrowEdge: placement.hasPrefix("top") ? .bottom : .top) { editor }
    }

    @ViewBuilder
    private var editor: some View {
        SceneTagEditor(tags: SceneTags.parse(String(liveText.prefix(4000))), cards: index.cards, colorFor: { color(of: $0) },
                       toggle: { kind, card in setTags(kind, SceneTags.parse(String(liveText.prefix(4000))).toggling(card, kind: kind)) },
                       remove: { kind, name in setTags(kind, SceneTags.parse(String(liveText.prefix(4000))).removing(name, kind: kind)) })
    }

    @ViewBuilder
    private var placementMenu: some View {
        Menu("Move Scene Tags") {
            ForEach([("bottom", "Bottom"), ("topLeading", "Top Left"), ("topTrailing", "Top Right"),
                     ("bottomLeading", "Bottom Left"), ("bottomTrailing", "Bottom Right")], id: \.0) { value, title in
                Button(title + (placement == value ? " ✓" : "")) { placement = value }
            }
        }
        Toggle("Fade While Typing", isOn: $fadeWhileTyping)
        Divider()
        Button("Hide Scene Tags") { placement = "off" }
    }
}

/// Pick the location, characters, and world notes for a scene from the project's cards.
struct SceneTagEditor: View {
    let tags: SceneTags
    let cards: [IndexedCard]
    var colorFor: (IndexedCard) -> Color? = { _ in nil }
    let toggle: (CardKind, IndexedCard) -> Void
    let remove: (CardKind, String) -> Void
    @State private var filter = ""

    private func isOn(_ card: IndexedCard, _ kind: CardKind) -> Bool {
        let mine = Set(card.names.map(CardIndex.normalize))
        return tags.names(for: kind).contains { mine.contains(CardIndex.normalize($0)) }
    }
    /// Tags that point at nothing yet, so they can still be seen and removed.
    private func orphans(_ kind: CardKind) -> [String] {
        tags.names(for: kind).filter { CardIndex.match($0, kind: kind, in: cards) == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tag this scene").font(.headline)
            Text("Who and what appears here. Tags are saved at the top of this chapter’s file, and clicking one while you write opens its card.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("Filter", text: $filter).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(SceneTags.kinds, id: \.self) { kind in section(kind) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 300)
        }.padding(16).frame(width: 310)
    }

    private func section(_ kind: CardKind) -> some View {
        let shown = cards.filter { $0.kind == kind && (filter.isEmpty || $0.title.localizedCaseInsensitiveContains(filter) || $0.subtitle.localizedCaseInsensitiveContains(filter)) }
        return VStack(alignment: .leading, spacing: 4) {
            Label(kind.pickerTitle.uppercased(), systemImage: kind.tagSymbol)
                .font(.system(size: 9.5, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
            ForEach(orphans(kind), id: \.self) { name in
                Button { remove(kind, name) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                        Text(name).lineLimit(1)
                        Text("no card yet").font(.caption).foregroundStyle(.tertiary)
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            ForEach(shown) { card in
                let on = isOn(card, kind)
                Button { toggle(kind, card) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Color.accentColor : Color.secondary)
                        Text(card.title).lineLimit(1)
                        if let dot = colorFor(card) { Circle().fill(dot).frame(width: 8, height: 8) }
                        if !card.subtitle.isEmpty { Text(card.subtitle).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if shown.isEmpty && orphans(kind).isEmpty {
                Text(cards.contains { $0.kind == kind } ? "Nothing matches." : "None yet. Use the + on the \(kind.folderHint) folder to add one.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}
