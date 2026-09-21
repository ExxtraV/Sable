import Foundation

/// Find and replace across every Markdown file in a folder, with a way back.
struct SearchOptions: Equatable {
    var query = ""
    var caseSensitive = false
    var wholeWord = false
}

struct SearchHit: Identifiable, Equatable {
    let id = UUID()
    let line: Int
    /// The line the match is on, shortened around the match.
    let snippet: String
    let range: NSRange
    /// Where the match sits in `snippet`, for showing it in bold.
    let snippetRange: NSRange
}

struct FileHits: Identifiable, Equatable {
    var id: URL { url }
    let url: URL
    let path: String
    let hits: [SearchHit]
}

/// What a replacement changed, so it can be taken back.
struct ReplaceReceipt {
    var originals: [URL: String] = [:]
    var replacements = 0
    var files: Int { originals.count }
}

enum ProjectSearch {
    static let fileExtensions: Set<String> = ["md", "markdown"]
    static let hitLimit = 5000

    static func expression(for options: SearchOptions) -> NSRegularExpression? {
        let query = options.query
        guard !query.isEmpty else { return nil }
        var pattern = NSRegularExpression.escapedPattern(for: query)
        if options.wholeWord { pattern = "(?<![\\p{L}\\p{N}_])" + pattern + "(?![\\p{L}\\p{N}_])" }
        return try? NSRegularExpression(pattern: pattern, options: options.caseSensitive ? [] : [.caseInsensitive])
    }

    /// Every Markdown file below `root`, skipping hidden files and folders.
    static func markdownFiles(in root: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var files: [URL] = []
        for case let url as URL in walker where fileExtensions.contains(url.pathExtension.lowercased()) {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            if size < 8_000_000 { files.append(url) }
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// The matches in one piece of text.
    static func hits(in text: String, options: SearchOptions) -> [SearchHit] {
        guard let expression = expression(for: options) else { return [] }
        let ns = text as NSString
        var result: [SearchHit] = []
        var lineNumber = 1, scanned = 0
        for match in expression.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            if result.count >= hitLimit { break }
            // Count lines up to this match without rescanning the whole text each time.
            if match.range.location > scanned {
                lineNumber += ns.substring(with: NSRange(location: scanned, length: match.range.location - scanned)).filter { $0 == "\n" }.count
                scanned = match.range.location
            }
            var start = 0, end = 0, contentsEnd = 0
            ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: match.range)
            var lineRange = NSRange(location: start, length: contentsEnd - start)
            // Keep the snippet short: a window around the match.
            let window = 70
            let from = max(lineRange.location, match.range.location - window)
            let to = min(NSMaxRange(lineRange), NSMaxRange(match.range) + window)
            lineRange = NSRange(location: from, length: to - from)
            var snippet = ns.substring(with: lineRange)
            var inSnippet = NSRange(location: match.range.location - from, length: match.range.length)
            if from > start { snippet = "…" + snippet; inSnippet.location += 1 }
            if to < contentsEnd { snippet += "…" }
            result.append(SearchHit(line: lineNumber, snippet: snippet, range: match.range, snippetRange: inSnippet))
        }
        return result
    }

    /// Searches every Markdown file below `root`. `liveText` supplies the text of files open with unsaved changes.
    static func find(in root: URL, options: SearchOptions, liveText: [URL: String] = [:]) -> [FileHits] {
        guard expression(for: options) != nil else { return [] }
        let rootPath = root.standardizedFileURL.path
        var results: [FileHits] = []
        var total = 0
        for url in markdownFiles(in: root) {
            let text = liveText[url.standardizedFileURL] ?? (try? String(contentsOf: url, encoding: .utf8))
            guard let text else { continue }
            let found = hits(in: text, options: options)
            guard !found.isEmpty else { continue }
            var path = url.standardizedFileURL.path
            if path.hasPrefix(rootPath + "/") { path = String(path.dropFirst(rootPath.count + 1)) }
            results.append(FileHits(url: url, path: path, hits: found))
            total += found.count
            if total >= hitLimit { break }
        }
        return results
    }

    /// `text` with every match replaced, and how many there were.
    static func replaced(_ text: String, options: SearchOptions, with replacement: String) -> (text: String, count: Int) {
        guard let expression = expression(for: options) else { return (text, 0) }
        let range = NSRange(location: 0, length: (text as NSString).length)
        let count = expression.numberOfMatches(in: text, range: range)
        guard count > 0 else { return (text, 0) }
        let result = expression.stringByReplacingMatches(in: text, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
        return (result, count)
    }

    /// Replaces in the given files on disk, remembering what each said before.
    static func replace(in files: [URL], options: SearchOptions, with replacement: String) throws -> ReplaceReceipt {
        var receipt = ReplaceReceipt()
        do {
            for url in files {
                let original = try String(contentsOf: url, encoding: .utf8)
                let outcome = replaced(original, options: options, with: replacement)
                guard outcome.count > 0 else { continue }
                try outcome.text.write(to: url, atomically: true, encoding: .utf8)
                receipt.originals[url] = original
                receipt.replacements += outcome.count
            }
        } catch {
            // Don't leave a half-done job: put back what was already changed.
            try? restore(receipt)
            throw error
        }
        return receipt
    }

    static func restore(_ receipt: ReplaceReceipt) throws {
        for (url, original) in receipt.originals { try original.write(to: url, atomically: true, encoding: .utf8) }
    }
}
