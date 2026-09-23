import Foundation
import NaturalLanguage

public enum WordClass: Int, CaseIterable, Sendable {
    case noun = 1, verb = 2, adjective = 4, adverb = 8, pronoun = 16
    public var label: String {
        switch self { case .noun: "Nouns"; case .verb: "Verbs"; case .adjective: "Adjectives"; case .adverb: "Adverbs"; case .pronoun: "Pronouns" }
    }
}
public struct TaggedWord {
    public let range: NSRange
    public let kind: WordClass
    /// The same word `delta` characters later, for a word after an edit.
    public func shifted(by delta: Int) -> TaggedWord { TaggedWord(range: NSRange(location: range.location + delta, length: range.length), kind: kind) }
}
public enum SentenceStructure {
    /// Every word class, for tagging once and choosing which classes to color afterwards.
    public static let allClasses = WordClass.allCases.reduce(0) { $0 | $1.rawValue }

    public static func words(in text: String, enabled: Int) -> [TaggedWord] {
        words(in: text, enabled: enabled, range: NSRange(location: 0, length: (text as NSString).length), spans: MarkdownSyntax.spans(in: text))
    }

    /// The words a whole-text pass tags inside `range` (whole lines), given the Markdown spans already found there. The
    /// tagger still reads the whole text, so a sentence is tagged the same however much of it is being restyled.
    public static func words(in text: String, enabled: Int, range: NSRange, spans: [MarkdownSpan]) -> [TaggedWord] {
        guard enabled != 0, range.length > 0, let bounds = Range(range, in: text) else { return [] }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        let excluded = merged(spans.flatMap { span -> [NSRange] in
            if case .code = span.kind { return [span.range] }
            return span.markers
        })
        var result: [TaggedWord] = []
        tagger.enumerateTags(in: bounds, unit: .word, scheme: .lexicalClass, options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            let kind: WordClass?
            switch tag { case .noun: kind = .noun; case .verb: kind = .verb; case .adjective: kind = .adjective; case .adverb: kind = .adverb; case .pronoun: kind = .pronoun; default: kind = nil }
            let nsRange = NSRange(range, in: text)
            if let kind, enabled & kind.rawValue != 0, !overlaps(nsRange, excluded) {
                result.append(TaggedWord(range: nsRange, kind: kind))
            }
            return true
        }
        return result
    }

    /// The ranges' union as sorted, disjoint ranges, so a word can be checked against them by binary search.
    private static func merged(_ ranges: [NSRange]) -> [NSRange] {
        var result: [NSRange] = []
        for range in ranges.filter({ $0.length > 0 }).sorted(by: { $0.location < $1.location }) {
            if let last = result.last, range.location <= NSMaxRange(last) {
                result[result.count - 1].length = max(NSMaxRange(last), NSMaxRange(range)) - last.location
            } else {
                result.append(range)
            }
        }
        return result
    }

    private static func overlaps(_ range: NSRange, _ sorted: [NSRange]) -> Bool {
        guard range.length > 0 else { return false }
        var low = 0, high = sorted.count
        while low < high {
            let middle = (low + high) / 2
            if NSMaxRange(sorted[middle]) <= range.location { low = middle + 1 } else { high = middle }
        }
        return low < sorted.count && sorted[low].location < NSMaxRange(range)
    }
}
