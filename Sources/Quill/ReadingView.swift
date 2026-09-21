import SwiftUI
import AppKit

@MainActor
enum MarkdownReading {
    static func render(_ source: String, family: String, size: Double, spacing: Double) -> NSAttributedString {
        let base = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size) ?? .systemFont(ofSize: size)
        let output = NSMutableAttributedString()
        var fence: String?
        var paragraph: [String] = []
        func append(_ text: String, font: NSFont, color: NSColor = .labelColor, indent: CGFloat = 0, literal: Bool = false) {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = size * spacing
            style.paragraphSpacing = size * 0.8
            style.headIndent = indent
            style.firstLineHeadIndent = indent
            let defaults: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
            if literal { output.append(NSAttributedString(string: text + "\n", attributes: defaults)); return }
            let parsed = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
            for run in parsed.runs {
                var attributes = defaults
                var traits: NSFontTraitMask = []
                if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true { traits.insert(.boldFontMask) }
                if run.inlinePresentationIntent?.contains(.emphasized) == true { traits.insert(.italicFontMask) }
                attributes[.font] = NSFontManager.shared.convert(font, toHaveTrait: traits)
                if run.inlinePresentationIntent?.contains(.code) == true { attributes[.font] = NSFont.monospacedSystemFont(ofSize: size * 0.88, weight: .regular) }
                if run.inlinePresentationIntent?.contains(.strikethrough) == true { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                if let link = run.link, ["https", "http", "mailto"].contains(link.scheme?.lowercased() ?? "") {
                    attributes[.link] = link; attributes[.foregroundColor] = NSColor.linkColor
                }
                output.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
            }
            output.append(NSAttributedString(string: "\n", attributes: defaults))
        }
        func flush() {
            if !paragraph.isEmpty { append(paragraph.joined(separator: " "), font: base); paragraph = [] }
        }
        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                let marker = String(trimmed.prefix(3))
                if fence == nil { fence = marker } else if fence == marker { fence = nil }
                continue
            }
            if fence != nil { append(line, font: .monospacedSystemFont(ofSize: size * 0.88, weight: .regular), literal: true); continue }
            if trimmed.isEmpty { flush(); continue }
            if let match = trimmed.range(of: "^#{1,6}\\s+", options: .regularExpression) {
                flush()
                let level = trimmed[match].filter { $0 == "#" }.count
                let headingSize = size + Double(max(1, 5 - level)) * 3
                let font = NSFontManager.shared.font(withFamily: family, traits: .boldFontMask, weight: 9, size: headingSize) ?? .systemFont(ofSize: headingSize, weight: .semibold)
                let title = String(trimmed[match.upperBound...]).replacingOccurrences(of: "\\s+#+\\s*$", with: "", options: .regularExpression)
                append(title, font: font)
            } else if trimmed.hasPrefix(">") {
                flush(); append(trimmed.replacingOccurrences(of: "^(>\\s*)+", with: "", options: .regularExpression), font: base, color: .secondaryLabelColor, indent: 18)
            } else if let match = trimmed.range(of: "^(?:[-+*]|[0-9]+[.)])\\s+", options: .regularExpression) {
                flush()
                let prefix = String(trimmed[match]).trimmingCharacters(in: .whitespaces)
                let bullet = prefix.first?.isNumber == true ? prefix : "•"
                let indent = CGFloat(line.prefix { $0 == " " || $0 == "\t" }.count) * 5
                append(bullet + "  " + String(trimmed[match.upperBound...]), font: base, indent: indent)
            } else if ["---", "***", "___"].contains(trimmed) { flush(); append("―", font: base, color: .tertiaryLabelColor) }
            else { paragraph.append(trimmed) }
        }
        flush()
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
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = WritingScrollView(frame: NSRect(x: 0, y: 0, width: 700, height: 600))
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.zoomKey = zoomKey
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
        let zoom = self.zoom ?? globalZoom
        view.columnWidth = width * zoom
        view.updateMargins()
        view.appearance = darker ? NSAppearance(named: .darkAqua) : nil
        let theme = WritingTheme.named(darker ? "midnight" : themeName)
        view.backgroundColor = theme.background
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
