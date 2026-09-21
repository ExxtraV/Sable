import Foundation
import QuillCore
import AppKit
import CoreText
import PDFKit

// Exporting a manuscript: chapters in their saved order become one PDF, EPUB, Word document, or Markdown file.
// Everything here is built from the files themselves, with no outside tools: a small Markdown reader turns each
// chapter into simple blocks, and each format writes those blocks its own way.

enum ExportFormat: String, CaseIterable, Sendable {
    case pdf, epub, docx, markdown
    var title: String {
        switch self { case .pdf: return "PDF"; case .epub: return "EPUB"; case .docx: return "Word"; case .markdown: return "Markdown" }
    }
    var fileExtension: String {
        switch self { case .pdf: return "pdf"; case .epub: return "epub"; case .docx: return "docx"; case .markdown: return "md" }
    }
    /// Whether page layout settings (style, size, page breaks) apply.
    var isPaged: Bool { self == .pdf || self == .docx }
}

enum ExportStyle: String, CaseIterable, Sendable {
    case manuscript, book
    var title: String { self == .manuscript ? "Manuscript" : "Book" }
    var detail: String {
        self == .manuscript ? "12-point Times, double-spaced, running header. The usual shape for submissions." : "Serif type, tighter lines, page numbers at the foot. Reads like a printed book."
    }
}

enum PageSize: String, CaseIterable, Sendable {
    case letter, a4
    var title: String { self == .letter ? "US Letter" : "A4" }
    var points: CGSize { self == .letter ? CGSize(width: 612, height: 792) : CGSize(width: 595.28, height: 841.89) }
    /// A4 in metric countries, Letter elsewhere.
    static var regional: PageSize { Locale.current.measurementSystem == .metric ? .a4 : .letter }
}

struct ExportOptions: Sendable {
    var title = "Untitled"
    var author = ""
    var format = ExportFormat.pdf
    var style = ExportStyle.manuscript
    var pageSize = PageSize.regional
    var titlePage = true
    var chapterPageBreaks = true
    var sceneBreak = "* * *"
}

struct ExportChapter: Equatable, Sendable, Identifiable {
    let name: String        // file name, the stable identity
    let title: String
    let body: String        // Markdown, without the card/tag block or the title heading
    var id: String { name }
    var words: Int { ManuscriptStats.wordCount(in: body) }
}

enum ExportError: LocalizedError {
    case nothingToExport, couldNotBuild(String)
    var errorDescription: String? {
        switch self {
        case .nothingToExport: return "There are no chapters to export."
        case let .couldNotBuild(reason): return "The export couldn’t be built: \(reason)"
        }
    }
}

// MARK: - Reading chapters

enum ManuscriptExport {
    /// Splits a chapter file into its title and its text. A leading "# Title" line becomes the title;
    /// the tag block at the top of the file is dropped. Without a heading, the file name is the title.
    static func chapter(named name: String, markdown: String) -> ExportChapter {
        let body = FrontMatter.parse(markdown).body
        var lines = body.components(separatedBy: "\n")
        var title = (name as NSString).deletingPathExtension
        if let index = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }), lines[index].hasPrefix("# ") {
            title = String(lines[index].dropFirst(2)).trimmingCharacters(in: .whitespaces)
            lines.remove(at: index)
        }
        return ExportChapter(name: name, title: title, body: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The project's chapters in the order the writer arranged them (or only those named in `include`).
    static func chapters(project: URL, include: Set<String>? = nil) -> [ExportChapter] {
        let folder = FictionProject.folder(for: .chapter, in: project)
        let order = FictionProject.load(project)?.chapterOrder
        return ManuscriptStats.load(folder: folder, order: order).compactMap { stat in
            guard include?.contains(stat.name) ?? true, let text = try? String(contentsOf: stat.url, encoding: .utf8) else { return nil }
            return chapter(named: stat.name, markdown: text)
        }
    }

    /// A safe file name for a save panel's suggestion.
    static func fileName(for title: String, format: ExportFormat) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? "Manuscript" : cleaned) + "." + format.fileExtension
    }

    static func export(_ chapters: [ExportChapter], options: ExportOptions) throws -> Data {
        guard !chapters.isEmpty else { throw ExportError.nothingToExport }
        switch options.format {
        case .pdf: return try PDFExporter.data(chapters, options)
        case .epub: return EPUBExporter.data(chapters, options)
        case .docx: return DOCXExporter.data(chapters, options)
        case .markdown: return Data(MarkdownExporter.text(chapters, options).utf8)
        }
    }
}

// MARK: - Markdown reading

// One Markdown reader serves the editor, Reading Mode, and every export: see MarkdownDocument.swift in QuillCore.
typealias ExportRun = MarkdownRun
typealias ExportBlock = MarkdownBlock

// MARK: - Zip

/// A minimal zip writer (stored, uncompressed), enough for EPUB and Word packages.
struct ZipWriter {
    private struct Entry { let name: String; let crc: UInt32; let size: UInt32; let offset: UInt32; let time: UInt16; let date: UInt16 }
    private var entries: [Entry] = []
    private var data = Data()

