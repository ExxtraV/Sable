import AppKit
import SwiftUI
import QuillCore

// How long one keystroke takes in a long single-file manuscript, from the key reaching the text view to the page being
// drawn again, at 10k, 50k, and 100k words. The editor is hosted the way the app hosts it (scroll view, clip view, the
// real NativeEditor.Coordinator with a stand-in for the SwiftUI binding), in an offscreen window.
//
//   --smoke                  10k words and a few keystrokes, only to prove it still builds and runs (CI)
//   --sizes 10000,50000      choose the manuscript sizes
//   --out <file.md>          also write the results as Markdown
//   --write-fixture <path>   write the 100k-word manuscript to a file (to open in Sable by hand) and stop
//
// Build it with -O, like the app. Timings vary from machine to machine; compare runs on the same Mac.

@main enum TypingBenchmark {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
        func value(after flag: String) -> String? {
            arguments.firstIndex(of: flag).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
        }
        if let path = value(after: "--write-fixture") {
            let text = ManuscriptFixture.novel(words: 100_000)
            do { try text.write(toFile: path, atomically: true, encoding: .utf8) } catch { print("Could not write \(path): \(error)"); exit(1) }
            print("Wrote \(Prose.wordCount(text)) words to \(path)")
            return
        }
        let smoke = arguments.contains("--smoke")
        let sizes = value(after: "--sizes")?.split(separator: ",").compactMap { Int($0) } ?? (smoke ? [10_000] : [10_000, 50_000, 100_000])
        let profiles: [(String, EditorSettings)] = [("defaults", .defaults), ("everything on", .everything)]

