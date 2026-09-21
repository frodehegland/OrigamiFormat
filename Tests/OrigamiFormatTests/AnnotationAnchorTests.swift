import Testing
import Foundation
@testable import OrigamiFormat

/// The ladder, which Origami Text had and Reader did not: a note whose
/// anchor has moved should be found again, not lost.
@Suite("Anchoring ladder")
struct AnnotationAnchorTests {

    let document = [
        AnchoredParagraph(id: "P-1", text: "The document conforms to the reader, not the reader to the document."),
        AnchoredParagraph(id: "P-2", text: "A format that cannot say where something is has not said very much."),
        AnchoredParagraph(id: "P-3", text: "Typesetting is an accident; structure is a claim."),
    ]

    func note(_ selectors: [WebAnnotation.Selector]) -> WebAnnotation {
        WebAnnotation(motivation: WebAnnotation.Motivation.commenting,
                      target: .init(source: "urn:test", selectors: selectors))
    }

    @Test("The stable id alone lands on its unit")
    func byID() throws {
        let found = try #require(AnnotationAnchor.resolve(
            note([.fragment(value: "P-2", conformsTo: WebAnnotation.fragmentConformsTo)]),
            in: document))
        #expect(found.paragraphID == "P-2")
        #expect(found.method == .fragment)
        #expect(found.exact == nil)
    }

    @Test("The id and the words together give the highlight")
    func idAndWords() throws {
        let found = try #require(AnnotationAnchor.resolve(
            note([.fragment(value: "P-3", conformsTo: nil),
                  .quote(exact: "structure is a claim", prefix: nil, suffix: nil)]),
            in: document))
        #expect(found.method == .quoteInParagraph)
        #expect(found.exact == "structure is a claim")
    }

    @Test("When the id has gone, the words are found elsewhere")
    func reanchorsByQuote() throws {
        let found = try #require(AnnotationAnchor.resolve(
            note([.fragment(value: "P-GONE", conformsTo: nil),
                  .quote(exact: "not said very much", prefix: nil, suffix: nil)]),
            in: document))
        #expect(found.paragraphID == "P-2")
        #expect(found.method == .quoteInDocument)
    }

    @Test("Words that drifted a little are still matched, as the page writes them")
    func fuzzy() throws {
        // A later edit inserted a word; the note quotes the older reading.
        let edited = [AnchoredParagraph(id: "P-1", text: "Typesetting is a mere accident; structure is a claim.")]
        let found = try #require(AnnotationAnchor.resolve(
            note([.fragment(value: "P-1", conformsTo: nil),
                  .quote(exact: "Typesetting is an accident", prefix: nil, suffix: nil)]),
            in: edited))
        #expect(found.method == .quoteInParagraph)
        // The document's own words, not the note's stale copy.
        #expect(found.exact?.contains("mere") == true)
    }

    @Test("The id matches but the words are gone — unit scope stands, nothing breaks")
    func degradesToUnit() throws {
        let found = try #require(AnnotationAnchor.resolve(
            note([.fragment(value: "P-1", conformsTo: nil),
                  .quote(exact: "words that were deleted entirely", prefix: nil, suffix: nil)]),
            in: document))
        #expect(found.paragraphID == "P-1")
        #expect(found.method == .paragraph)
        #expect(found.exact == nil)
    }

    @Test("An orphan is nil rather than a wrong landing")
    func orphan() {
        #expect(AnnotationAnchor.resolve(
            note([.fragment(value: "P-GONE", conformsTo: nil),
                  .quote(exact: "nothing in this document says this", prefix: nil, suffix: nil)]),
            in: document) == nil)
    }

    @Test("A page selector anchors nothing and breaks nothing")
    func pageIsNotAnAnchor() throws {
        // The page says where the reader stood, not which words are meant.
        let found = try #require(AnnotationAnchor.resolve(
            note([.page(7),
                  .fragment(value: "P-2", conformsTo: nil)]),
            in: document))
        #expect(found.paragraphID == "P-2")
        #expect(AnnotationAnchor.resolve(note([.page(7)]), in: document) == nil)
    }

    @Test("A new target carries the whole ladder, with context either side")
    func buildsTheLadder() {
        let target = AnnotationAnchor.target(source: "urn:test", in: document,
                                             paragraphID: "P-1",
                                             exact: "not the reader")
        var sawFragment = false, sawQuote = false, sawPosition = false, sawProgression = false
        for selector in target.selectors {
            switch selector {
            case .fragment(let value, let conformsTo):
                sawFragment = true
                #expect(value == "P-1")
                #expect(conformsTo == WebAnnotation.fragmentConformsTo)
            case .quote(let exact, let prefix, let suffix):
                sawQuote = true
                #expect(exact == "not the reader")
                #expect(prefix?.isEmpty == false)
                #expect(suffix?.isEmpty == false)
            case .position(let start, let end):
                sawPosition = true
                #expect(end > start)
            case .progression(let fraction):
                sawProgression = true
                #expect(fraction == 0)
            case .page:
                Issue.record("a new passage target should not invent a page")
            }
        }
        #expect(sawFragment && sawQuote && sawPosition && sawProgression)
    }

    @Test("Short quotes stay exact — fuzziness on a few characters matches noise")
    func shortQuotesAreNotFuzzy() {
        #expect(AnnotationAnchor.fuzzyMatch("the", in: "there") == nil)
        #expect(AnnotationAnchor.fuzzyMatch("structure", in: "the structuer of it") != nil)
    }
}