    private static let table: [UInt32] = (0..<256).map { index in
        (0..<8).reduce(UInt32(index)) { value, _ in value & 1 == 1 ? (value >> 1) ^ 0xEDB88320 : value >> 1 }
    }
    static func crc32(_ bytes: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFFFFFF
    }
    private static func dos(_ date: Date) -> (time: UInt16, date: UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        let year = max(1980, c.year ?? 1980)
        let hour = c.hour ?? 0, minute = c.minute ?? 0, second = (c.second ?? 0) / 2
        let month = c.month ?? 1, day = c.day ?? 1
        let time: Int = (hour << 11) | (minute << 5) | second
        let stamp: Int = ((year - 1980) << 9) | (month << 5) | day
        return (UInt16(time), UInt16(stamp))
    }
    private static func put<T: FixedWidthInteger>(_ value: T, to output: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { output.append(contentsOf: $0) }
    }

    mutating func add(_ name: String, _ content: Data, date: Date = Date()) {
        let stamp = ZipWriter.dos(date)
        let crc = ZipWriter.crc32(content)
        let offset = UInt32(data.count)
        ZipWriter.put(UInt32(0x04034b50), to: &data); ZipWriter.put(UInt16(20), to: &data); ZipWriter.put(UInt16(0x0800), to: &data); ZipWriter.put(UInt16(0), to: &data)
        ZipWriter.put(stamp.time, to: &data); ZipWriter.put(stamp.date, to: &data); ZipWriter.put(crc, to: &data)
        ZipWriter.put(UInt32(content.count), to: &data); ZipWriter.put(UInt32(content.count), to: &data)
        let nameBytes = Data(name.utf8)
        ZipWriter.put(UInt16(nameBytes.count), to: &data); ZipWriter.put(UInt16(0), to: &data)
        data.append(nameBytes); data.append(content)
        entries.append(Entry(name: name, crc: crc, size: UInt32(content.count), offset: offset, time: stamp.time, date: stamp.date))
    }
    mutating func add(_ name: String, _ text: String, date: Date = Date()) { add(name, Data(text.utf8), date: date) }

    func finish() -> Data {
        var output = data
        var central = Data()
        func write<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { central.append(contentsOf: $0) } }
        for entry in entries {
            write(UInt32(0x02014b50)); write(UInt16(20)); write(UInt16(20)); write(UInt16(0x0800)); write(UInt16(0))
            write(entry.time); write(entry.date); write(entry.crc); write(entry.size); write(entry.size)
            let nameBytes = Data(entry.name.utf8)
            write(UInt16(nameBytes.count)); write(UInt16(0)); write(UInt16(0)); write(UInt16(0)); write(UInt16(0)); write(UInt32(0)); write(entry.offset)
            central.append(nameBytes)
        }
        let start = UInt32(output.count)
        output.append(central)
        func end<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { output.append(contentsOf: $0) } }
        end(UInt32(0x06054b50)); end(UInt16(0)); end(UInt16(0)); end(UInt16(entries.count)); end(UInt16(entries.count))
        end(UInt32(central.count)); end(start); end(UInt16(0))
        return output
    }
}

func xmlEscape(_ text: String) -> String {
    var result = ""
    result.reserveCapacity(text.count)
    for scalar in text.unicodeScalars {
        switch scalar {
        case "&": result += "&amp;"
        case "<": result += "&lt;"
        case ">": result += "&gt;"
        case "\"": result += "&quot;"
        // Characters XML 1.0 can't carry would make a file unreadable, so drop them.
        case let s where s.value < 0x20 && s != "\t" && s != "\n" && s != "\r": continue
        default: result.unicodeScalars.append(scalar)
        }
    }
    return result
}

// MARK: - Markdown