        var report = "# Typing benchmark\n\n\(machine())\n"
        for (name, settings) in profiles {
            report += "\n## Per keystroke, \(name)\n\n"
            report += "Milliseconds. *Edit* is `insertText` through the delegate (restyle, focus, caret centering), "
                + "including the layout AppKit does to keep the caret in view; *layout* finishes laying out the visible page; "
                + "*draw* draws it. *Binding flush* hands the typing to SwiftUI's copy of the text with the status bar's counts; "
                + "the editor does that after a pause, not per keystroke, so it isn't in the total. *Region passes* counts the "
                + "keystrokes that restyled only the lines around the edit.\n\n"
            report += "| Words | Characters | Edit (median) | Layout (median) | Draw (median) | Total median | Total p90 | Total max | Binding flush (median) | Region passes | Full restyle |\n"
            report += "|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n"
            for size in sizes {
                let keystrokes = smoke ? 3 : (size <= 10_000 ? 30 : (size <= 50_000 ? 15 : 10))
                report += keystrokeRow(words: size, settings: settings, keystrokes: keystrokes, warmUp: smoke ? 1 : 3) + "\n"
                print("measured \(name) at \(size) words")
            }
        }
        report += "\n## Whole-document passes\n\n"
        report += "Milliseconds, median, each over the whole text. A full restyle (a new file or a setting change) runs them; "
            + "before incremental styling every keystroke did, and the SwiftUI side also ran `Prose.wordCount` about three "
            + "times and `Prose.suggestions` once per keystroke. The last column is the compare and copy the binding used to do "
            + "per keystroke.\n\n"
        report += "| Words | Markdown spans | Sentence colors (all) | Names | Prose suggestions | Focus paragraph | Word count | Binding compare + copy |\n"
        report += "|---:|---:|---:|---:|---:|---:|---:|---:|\n"
        for size in sizes { report += passesRow(words: size, repeats: smoke ? 1 : (size <= 10_000 ? 7 : 3)) + "\n" }
        print("\n" + report)
        if let path = value(after: "--out") {
            do { try report.write(toFile: path, atomically: true, encoding: .utf8) } catch { print("Could not write \(path): \(error)"); exit(1) }
        }
    }

    // MARK: Measuring

    private static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
    private static func milliseconds(_ start: UInt64, _ end: UInt64) -> Double { Double(end - start) / 1_000_000 }
    private static func format(_ value: Double) -> String { value < 10 ? String(format: "%.2f", value) : String(format: "%.1f", value) }
    private static func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
    private static func p90(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[max(0, Int((Double(sorted.count) * 0.9).rounded(.up)) - 1)]
    }

    /// A caret in the middle of the manuscript, just after "the " in a sentence of prose.
    private static func middleCaret(in text: String) -> Int {
        let source = text as NSString
        let from = source.length / 2
        let found = source.range(of: " the ", range: NSRange(location: from, length: source.length - from))
        return found.location == NSNotFound ? from : found.location + 5
    }

    @MainActor private static func keystrokeRow(words: Int, settings: EditorSettings, keystrokes: Int, warmUp: Int) -> String {
        let text = ManuscriptFixture.novel(words: words)
        let host = HostedEditor(text: text, settings: settings)
        let editor = host.editor
        guard let layout = editor.layoutManager, let container = editor.textContainer else { fatalError("The editor has no layout") }
        func visibleArea() -> NSRect { editor.visibleRect.offsetBy(dx: -editor.textContainerOrigin.x, dy: -editor.textContainerOrigin.y) }
        // The window is never on screen, so draw the visible page into a bitmap to make AppKit really draw it.
        func drawPage() {
            let bounds = host.scroll.bounds
            guard let bitmap = host.scroll.bitmapImageRepForCachingDisplay(in: bounds) else { return }
            host.scroll.cacheDisplay(in: bounds, to: bitmap)
        }
        editor.setSelectedRange(NSRange(location: middleCaret(in: text), length: 0))
        editor.scrollRangeToVisible(editor.selectedRange())
        host.flush()
        layout.ensureLayout(forBoundingRect: visibleArea(), in: container)
        drawPage()

        let letters = Array("tide ")
        var edit: [Double] = [], lay: [Double] = [], draw: [Double] = [], total: [Double] = [], flush: [Double] = []
        var regionPasses = 0
        for index in 0..<(warmUp + keystrokes) {
            let regionsBefore = editor.style.regionPasses
            let start = now()
            host.edit { editor.insertText(String(letters[index % letters.count]), replacementRange: NSRange(location: NSNotFound, length: 0)) }
            let edited = now()
            layout.ensureLayout(forBoundingRect: visibleArea(), in: container)
            let laidOut = now()
            drawPage()
            let drawn = now()
            host.commitText()
            let flushed = now()
            host.flush()
            guard index >= warmUp else { continue }
            if editor.style.regionPasses > regionsBefore { regionPasses += 1 }
            flush.append(milliseconds(drawn, flushed))
            edit.append(milliseconds(start, edited))
            lay.append(milliseconds(edited, laidOut))
            draw.append(milliseconds(laidOut, drawn))
            total.append(milliseconds(start, drawn))
        }
        precondition(host.text == editor.string, "The binding kept up with the editor")

        // A setting change restyles everything; this is what theme, font, and size changes cost.
        var changed = settings
        changed.colorVersion += 1
        let restyleStart = now()
        host.apply(changed)
        layout.ensureLayout(forBoundingRect: visibleArea(), in: container)
        drawPage()
        let restyle = milliseconds(restyleStart, now())

        let characters = (text as NSString).length
        let cells = [median(edit), median(lay), median(draw), median(total), p90(total), total.max() ?? 0, median(flush)].map(format)
            + ["\(regionPasses) of \(keystrokes)", format(restyle)]
        return "| \(Prose.wordCount(text)) | \(characters) | " + cells.joined(separator: " | ") + " |"
    }

    @MainActor private static func passesRow(words: Int, repeats: Int) -> String {
        let text = ManuscriptFixture.novel(words: words)
        let highlighter = ManuscriptFixture.highlighter
        let allClasses = WordClass.allCases.reduce(0) { $0 | $1.rawValue }
        let caret = middleCaret(in: text)
        let view = NSTextView(frame: .zero)
        view.string = text
        func time(_ work: () -> Void) -> String {
            var runs: [Double] = []
            for _ in 0..<repeats {
                let start = now()
                work()
                runs.append(milliseconds(start, now()))
            }
            return format(median(runs))
        }
        var sink = 0
        var binding = String(decoding: Array(text.utf8), as: UTF8.self) // SwiftUI's own copy, not the same storage
        let cells = [
            time { sink &+= MarkdownSyntax.spans(in: text).count },
            time { sink &+= SentenceStructure.words(in: text, enabled: allClasses).count },
            time { sink &+= highlighter.matches(in: text).count },
            time { sink &+= Prose.suggestions(in: text, words: Prose.defaultWords).count },
            time { sink &+= FocusParagraph.range(in: text, caret: caret).length },
            time { sink &+= Prose.wordCount(text) },
            // What the coordinator does per keystroke: compare the binding with the editor's string, then hand it over.
            time {
                if binding != view.string { sink &+= 1 }
                binding = view.string
                sink &+= binding.utf16.count
            }
        ]
        precondition(sink != 0)
        return "| \(Prose.wordCount(text)) | " + cells.joined(separator: " | ") + " |"
    }

    // MARK: Machine

    private static func sysctl(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "?" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "?" }
        return String(cString: buffer)
    }

    private static func machine() -> String {
        let memory = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
        return "\(sysctl("hw.model")), \(sysctl("machdep.cpu.brand_string")), \(memory) GB, "
            + "\(ProcessInfo.processInfo.operatingSystemVersionString), \(ProcessInfo.processInfo.activeProcessorCount) cores"
    }
}
