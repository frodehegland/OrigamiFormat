import Testing
import Foundation
@testable import OrigamiFormat

/// The reading half of the Origami profile's high-resolution addressing: a
/// note that names the passage's own id rather than the page it happened to
/// fall on, and a citation that carries that anchor to whoever is writing.
@Suite("Passage annotations")
struct PassageAnnotationTests {

    @Test("A passage note anchors to the unit, quotes the words, and says where it was")
    func passageNote() {
        let note = WebAnnotation.passageNote(
            "This is the load-bearing claim.",
            quoting: "The document conforms to the reader, not the reader to the document.",
            elementID: "P-DB45ABBC-AEBE-43F8-9083-E28E820C9A42",
            about: "urn:x-reader:abc", author: "A Reader",
            page: 3, prefix: "…dissolves it. ", suffix: " The timing is…")

        #expect(note.motivation == WebAnnotation.Motivation.commenting)
        #expect(note.anchorID == "P-DB45ABBC-AEBE-43F8-9083-E28E820C9A42")
        #expect(note.quotedText?.hasPrefix("The document conforms") == true)
        #expect(note.pageNumber == 3)
        // It is emphatically *not* a note about the whole document.
        #expect(!note.isAboutWholeDocument)
    }

    @Test("The anchor survives the JSON-LD round trip as a FragmentSelector")
    func roundTrip() throws {
        let note = WebAnnotation.passageNote(
            "Worth arguing with.", quoting: "an accident of typesetting",
            elementID: "P-1234", about: "https://doi.org/10.1145/3345001",
            author: nil)
        let data = try JSONEncoder().encode(note)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let target = try #require(json["target"] as? [String: Any])
        let selectors = try #require(target["selector"] as? [[String: Any]])

        let fragment = try #require(selectors.first { $0["type"] as? String == "FragmentSelector" })
        #expect(fragment["value"] as? String == "P-1234")
        // Conforming to Origami's own stable-id space, not a page scheme.
        #expect(fragment["conformsTo"] as? String == WebAnnotation.fragmentConformsTo)
        let quote = try #require(selectors.first { $0["type"] as? String == "TextQuoteSelector" })
        #expect(quote["exact"] as? String == "an accident of typesetting")

        let back = try JSONDecoder().decode(WebAnnotation.self, from: data)
        #expect(back.anchorID == "P-1234")
        #expect(back.quotedText == "an accident of typesetting")
    }

    @Test("A book with no ids still gets a note, quoting rather than anchoring")
    func noAnchor() {
        let note = WebAnnotation.passageNote("Still worth saying.",
                                             quoting: "some words",
                                             elementID: nil,
                                             about: "urn:x-reader:abc", author: nil)
        #expect(note.anchorID == nil)
        #expect(note.quotedText == "some words")
    }

    @Test("The citation block is the document's own entry plus the anchor")
    func citationBlock() {
        let entry = """
        @misc{doc-c15e5b1a2026,
          title = {Origami Text},
          author = {Frode Alexander Hegland},
          year = {2026},
        }
        """
        let block = WebAnnotation.citationBlock(bibtex: entry, anchor: "P-1234")
        // The invariant entry is intact…
        #expect(block.contains("@misc{doc-c15e5b1a2026,"))
        #expect(block.contains("title = {Origami Text},"))
        // …and the passage rides in one added field, inside the braces.
        #expect(block.contains("origami-anchor = {P-1234},"))
        #expect(block.hasSuffix("}"))
        #expect(block.filter { $0 == "}" }.count == entry.filter { $0 == "}" }.count + 1)
    }

    @Test("An entry with no trailing comma still gets valid BibTeX")
    func citationBlockCommaDiscipline() {
        let entry = "@misc{x,\n  title = {A}\n}"
        let block = WebAnnotation.citationBlock(bibtex: entry, anchor: "P-9")
        #expect(block.contains("title = {A},"))
        #expect(block.contains("origami-anchor = {P-9},"))
    }

    @Test("With no anchor the citation is the plain entry, unchanged")
    func citationBlockWithoutAnchor() {
        let entry = "@misc{x,\n  title = {A},\n}"
        #expect(WebAnnotation.citationBlock(bibtex: entry, anchor: nil) == entry)
        #expect(WebAnnotation.citationBlock(bibtex: entry, anchor: "") == entry)
    }

    @Test("The selection bridge reports the unit, not just the words")
    func selectionBridge() {
        let script = EPUBReadingStyle.selectionBridgeScript
        // The nearest ancestor carrying either id is the addressable unit.
        #expect(script.contains("getAttribute('data-id')"))
        #expect(script.contains("getAttribute('id')"))
        #expect(script.contains("messageHandlers.reader.postMessage"))
        // Context either side, so a note re-anchors when an id changes.
        #expect(script.contains("payload.before"))
        #expect(script.contains("payload.after"))
    }
}