enum MarkdownExporter {
    static func text(_ chapters: [ExportChapter], _ options: ExportOptions) -> String {
        var out = ""
        if options.titlePage {
            out += "# \(options.title)\n\n"
            if !options.author.isEmpty { out += "*by \(options.author)*\n\n" }
            out += "---\n\n"
        }
        for chapter in chapters {
            out += "## \(chapter.title)\n\n\(chapter.body)\n\n"
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }
}

// MARK: - EPUB

enum EPUBExporter {
    static func data(_ chapters: [ExportChapter], _ options: ExportOptions, date: Date = Date()) -> Data {
        var zip = ZipWriter()
        let identifier = "urn:uuid:" + UUID().uuidString
        let stamp = ISO8601DateFormatter().string(from: date)
        // The mimetype must come first and be stored uncompressed, which this writer always does.
        zip.add("mimetype", "application/epub+zip", date: date)
        zip.add("META-INF/container.xml", """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """, date: date)
        zip.add("OEBPS/style.css", css, date: date)

        var manifest = "    <item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>\n    <item id=\"css\" href=\"style.css\" media-type=\"text/css\"/>\n"
        var spine = ""
        var toc = ""
        if options.titlePage {
            zip.add("OEBPS/title.xhtml", page(title: options.title, body: "<div class=\"titlepage\"><h1>\(xmlEscape(options.title))</h1>\(options.author.isEmpty ? "" : "<p class=\"author\">\(xmlEscape(options.author))</p>")</div>"), date: date)
            manifest += "    <item id=\"title\" href=\"title.xhtml\" media-type=\"application/xhtml+xml\"/>\n"
            spine += "    <itemref idref=\"title\"/>\n"
        }
        for (index, chapter) in chapters.enumerated() {
            let file = String(format: "chapter%03d.xhtml", index + 1)
            zip.add("OEBPS/\(file)", page(title: chapter.title, body: chapterBody(chapter, options)), date: date)
            manifest += "    <item id=\"c\(index + 1)\" href=\"\(file)\" media-type=\"application/xhtml+xml\"/>\n"
            spine += "    <itemref idref=\"c\(index + 1)\"/>\n"
            toc += "      <li><a href=\"\(file)\">\(xmlEscape(chapter.title))</a></li>\n"
        }
        zip.add("OEBPS/nav.xhtml", """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="en" lang="en">
        <head><meta charset="utf-8"/><title>Contents</title></head>
        <body><nav epub:type="toc" id="toc"><h1>Contents</h1>
        <ol>
        \(toc)    </ol></nav></body></html>
        """, date: date)
        zip.add("OEBPS/content.opf", """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id" xml:lang="en">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="book-id">\(identifier)</dc:identifier>
            <dc:title>\(xmlEscape(options.title))</dc:title>
        \(options.author.isEmpty ? "" : "    <dc:creator>\(xmlEscape(options.author))</dc:creator>\n")    <dc:language>en</dc:language>
            <meta property="dcterms:modified">\(stamp)</meta>
          </metadata>
          <manifest>
        \(manifest)  </manifest>
          <spine>
        \(spine)  </spine>
        </package>
        """, date: date)
        return zip.finish()
    }

    private static let css = """
    body { font-family: serif; line-height: 1.45; margin: 5%; }
    h1 { text-align: center; font-size: 1.6em; margin: 2em 0 1.2em; page-break-before: always; }
    h2, h3, h4, h5, h6 { text-align: center; margin: 1.6em 0 0.8em; }
    p { margin: 0; text-indent: 1.4em; text-align: justify; }
    h1 + p, h2 + p, h3 + p, p.first, p.scenebreak + p { text-indent: 0; }
    p.scenebreak { text-align: center; text-indent: 0; margin: 1.4em 0; }
    blockquote { margin: 1em 2em; font-style: italic; }
    blockquote p { text-indent: 0; }
    pre { font-family: monospace; white-space: pre-wrap; margin: 1em 0; }
    ul, ol { margin: 0.8em 0 0.8em 1.6em; }
    .titlepage { text-align: center; margin-top: 30%; }
    .titlepage h1 { page-break-before: avoid; font-size: 2.2em; }
    .titlepage .author { text-indent: 0; text-align: center; font-size: 1.2em; margin-top: 1.5em; }
    """

    private static func page(title: String, body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
        <head><meta charset="utf-8"/><title>\(xmlEscape(title))</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
        <body>
        \(body)
        </body></html>
        """
    }

    static func inline(_ runs: [ExportRun]) -> String {
        runs.map { run in
            var html = xmlEscape(run.text)
            if run.code { html = "<code>\(html)</code>" }
            if run.strike { html = "<del>\(html)</del>" }
            if run.italic { html = "<em>\(html)</em>" }
            if run.bold { html = "<strong>\(html)</strong>" }
            return html
        }.joined()
    }

    static func chapterBody(_ chapter: ExportChapter, _ options: ExportOptions) -> String {
        var html = "<h1>\(xmlEscape(chapter.title))</h1>\n"
        var openList: String?
        func closeList() { if let tag = openList { html += "</\(tag)>\n"; openList = nil } }
        for block in MarkdownBlocks.parse(chapter.body) {
            switch block {
            case let .bullet(runs, depth):
                if openList != "ul" { closeList(); html += "<ul>\n"; openList = "ul" }
                html += "<li\(depth > 0 ? " style=\"margin-left:\(Double(depth) * 1.5)em\"" : "")>\(inline(runs))</li>\n"
            case let .numbered(_, runs, depth):
                if openList != "ol" { closeList(); html += "<ol>\n"; openList = "ol" }
                html += "<li\(depth > 0 ? " style=\"margin-left:\(Double(depth) * 1.5)em\"" : "")>\(inline(runs))</li>\n"
            case let .task(done, runs, depth):
                if openList != "ul" { closeList(); html += "<ul style=\"list-style:none\">\n"; openList = "ul" }
                html += "<li\(depth > 0 ? " style=\"margin-left:\(Double(depth) * 1.5)em\"" : "")>\(done ? "☑" : "☐") \(inline(runs))</li>\n"
            default:
                closeList()
                switch block {
                case let .heading(level, runs): let tag = "h\(min(6, level + 1))"; html += "<\(tag)>\(inline(runs))</\(tag)>\n"
                case let .paragraph(runs): html += "<p>\(inline(runs))</p>\n"
                case let .quote(runs): html += "<blockquote><p>\(inline(runs))</p></blockquote>\n"
                case .sceneBreak: html += "<p class=\"scenebreak\">\(xmlEscape(options.sceneBreak))</p>\n"
                case let .code(text): html += "<pre>\(xmlEscape(text))</pre>\n"
                case let .table(rows, header):
                    html += "<table>\n"
                    for (index, row) in rows.enumerated() {
                        let tag = header && index == 0 ? "th" : "td"
                        html += "<tr>" + row.map { "<\(tag)>\(xmlEscape($0))</\(tag)>" }.joined() + "</tr>\n"
                    }
                    html += "</table>\n"
                case .image: break   // A picture has no place in the words of a manuscript.
                case .bullet, .numbered, .task: break
                }
            }
        }
        closeList()
        return html
    }
}

// MARK: - Word (.docx)

enum DOCXExporter {
    static func data(_ chapters: [ExportChapter], _ options: ExportOptions, date: Date = Date()) -> Data {
        var zip = ZipWriter()
        let manuscript = options.style == .manuscript
        let size = options.pageSize
        zip.add("[Content_Types].xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
          <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
          <Override PartName="/word/\(manuscript ? "header1" : "footer1").xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.\(manuscript ? "header" : "footer")+xml"/>
          <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
        </Types>
        """, date: date)
        zip.add("_rels/.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
        </Relationships>
        """, date: date)
        zip.add("word/_rels/document.xml.rels", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
          <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/\(manuscript ? "header" : "footer")" Target="\(manuscript ? "header1" : "footer1").xml"/>
        </Relationships>
        """, date: date)
        zip.add("docProps/core.xml", """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <dc:title>\(xmlEscape(options.title))</dc:title><dc:creator>\(xmlEscape(options.author))</dc:creator>
          <dcterms:created xsi:type="dcterms:W3CDTF">\(ISO8601DateFormatter().string(from: date))</dcterms:created>
        </cp:coreProperties>
        """, date: date)
        zip.add("word/styles.xml", styles(manuscript: manuscript), date: date)
        let pageField = "<w:r><w:fldChar w:fldCharType=\"begin\"/></w:r><w:r><w:instrText xml:space=\"preserve\"> PAGE </w:instrText></w:r><w:r><w:fldChar w:fldCharType=\"separate\"/></w:r><w:r><w:t>1</w:t></w:r><w:r><w:fldChar w:fldCharType=\"end\"/></w:r>"
        let ns = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\""
        if manuscript {
            // The customary running header: author / title / page number, at the top right.
            let label = [options.author.components(separatedBy: " ").last ?? "", options.title].filter { !$0.isEmpty }.joined(separator: " / ")
            zip.add("word/header1.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:hdr \(ns)><w:p><w:pPr><w:jc w:val=\"right\"/></w:pPr><w:r><w:t xml:space=\"preserve\">\(xmlEscape(label))\(label.isEmpty ? "" : " / ")</w:t></w:r>\(pageField)</w:p></w:hdr>", date: date)
        } else {
            zip.add("word/footer1.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:ftr \(ns)><w:p><w:pPr><w:jc w:val=\"center\"/></w:pPr>\(pageField)</w:p></w:ftr>", date: date)
        }

        var body = ""
        let words = chapters.reduce(0) { $0 + $1.words }
        if options.titlePage {
            if manuscript {
                body += paragraph("About \(roundedWords(words)) words", style: "Byline", align: "right")
                body += "<w:p><w:pPr><w:pStyle w:val=\"Title\"/><w:spacing w:before=\"3600\"/></w:pPr><w:r><w:t xml:space=\"preserve\">\(xmlEscape(options.title))</w:t></w:r></w:p>"
            } else {
                body += "<w:p><w:pPr><w:pStyle w:val=\"Title\"/><w:spacing w:before=\"4200\"/></w:pPr><w:r><w:t xml:space=\"preserve\">\(xmlEscape(options.title))</w:t></w:r></w:p>"
            }
            if !options.author.isEmpty { body += paragraph("by \(options.author)", style: "Subtitle", align: "center") }
        }
        for (index, chapter) in chapters.enumerated() {
            // The first chapter always starts a fresh page after a title page; others follow the setting.
            let breakBefore = (index == 0 && options.titlePage) || (index > 0 && options.chapterPageBreaks)
            body += "<w:p><w:pPr><w:pStyle w:val=\"Heading1\"/>\(breakBefore ? "<w:pageBreakBefore/>" : "")\(manuscript && breakBefore ? "<w:spacing w:before=\"2400\" w:after=\"480\"/>" : "")</w:pPr><w:r><w:t xml:space=\"preserve\">\(xmlEscape(chapter.title))</w:t></w:r></w:p>"
            var afterOpening = true
            for block in MarkdownBlocks.parse(chapter.body) {
                switch block {
                case let .paragraph(runs):
                    body += "<w:p><w:pPr><w:pStyle w:val=\"\(afterOpening ? "FirstParagraph" : "BodyText")\"/></w:pPr>\(runsXML(runs))</w:p>"
                    afterOpening = false
                case let .heading(level, runs):
                    body += "<w:p><w:pPr><w:pStyle w:val=\"Heading\(min(3, level + 1))\"/></w:pPr>\(runsXML(runs))</w:p>"
                    afterOpening = true
                case let .quote(runs): body += "<w:p><w:pPr><w:pStyle w:val=\"Quote\"/></w:pPr>\(runsXML(runs))</w:p>"; afterOpening = true
                case let .bullet(runs, depth): body += listItem("•", runs, depth); afterOpening = false
                case let .numbered(number, runs, depth): body += listItem("\(number).", runs, depth); afterOpening = false
                case let .task(done, runs, depth): body += listItem(done ? "☑" : "☐", runs, depth); afterOpening = false
                case let .table(rows, _):
                    for row in rows { body += "<w:p><w:pPr><w:pStyle w:val=\"BodyText\"/></w:pPr><w:r><w:t xml:space=\"preserve\">\(xmlEscape(row.joined(separator: "  |  ")))</w:t></w:r></w:p>" }
                    afterOpening = false
                case .image: break
                case .sceneBreak: body += paragraph(options.sceneBreak, style: "SceneBreak", align: "center"); afterOpening = true
                case let .code(text):
                    for line in text.components(separatedBy: "\n") { body += "<w:p><w:pPr><w:pStyle w:val=\"Code\"/></w:pPr><w:r><w:t xml:space=\"preserve\">\(xmlEscape(line))</w:t></w:r></w:p>" }
                    afterOpening = false
                }
            }
        }
        let width = Int(size.points.width * 20), height = Int(size.points.height * 20)
        let margin = manuscript ? 1440 : 1300
        body += "<w:sectPr><w:\(manuscript ? "header" : "footer")Reference w:type=\"default\" r:id=\"rId2\"/><w:pgSz w:w=\"\(width)\" w:h=\"\(height)\"/><w:pgMar w:top=\"\(margin)\" w:right=\"\(margin)\" w:bottom=\"\(margin)\" w:left=\"\(margin)\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/>\(options.titlePage ? "<w:pgNumType w:start=\"0\"/><w:titlePg/>" : "")</w:sectPr>"
        zip.add("word/document.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:document \(ns)><w:body>\(body)</w:body></w:document>", date: date)
        return zip.finish()
    }

    private static func roundedWords(_ count: Int) -> String {
        let step = count >= 10_000 ? 1_000 : (count >= 1_000 ? 100 : 10)
        return ((count + step / 2) / step * step).formatted()
    }

    private static func listItem(_ marker: String, _ runs: [ExportRun], _ depth: Int) -> String {
        let indent = depth > 0 ? "<w:ind w:left=\"\(720 + depth * 360)\" w:hanging=\"360\"/>" : ""
        return "<w:p><w:pPr><w:pStyle w:val=\"ListItem\"/>\(indent)</w:pPr><w:r><w:t xml:space=\"preserve\">\(marker)\t</w:t></w:r>\(runsXML(runs))</w:p>"
    }

    private static func paragraph(_ text: String, style: String, align: String) -> String {
        "<w:p><w:pPr><w:pStyle w:val=\"\(style)\"/><w:jc w:val=\"\(align)\"/></w:pPr><w:r><w:t xml:space=\"preserve\">\(xmlEscape(text))</w:t></w:r></w:p>"
    }

    private static func runsXML(_ runs: [ExportRun]) -> String {
        runs.map { run in
            var properties = ""
            if run.code { properties += "<w:rFonts w:ascii=\"Courier New\" w:hAnsi=\"Courier New\" w:cs=\"Courier New\"/>" }
            if run.bold { properties += "<w:b/>" }
            if run.italic { properties += "<w:i/>" }
            if run.strike { properties += "<w:strike/>" }
            return "<w:r>\(properties.isEmpty ? "" : "<w:rPr>\(properties)</w:rPr>")<w:t xml:space=\"preserve\">\(xmlEscape(run.text))</w:t></w:r>"
        }.joined()
    }

    private static func styles(manuscript: Bool) -> String {
        let font = manuscript ? "Times New Roman" : "Palatino Linotype"
        let size = manuscript ? 24 : 22
        let line = manuscript ? 480 : 300
        let indent = manuscript ? 720 : 360
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:docDefaults>
            <w:rPrDefault><w:rPr><w:rFonts w:ascii="\(font)" w:hAnsi="\(font)" w:cs="\(font)" w:eastAsia="\(font)"/><w:sz w:val="\(size)"/><w:szCs w:val="\(size)"/><w:lang w:val="en-US"/></w:rPr></w:rPrDefault>
            <w:pPrDefault><w:pPr><w:spacing w:after="0" w:line="\(line)" w:lineRule="auto"/></w:pPr></w:pPrDefault>
          </w:docDefaults>
          <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>
          <w:style w:type="paragraph" w:styleId="BodyText"><w:name w:val="Body Text"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:ind w:firstLine="\(indent)"/>\(manuscript ? "" : "<w:jc w:val=\"both\"/>")</w:pPr></w:style>
          <w:style w:type="paragraph" w:styleId="FirstParagraph"><w:name w:val="First Paragraph"/><w:basedOn w:val="Normal"/><w:qFormat/>\(manuscript ? "<w:pPr><w:ind w:firstLine=\"\(indent)\"/></w:pPr>" : "<w:pPr><w:jc w:val=\"both\"/></w:pPr>")</w:style>
          <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="FirstParagraph"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="480" w:after="360"/><w:jc w:val="center"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="\(size + 6)"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="FirstParagraph"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="360" w:after="240"/><w:jc w:val="center"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:next w:val="FirstParagraph"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before="240" w:after="120"/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:i/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:before="120" w:after="120"/><w:ind w:left="720" w:right="720"/></w:pPr><w:rPr><w:i/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="SceneBreak"><w:name w:val="Scene Break"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:before="240" w:after="240"/><w:jc w:val="center"/></w:pPr></w:style>
          <w:style w:type="paragraph" w:styleId="ListItem"><w:name w:val="List Item"/><w:basedOn w:val="Normal"/><w:pPr><w:tabs><w:tab w:val="left" w:pos="720"/></w:tabs><w:ind w:left="720" w:hanging="360"/></w:pPr></w:style>
          <w:style w:type="paragraph" w:styleId="Code"><w:name w:val="Code"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:line="240" w:lineRule="auto"/></w:pPr><w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:cs="Courier New"/><w:sz w:val="20"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:jc w:val="center"/></w:pPr><w:rPr><w:b/><w:sz w:val="56"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Subtitle"><w:name w:val="Subtitle"/><w:basedOn w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:before="480"/><w:jc w:val="center"/></w:pPr><w:rPr><w:sz w:val="\(size + 4)"/></w:rPr></w:style>
          <w:style w:type="paragraph" w:styleId="Byline"><w:name w:val="Byline"/><w:basedOn w:val="Normal"/><w:pPr><w:jc w:val="right"/></w:pPr></w:style>
        </w:styles>
        """
    }
}

// MARK: - PDF

enum PDFExporter {
    private struct Metrics {
        let font: String, size: CGFloat, lineMultiple: CGFloat, indent: CGFloat, margin: CGFloat, justified: Bool
        let paragraphSpace: CGFloat
    }
    private static func metrics(_ style: ExportStyle) -> Metrics {
        style == .manuscript
            ? Metrics(font: "Times New Roman", size: 12, lineMultiple: 2.0, indent: 36, margin: 72, justified: false, paragraphSpace: 0)
            : Metrics(font: "Charter", size: 11, lineMultiple: 1.28, indent: 18, margin: 66, justified: true, paragraphSpace: 0)
    }

    private static func font(_ name: String, _ size: CGFloat, bold: Bool = false, italic: Bool = false, mono: Bool = false) -> CTFont {
        let base = CTFontCreateWithName((mono ? "Courier New" : name) as CFString, size, nil)
        var traits: CTFontSymbolicTraits = []
        if bold { traits.insert(.boldTrait) }
        if italic { traits.insert(.italicTrait) }
        guard !traits.isEmpty else { return base }
        return CTFontCreateCopyWithSymbolicTraits(base, size, nil, traits, traits) ?? base
    }

    private static func paragraphStyle(_ m: Metrics, first: CGFloat = 0, head: CGFloat = 0, tail: CGFloat = 0, align: CTTextAlignment = .natural, multiple: CGFloat? = nil, before: CGFloat = 0, after: CGFloat = 0) -> CTParagraphStyle {
        var alignment = align, firstIndent = first, headIndent = head, tailIndent = tail
        var lineMultiple = multiple ?? m.lineMultiple, spaceBefore = before, spaceAfter = after
        return withUnsafePointer(to: &alignment) { a in withUnsafePointer(to: &firstIndent) { f in withUnsafePointer(to: &headIndent) { h in
            withUnsafePointer(to: &tailIndent) { t in withUnsafePointer(to: &lineMultiple) { l in withUnsafePointer(to: &spaceBefore) { b in withUnsafePointer(to: &spaceAfter) { s in
                let settings = [
                    CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: a),
                    CTParagraphStyleSetting(spec: .firstLineHeadIndent, valueSize: MemoryLayout<CGFloat>.size, value: f),
                    CTParagraphStyleSetting(spec: .headIndent, valueSize: MemoryLayout<CGFloat>.size, value: h),
                    CTParagraphStyleSetting(spec: .tailIndent, valueSize: MemoryLayout<CGFloat>.size, value: t),
                    CTParagraphStyleSetting(spec: .lineHeightMultiple, valueSize: MemoryLayout<CGFloat>.size, value: l),
                    CTParagraphStyleSetting(spec: .paragraphSpacingBefore, valueSize: MemoryLayout<CGFloat>.size, value: b),
                    CTParagraphStyleSetting(spec: .paragraphSpacing, valueSize: MemoryLayout<CGFloat>.size, value: s),
                ]
                return CTParagraphStyleCreate(settings, settings.count)
            } } } } } } }
    }

    private static func attributed(_ runs: [ExportRun], _ m: Metrics, baseSize: CGFloat, style: CTParagraphStyle, forceItalic: Bool = false, forceBold: Bool = false) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in runs {
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(rawValue: kCTFontAttributeName as String): font(m.font, baseSize, bold: run.bold || forceBold, italic: run.italic || forceItalic, mono: run.code),
                NSAttributedString.Key(rawValue: kCTParagraphStyleAttributeName as String): style,
                NSAttributedString.Key(rawValue: kCTForegroundColorFromContextAttributeName as String): true,
            ]
            result.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        return result
    }

    /// One chapter as styled text: its title, then its blocks. Paragraphs are separated by newlines, as CoreText expects.
    private static func chapterText(_ chapter: ExportChapter, _ options: ExportOptions, _ m: Metrics, runningOn: Bool = false) -> NSAttributedString {
        let out = NSMutableAttributedString()
        func add(_ text: NSAttributedString) { out.append(text); out.append(NSAttributedString(string: "\n")) }
        // When chapters run on without page breaks, the title needs room above it.
        let title = paragraphStyle(m, align: .center, multiple: 1.1, before: runningOn ? m.size * 3 : 0, after: m.size * 1.8)
        add(attributed([ExportRun(text: chapter.title, bold: true)], m, baseSize: m.size + 5, style: title))
        var afterOpening = true
        for block in MarkdownBlocks.parse(chapter.body) {
            let alignment: CTTextAlignment = m.justified ? .justified : .natural
            switch block {
            case let .paragraph(runs):
                // Book convention: no indent on the first paragraph of a chapter or after a break.
                let indent = (options.style == .book && afterOpening) ? 0 : m.indent
                add(attributed(runs, m, baseSize: m.size, style: paragraphStyle(m, first: indent, align: alignment, after: m.paragraphSpace)))
                afterOpening = false
            case let .heading(_, runs):
                add(attributed(runs, m, baseSize: m.size + 2, style: paragraphStyle(m, align: .center, multiple: 1.2, before: m.size, after: m.size), forceBold: true))
                afterOpening = true
            case let .quote(runs):
                add(attributed(runs, m, baseSize: m.size, style: paragraphStyle(m, head: 36, tail: -36, align: .natural, multiple: max(1.2, m.lineMultiple * 0.85), before: 4, after: 4), forceItalic: true))
                afterOpening = true
            case let .bullet(runs, depth):
                add(attributed([ExportRun(text: "•\t")] + runs, m, baseSize: m.size, style: paragraphStyle(m, first: CGFloat(depth) * 18, head: 36 + CGFloat(depth) * 18, multiple: m.lineMultiple)))
                afterOpening = false
            case let .numbered(number, runs, depth):
                add(attributed([ExportRun(text: "\(number).\t")] + runs, m, baseSize: m.size, style: paragraphStyle(m, first: CGFloat(depth) * 18, head: 36 + CGFloat(depth) * 18, multiple: m.lineMultiple)))
                afterOpening = false
            case let .task(done, runs, depth):
                add(attributed([ExportRun(text: (done ? "☑" : "☐") + "\t")] + runs, m, baseSize: m.size, style: paragraphStyle(m, first: CGFloat(depth) * 18, head: 36 + CGFloat(depth) * 18, multiple: m.lineMultiple)))
                afterOpening = false
            case let .table(rows, _):
                for row in rows { add(attributed([ExportRun(text: row.joined(separator: "  |  "))], m, baseSize: m.size, style: paragraphStyle(m, multiple: m.lineMultiple))) }
                afterOpening = false
            case .image:
                break
            case .sceneBreak:
                add(attributed([ExportRun(text: options.sceneBreak)], m, baseSize: m.size, style: paragraphStyle(m, align: .center, before: m.size * 0.6, after: m.size * 0.6)))
                afterOpening = true
            case let .code(text):
                add(attributed([ExportRun(text: text, code: true)], m, baseSize: m.size - 1.5, style: paragraphStyle(m, multiple: 1.1, before: 4, after: 4)))
                afterOpening = false
            }
        }
        if out.length > 0 { out.deleteCharacters(in: NSRange(location: out.length - 1, length: 1)) }
        return out
    }

    /// A run of text laid out across pages, and where each chapter in it begins.
    private struct Section {
        var text: NSAttributedString
        var chapters: [(title: String, offset: Int)]
    }

    static func data(_ chapters: [ExportChapter], _ options: ExportOptions) throws -> Data {
        let m = metrics(options.style)
        let page = CGRect(origin: .zero, size: options.pageSize.points)
        let output = NSMutableData()
        var box = page
        guard let consumer = CGDataConsumer(data: output as CFMutableData), let context = CGContext(consumer: consumer, mediaBox: &box, [
            kCGPDFContextTitle as String: options.title, kCGPDFContextAuthor as String: options.author, kCGPDFContextCreator as String: "Sable Markdown Writer",
        ] as CFDictionary) else { throw ExportError.couldNotBuild("the PDF could not be started") }

        var outlinePages: [(title: String, page: Int)] = []
        var pageIndex = 0        // physical pages written so far
        var folio = 0            // the number printed on the page (a title page is unnumbered)
        let text = CGRect(x: m.margin, y: m.margin, width: page.width - 2 * m.margin, height: page.height - 2 * m.margin)
        let surname = options.author.components(separatedBy: " ").last ?? ""
        let header = [surname, options.title].filter { !$0.isEmpty }.joined(separator: " / ")

        func line(_ string: String, size: CGFloat, italic: Bool = false) -> CTLine {
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(rawValue: kCTFontAttributeName as String): font(m.font, size, italic: italic),
                NSAttributedString.Key(rawValue: kCTForegroundColorFromContextAttributeName as String): true,
            ]
            return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        }
        func width(_ line: CTLine) -> CGFloat { CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) }
        func draw(_ line: CTLine, x: CGFloat, y: CGFloat) { context.textPosition = CGPoint(x: x, y: y); CTLineDraw(line, context) }
        func beginPage() { context.beginPDFPage(nil); context.setFillColor(gray: 0, alpha: 1) }
        func endPage() { context.endPDFPage(); pageIndex += 1 }
        func drawFolio() {
            folio += 1
            if options.style == .manuscript {
                let label = line((header.isEmpty ? "" : header + " / ") + String(folio), size: 11)
                draw(label, x: page.width - m.margin - width(label), y: page.height - m.margin / 2 - 4)
            } else {
                let label = line(String(folio), size: 10)
                draw(label, x: page.midX - width(label) / 2, y: m.margin / 2 - 4)
            }
        }

        if options.titlePage {
            beginPage()
            let title = line(options.title, size: 30)
            draw(title, x: page.midX - width(title) / 2, y: page.height * 0.58)
            if !options.author.isEmpty {
                let byline = line("by \(options.author)", size: 15, italic: true)
                draw(byline, x: page.midX - width(byline) / 2, y: page.height * 0.58 - 46)
            }
            if options.style == .manuscript {
                let count = line("About \(chapters.reduce(0) { $0 + $1.words }.formatted()) words", size: 11)
                draw(count, x: page.width - m.margin - width(count), y: page.height - m.margin)
            }
            endPage()
        }

        // One section per chapter when chapters start new pages; otherwise the whole book as one continuous run.
        var sections: [Section] = []
        if options.chapterPageBreaks {
            sections = chapters.map { Section(text: chapterText($0, options, m), chapters: [($0.title, 0)]) }
        } else {
            let combined = NSMutableAttributedString()
            var starts: [(String, Int)] = []
            for (index, chapter) in chapters.enumerated() {
                if index > 0 { combined.append(NSAttributedString(string: "\n")) }
                starts.append((chapter.title, combined.length))
                combined.append(chapterText(chapter, options, m, runningOn: index > 0))
            }
            sections = [Section(text: combined, chapters: starts)]
        }

        for section in sections {
            let setter = CTFramesetterCreateWithAttributedString(section.text)
            var location = 0
            var first = true
            while location < section.text.length {
                beginPage()
                // A manuscript chapter opens a fifth of the way down its page.
                let inset: CGFloat = (first && options.chapterPageBreaks && options.style == .manuscript) ? page.height * 0.2 : 0
                var area = text
                area.size.height -= inset
                let frame = CTFramesetterCreateFrame(setter, CFRange(location: location, length: 0), CGPath(rect: area, transform: nil), nil)
                let visible = CTFrameGetVisibleStringRange(frame)
                guard visible.length > 0 else { endPage(); break }   // nothing fits (a giant unbreakable word); don't loop forever
                CTFrameDraw(frame, context)
                for chapter in section.chapters where chapter.offset >= location && chapter.offset < location + visible.length {
                    outlinePages.append((chapter.title, pageIndex))
                }
                drawFolio()
                endPage()
                location += visible.length
                first = false
            }
        }
        context.closePDF()

        guard let document = PDFDocument(data: output as Data), document.pageCount > 0 else { throw ExportError.couldNotBuild("the PDF could not be read back") }
        // A table of contents in the PDF sidebar, one entry per chapter.
        let root = PDFOutline()
        for (position, entry) in outlinePages.enumerated() {
            guard let target = document.page(at: min(entry.page, document.pageCount - 1)) else { continue }
            let item = PDFOutline()
            item.label = entry.title
            item.destination = PDFDestination(page: target, at: CGPoint(x: 0, y: page.height))
            root.insertChild(item, at: position)
        }
        document.outlineRoot = root
        document.documentAttributes = [PDFDocumentAttribute.titleAttribute: options.title, PDFDocumentAttribute.authorAttribute: options.author,
                                       PDFDocumentAttribute.creatorAttribute: "Sable Markdown Writer"]
        guard let final = document.dataRepresentation() else { throw ExportError.couldNotBuild("the PDF could not be finished") }
        return final
    }
}
