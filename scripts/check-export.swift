import Foundation
import PDFKit

@main enum ExportChecks {
    @discardableResult
    static func run(_ tool: String, _ args: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static func main() throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("quill-export-check-\(UUID())")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        // ---- Markdown reader
        let sample = """
        The harbor bell rang *twice* before **dawn**,
        which meant someone had lied.

        ## A Heading

        > Counting was how the harbor
        > kept its dead.

        - first item
        - second **bold** item
        1. numbered one

        ---

        ```
        code line
        ```

        Last paragraph with `code` and [a link](https://example.com) and ![img](x.png) gone. <!-- hidden -->
        """
        let blocks = MarkdownBlocks.parse(sample)
        precondition(blocks.count == 9, "Nine blocks: \(blocks.count) \(blocks)")
        if case let .paragraph(runs) = blocks[0] {
            precondition(MarkdownBlocks.plain(runs) == "The harbor bell rang twice before dawn, which meant someone had lied.", "Soft line breaks join: \(MarkdownBlocks.plain(runs))")
            precondition(runs.contains { $0.text == "twice" && $0.italic } && runs.contains { $0.text == "dawn" && $0.bold }, "Emphasis becomes runs")
        } else { preconditionFailure("first block is a paragraph") }
        precondition(blocks[1] == .heading(2, [ExportRun(text: "A Heading")]))
        if case let .quote(runs) = blocks[2] { precondition(MarkdownBlocks.plain(runs) == "Counting was how the harbor kept its dead.") } else { preconditionFailure("quote") }
        if case .bullet = blocks[3], case .bullet = blocks[4], case .numbered(1, _) = blocks[5] {} else { preconditionFailure("lists") }
        precondition(blocks[6] == .sceneBreak && blocks[7] == .code("code line"))
        if case let .paragraph(runs) = blocks[8] { precondition(MarkdownBlocks.plain(runs) == "Last paragraph with code and a link and  gone.", "Links keep words, images and comments vanish: \(MarkdownBlocks.plain(runs))") }
        for breakLine in ["---", "***", "___", "* * *", "- - -", "  ***  "] { precondition(MarkdownBlocks.isSceneBreak(breakLine.trimmingCharacters(in: .whitespaces)), breakLine) }
        for notBreak in ["--", "**bold**", "- item", "abc"] { precondition(!MarkdownBlocks.isSceneBreak(notBreak), notBreak) }

        // ---- Chapters from files
        let chapter = ManuscriptExport.chapter(named: "Chapter 3.md", markdown: "---\ncharacters: Marren\nlocation: The Pier\n---\n\n# The Crossing\n\nText here.\n")
        precondition(chapter.title == "The Crossing" && chapter.body == "Text here." && chapter.words == 2, "Tags dropped, title taken from the heading: \(chapter)")
        precondition(ManuscriptExport.chapter(named: "Epilogue.md", markdown: "No heading.\n").title == "Epilogue", "The file name is the fallback title")
        precondition(ManuscriptExport.chapter(named: "x.md", markdown: "Intro text\n\n# Later heading\n").title == "x", "Only a leading heading is the title")
        precondition(ManuscriptExport.fileName(for: "My: Novel/Draft?", format: .epub) == "My  Novel Draft.epub" && ManuscriptExport.fileName(for: "  ", format: .pdf) == "Manuscript.pdf")

        let project = try FictionProject.create(named: "Book", in: work, starterFiles: false)
        let manuscript = FictionProject.folder(for: .chapter, in: project)
        try "---\nlocation: The Pier\n---\n# One\n\nFirst chapter text.".write(to: manuscript.appendingPathComponent("Chapter 1.md"), atomically: true, encoding: .utf8)
        try "# Two\n\nSecond chapter text.".write(to: manuscript.appendingPathComponent("Chapter 2.md"), atomically: true, encoding: .utf8)
        try "# Three\n\nThird.".write(to: manuscript.appendingPathComponent("Chapter 3.md"), atomically: true, encoding: .utf8)
        try FictionProject.setChapterOrder(["Chapter 3.md", "Chapter 1.md", "Chapter 2.md"], in: project)
        precondition(ManuscriptExport.chapters(project: project).map(\.title) == ["Three", "One", "Two"], "Chapters come in the saved order")
        precondition(ManuscriptExport.chapters(project: project, include: ["Chapter 2.md", "Chapter 3.md"]).map(\.title) == ["Three", "Two"], "…and can be limited to a selection")
        precondition(ManuscriptExport.chapters(project: project).allSatisfy { !$0.body.contains("---") && !$0.body.contains("location") }, "Tag blocks never reach the export")

        // ---- Zip container
        var zip = ZipWriter()
        zip.add("mimetype", "application/epub+zip")
        zip.add("dir/hello.txt", "héllo wörld — 日本語")
        zip.add("empty.txt", "")
        let zipURL = work.appendingPathComponent("test.zip")
        try zip.finish().write(to: zipURL)
        precondition(run("/usr/bin/unzip", ["-tq", zipURL.path]).status == 0, "unzip accepts the archive: \(run("/usr/bin/unzip", ["-t", zipURL.path]).output)")
        precondition(run("/usr/bin/unzip", ["-p", zipURL.path, "dir/hello.txt"]).output == "héllo wörld — 日本語", "Contents survive, UTF-8 included")
        precondition(ZipWriter.crc32(Data("123456789".utf8)) == 0xCBF43926, "CRC-32 matches the standard check value")

        // ---- Bigger, realistic chapters for the paged formats
        func paragraphs(_ n: Int, seed: String) -> String {
            (0..<n).map { i in "\(seed) paragraph \(i): The harbor bell rang twice before dawn, which meant someone had lied about the tide, and Marren pulled her coat tight and went down to the water anyway; “quoted speech,” she said — an em dash, an ellipsis… and unicode: café, naïve, 日本語." }.joined(separator: "\n\n")
        }
        let chapters = (1...5).map { ExportChapter(name: "Chapter \($0).md", title: "Chapter \($0): The Title & More <Tags>", body: paragraphs(14, seed: "C\($0)") + "\n\n---\n\n*Italic ending* and **bold ending**.") }
        var options = ExportOptions()
        options.title = "The Crossing & Other <Stories>"
        options.author = "Marren Vale"
        options.pageSize = .letter

        // ---- EPUB
        options.format = .epub
        let epub = try ManuscriptExport.export(chapters, options: options)
        let epubURL = work.appendingPathComponent("book.epub")
        try epub.write(to: epubURL)
        precondition(run("/usr/bin/unzip", ["-tq", epubURL.path]).status == 0, "The EPUB is a valid archive")
        let listing = run("/usr/bin/unzip", ["-Z1", epubURL.path]).output.split(separator: "\n").map(String.init)
        precondition(listing.first == "mimetype", "mimetype must be the first entry: \(listing)")
        precondition(run("/usr/bin/unzip", ["-Zv", epubURL.path]).output.contains("compression method:                             none (stored)"), "…and stored uncompressed")
        precondition(run("/usr/bin/unzip", ["-p", epubURL.path, "mimetype"]).output == "application/epub+zip")
        let epubDir = work.appendingPathComponent("epub")
        precondition(run("/usr/bin/unzip", ["-q", epubURL.path, "-d", epubDir.path]).status == 0)
        for file in ["META-INF/container.xml", "OEBPS/content.opf", "OEBPS/nav.xhtml", "OEBPS/title.xhtml", "OEBPS/chapter001.xhtml", "OEBPS/chapter005.xhtml"] {
            let lint = run("/usr/bin/xmllint", ["--noout", epubDir.appendingPathComponent(file).path])
            precondition(lint.status == 0, "\(file) is well-formed XML: \(lint.output)")
        }
        let opf = try String(contentsOf: epubDir.appendingPathComponent("OEBPS/content.opf"), encoding: .utf8)
        precondition(opf.contains("<dc:title>The Crossing &amp; Other &lt;Stories&gt;</dc:title>") && opf.contains("<dc:creator>Marren Vale</dc:creator>") && opf.contains("dcterms:modified"))
        for index in 1...5 { precondition(opf.contains("<itemref idref=\"c\(index)\"/>") && fm.fileExists(atPath: epubDir.appendingPathComponent(String(format: "OEBPS/chapter%03d.xhtml", index)).path)) }
        let nav = try String(contentsOf: epubDir.appendingPathComponent("OEBPS/nav.xhtml"), encoding: .utf8)
        precondition(nav.contains("Chapter 1: The Title &amp; More &lt;Tags&gt;") && nav.contains("chapter005.xhtml"), "The contents list every chapter, escaped")
        let ch1 = try String(contentsOf: epubDir.appendingPathComponent("OEBPS/chapter001.xhtml"), encoding: .utf8)
        precondition(ch1.contains("<em>Italic ending</em>") && ch1.contains("<strong>bold ending</strong>") && ch1.contains("class=\"scenebreak\">* * *</p>") && ch1.contains("café"), "Formatting, scene breaks, and unicode carry over")
        options.titlePage = false
        let bare = try ManuscriptExport.export(Array(chapters.prefix(1)), options: options)
        precondition(run("/usr/bin/unzip", ["-Z1", { let u = work.appendingPathComponent("bare.epub"); try? bare.write(to: u); return u.path }()]).output.contains("title.xhtml") == false, "No title page when turned off")
        options.titlePage = true

        // ---- Word
        for style in ExportStyle.allCases {
            options.format = .docx
            options.style = style
            let docx = try ManuscriptExport.export(chapters, options: options)
            let docxURL = work.appendingPathComponent("book-\(style.rawValue).docx")
            try docx.write(to: docxURL)
            precondition(run("/usr/bin/unzip", ["-tq", docxURL.path]).status == 0, "The .docx is a valid archive")
            let dir = work.appendingPathComponent("docx-\(style.rawValue)")
            precondition(run("/usr/bin/unzip", ["-q", docxURL.path, "-d", dir.path]).status == 0)
            for file in ["[Content_Types].xml", "_rels/.rels", "word/document.xml", "word/styles.xml", "word/_rels/document.xml.rels", "docProps/core.xml", style == .manuscript ? "word/header1.xml" : "word/footer1.xml"] {
                let lint = run("/usr/bin/xmllint", ["--noout", dir.appendingPathComponent(file).path])
                precondition(lint.status == 0, "\(file) (\(style.rawValue)) is well-formed XML: \(lint.output)")
            }
            // macOS's own Word reader must open it and find our words
            let txt = work.appendingPathComponent("book-\(style.rawValue).txt")
            let converted = run("/usr/bin/textutil", ["-convert", "txt", "-output", txt.path, docxURL.path])
            precondition(converted.status == 0, "textutil opens the .docx: \(converted.output)")
            let plain = try String(contentsOf: txt, encoding: .utf8)
            precondition(plain.contains("The Crossing & Other <Stories>") && plain.contains("by Marren Vale"), "Title page text (\(style.rawValue))")
            precondition(plain.contains("Chapter 1: The Title & More <Tags>") && plain.contains("Chapter 5: The Title & More <Tags>"), "Every chapter title is there")
            precondition(plain.contains("C3 paragraph 7: The harbor bell rang twice") && plain.contains("“quoted speech,”") && plain.contains("café") && plain.contains("日本語"), "Body text and unicode survive")
            precondition(plain.contains("* * *") && plain.contains("Italic ending"), "Scene breaks and closing lines")
            let document = try String(contentsOf: dir.appendingPathComponent("word/document.xml"), encoding: .utf8)
            precondition(document.contains("<w:i/>") && document.contains("<w:b/>") && document.contains("w:pageBreakBefore"), "Italic, bold, and chapter page breaks")
            precondition(document.contains("w:w=\"12240\" w:h=\"15840\""), "Letter page size")
        }
        options.pageSize = .a4
        options.style = .manuscript
        let a4 = try ManuscriptExport.export(Array(chapters.prefix(1)), options: options)
        let a4URL = work.appendingPathComponent("a4.docx"); try a4.write(to: a4URL)
        precondition(run("/usr/bin/unzip", ["-p", a4URL.path, "word/document.xml"]).output.contains("w:w=\"11905\" w:h=\"16837\""), "A4 page size")
        options.pageSize = .letter

        // ---- PDF
        options.format = .pdf
        for style in ExportStyle.allCases {
            options.style = style
            let pdfData = try ManuscriptExport.export(chapters, options: options)
            guard let pdf = PDFDocument(data: pdfData) else { preconditionFailure("The PDF can't be read back (\(style.rawValue))") }
            precondition(pdf.pageCount >= 8, "\(style.rawValue): five long chapters plus a title page make many pages: \(pdf.pageCount)")
            let first = pdf.page(at: 0)?.string ?? ""
            precondition(first.contains("The Crossing & Other <Stories>") && first.contains("Marren Vale"), "\(style.rawValue): title page: \(first.prefix(120))")
            precondition(!(pdf.page(at: 1)?.string ?? "").contains("by Marren Vale"), "The title page stands alone: the byline appears once")
            // Each chapter starts a new page, and the sidebar outline points at those pages
            let outline = pdf.outlineRoot
            precondition(outline?.numberOfChildren == 5, "\(style.rawValue): outline has a line per chapter: \(outline?.numberOfChildren ?? -1)")
            var previous = 0
            for index in 0..<5 {
                guard let item = outline?.child(at: index), let page = item.destination?.page else { preconditionFailure("outline destination \(index)") }
                let at = pdf.index(for: page)
                precondition(at > previous, "\(style.rawValue): outline entries move forward through the book")
                precondition((page.string ?? "").hasPrefix("Chapter \(index + 1)") || (page.string ?? "").contains("Chapter \(index + 1): The Title"), "\(style.rawValue): chapter \(index + 1) begins on its outline page: \((page.string ?? "").prefix(60))")
                previous = at
            }
            // Text wraps across lines and pages, so compare with whitespace collapsed.
            let all = (pdf.string ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            precondition(all.contains("café") && all.contains("本語") && all.contains("quoted speech"), "\(style.rawValue): text and unicode are real, selectable text")
            precondition(all.contains("* * *"), "Scene breaks appear")
            let size = pdf.page(at: 3)!.bounds(for: .mediaBox).size
            precondition(abs(size.width - 612) < 1 && abs(size.height - 792) < 1, "Letter size")
            precondition(pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == options.title && pdf.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String == options.author, "Title and author are stored in the PDF")
            // Page numbers: the first chapter page is 1, the last is one less than the total
            let firstChapterPage = pdf.page(at: 1)?.string ?? ""
            precondition(firstChapterPage.contains("1") && (pdf.page(at: pdf.pageCount - 1)?.string ?? "").contains("\(pdf.pageCount - 1)"), "\(style.rawValue): pages are numbered from the first chapter")
            if style == .manuscript { precondition(firstChapterPage.contains("Vale / The Crossing & Other <Stories> / 1"), "Running header: \(firstChapterPage.suffix(80))") }
        }
        // Chapters that run on, without page breaks, make a shorter book
        options.style = .book
        options.chapterPageBreaks = true
        let broken = PDFDocument(data: try ManuscriptExport.export(chapters, options: options))!.pageCount
        options.chapterPageBreaks = false
        let runOn = PDFDocument(data: try ManuscriptExport.export(chapters, options: options))!
        precondition(runOn.pageCount <= broken && runOn.outlineRoot?.numberOfChildren == 5, "Running chapters together never adds pages: \(runOn.pageCount) vs \(broken)")
        let runOnText = (runOn.string ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        for index in 0..<5 { precondition(runOnText.contains("Chapter \(index + 1): The Title"), "Every chapter is present when chapters run on") }
        options.chapterPageBreaks = true
        // A4, no title page
        options.pageSize = .a4; options.titlePage = false
        let a4pdf = PDFDocument(data: try ManuscriptExport.export(Array(chapters.prefix(2)), options: options))!
        precondition(abs(a4pdf.page(at: 0)!.bounds(for: .mediaBox).width - 595.28) < 1 && (a4pdf.page(at: 0)?.string ?? "").contains("Chapter 1"), "A4 with no title page starts on the first chapter")
        options.pageSize = .letter; options.titlePage = true

        // ---- Edge cases: empty chapter, no author, one word, an enormous unbreakable word, a bare title
        let odd = [ExportChapter(name: "a.md", title: "Empty", body: ""), ExportChapter(name: "b.md", title: "One", body: "Word"),
                   ExportChapter(name: "c.md", title: "Long", body: String(repeating: "x", count: 4000)), ExportChapter(name: "d.md", title: "Emoji", body: "Fine 🙂 text")]
        options.author = ""
        for format in ExportFormat.allCases {
            options.format = format
            let out = try ManuscriptExport.export(odd, options: options)
            precondition(out.count > 100, "\(format.title) handles awkward chapters")
            if format == .pdf { precondition(PDFDocument(data: out)?.pageCount ?? 0 >= 3) }
        }
        do { _ = try ManuscriptExport.export([], options: options); preconditionFailure() } catch ExportError.nothingToExport {}
        options.format = .markdown
        options.author = "Marren Vale"
        let md = String(decoding: try ManuscriptExport.export(Array(chapters.prefix(2)), options: options), as: UTF8.self)
        precondition(md.hasPrefix("# The Crossing & Other <Stories>\n\n*by Marren Vale*") && md.contains("## Chapter 2: The Title & More <Tags>") && md.hasSuffix("\n"), "Combined Markdown reads cleanly")
        print("Passed: Markdown reading, chapter loading and order, zip container, EPUB (valid archive/XML/structure), Word (opens in macOS, both styles), PDF (pages, outline, numbering, run-on chapters, A4), and edge cases.")
    }
}
