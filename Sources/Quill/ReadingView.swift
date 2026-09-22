import SwiftUI
import AppKit
import QuillCore

@MainActor
enum MarkdownReading {
    /// Reading Mode draws exactly what the shared Markdown reader finds, the same blocks the exports use.
    static func render(_ source: String, family: String, size: Double, spacing: Double) -> NSAttributedString {
        let base = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size) ?? .systemFont(ofSize: size)
        let mono = NSFont.monospacedSystemFont(ofSize: size * 0.88, weight: .regular)
        let output = NSMutableAttributedString()
        func paragraphStyle(indent: CGFloat, centered: Bool) -> NSMutableParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = size * spacing
            style.paragraphSpacing = size * 0.8
            style.headIndent = indent
            style.firstLineHeadIndent = indent
            if centered { style.alignment = .center }
            return style
        }
        func append(_ runs: [MarkdownRun], font: NSFont, color: NSColor = .labelColor, indent: CGFloat = 0, centered: Bool = false, prefix: String = "") {
            let style = paragraphStyle(indent: indent, centered: centered)
            if !prefix.isEmpty {
                output.append(NSAttributedString(string: prefix, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style]))
            }
            for run in runs {
                var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
                var traits: NSFontTraitMask = []
                if run.bold { traits.insert(.boldFontMask) }
                if run.italic { traits.insert(.italicFontMask) }
                attributes[.font] = NSFontManager.shared.convert(font, toHaveTrait: traits)
                if run.code { attributes[.font] = mono }
                if run.strike { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                if let address = run.link, let link = URL(string: address), ["https", "http", "mailto"].contains(link.scheme?.lowercased() ?? "") {
                    attributes[.link] = link
                    attributes[.foregroundColor] = NSColor.linkColor
                }
                output.append(NSAttributedString(string: run.text, attributes: attributes))
            }
            output.append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: style]))
        }
        for block in MarkdownBlocks.parse(source) {
            switch block {
            case let .paragraph(runs): append(runs, font: base)
            case let .heading(level, runs):
                let headingSize = size + Double(max(1, 5 - level)) * 3
                let font = NSFontManager.shared.font(withFamily: family, traits: .boldFontMask, weight: 9, size: headingSize) ?? .systemFont(ofSize: headingSize, weight: .semibold)
                append(runs.map { var run = $0; run.bold = false; return run }, font: font)
            case let .quote(runs): append(runs, font: base, color: .secondaryLabelColor, indent: 18)
            case let .bullet(runs, depth): append(runs, font: base, indent: CGFloat(depth) * 18, prefix: "•  ")
            case let .numbered(number, runs, depth): append(runs, font: base, indent: CGFloat(depth) * 18, prefix: "\(number).  ")
            case let .task(done, runs, depth): append(runs, font: base, indent: CGFloat(depth) * 18, prefix: (done ? "☑" : "☐") + "  ")
            case .sceneBreak: append([MarkdownRun(text: "*  *  *")], font: base, color: .tertiaryLabelColor, centered: true)
            case let .code(text):
                for line in text.components(separatedBy: "\n") { append([MarkdownRun(text: line)], font: mono) }
            case let .table(rows, _):
                for row in rows { append([MarkdownRun(text: row.joined(separator: "   "))], font: mono, color: .secondaryLabelColor) }
            case let .image(alt, _):
                append([MarkdownRun(text: alt.isEmpty ? "[Image]" : "[Image: \(alt)]", italic: true)], font: base, color: .tertiaryLabelColor)
            }
        }
        return output
    }
}

struct ReadingView: NSViewRepresentable {
    @AppStorage("writingTheme") private var themeName = "graphite"
    @AppStorage("editorZoom") private var globalZoom = 1.0
    var zoom: Double? = nil
    var zoomKey: String = WritingZoom.mainKey
    let text: String
    let family: String
    let size: Double
    let spacing: Double
    var width: Double = 680
    var darker = false
    /// Let the page behind show through (the edge shading is drawn there).
    var transparent = false
    var sidebarGesture: (() -> Void)? = nil
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = WritingScrollView(frame: NSRect(x: 0, y: 0, width: 700, height: 600))
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.zoomKey = zoomKey
        scroll.sidebarGesture = sidebarGesture
        let view = ReadingTextView(frame: scroll.contentView.bounds)
        view.isEditable = false; view.isSelectable = true
        view.isVerticallyResizable = true; view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize.height = CGFloat.greatestFiniteMagnitude
        view.delegate = context.coordinator
        scroll.documentView = view
        return scroll
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
            guard let url else { return false }
            NSWorkspace.shared.open(url)
            return true
        }
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? ReadingTextView else { return }
        (scroll as? WritingScrollView)?.zoomKey = zoomKey
        (scroll as? WritingScrollView)?.sidebarGesture = sidebarGesture
        let zoom = self.zoom ?? globalZoom
        view.columnWidth = width * zoom
        view.updateMargins()
        view.appearance = darker ? NSAppearance(named: .darkAqua) : nil
        let theme = WritingTheme.named(darker ? "midnight" : themeName)
        view.backgroundColor = transparent ? .clear : theme.background
        view.drawsBackground = !transparent
        scroll.drawsBackground = !transparent
        scroll.contentView.drawsBackground = !transparent
        let key = "\(family)|\(size)|\(spacing)|\(zoom)|\(theme.id)|\(text)"
        if view.renderKey != key {
            let rendered = NSMutableAttributedString(attributedString: MarkdownReading.render(text, family: family, size: size * zoom, spacing: spacing))
            rendered.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: rendered.length)) { value, range, _ in
                if (value as? NSColor) == NSColor.labelColor { rendered.addAttribute(.foregroundColor, value: theme.foreground, range: range) }
            }
            view.textStorage?.setAttributedString(rendered)
            view.renderKey = key
        }
    }
}
final class ReadingTextView: NSTextView {
    var columnWidth = 680.0
    var renderKey = ""
    func updateMargins() { textContainerInset = NSSize(width: max(26, (bounds.width - columnWidth) / 2), height: 36) }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); updateMargins() }
}
