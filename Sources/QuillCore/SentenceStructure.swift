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
}
public enum SentenceStructure {
    public static func words(in text: String, enabled: Int) -> [TaggedWord] {
        guard enabled != 0 else { return [] }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        let spans = MarkdownSyntax.spans(in: text)
        let excluded = spans.flatMap { span -> [NSRange] in
            if case .code = span.kind { return [span.range] }
            return span.markers
        }
        var result: [TaggedWord] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            let kind: WordClass?
            switch tag { case .noun: kind = .noun; case .verb: kind = .verb; case .adjective: kind = .adjective; case .adverb: kind = .adverb; case .pronoun: kind = .pronoun; default: kind = nil }
            let nsRange = NSRange(range, in: text)
            if let kind, enabled & kind.rawValue != 0, !excluded.contains(where: { NSIntersectionRange($0, nsRange).length > 0 }) {
                result.append(TaggedWord(range: nsRange, kind: kind))
            }
            return true
        }
        return result
    }
}
