import Testing
import Foundation
@testable import OrigamiFormat

/// The document annotation is only useful if it is really W3C: another
/// reader has to recognise the shape without knowing anything about Reader.
@Suite("Web annotations")
struct WebAnnotationTests {

    private func encoded(_ annotation: WebAnnotation) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(annotation)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("A document note encodes as JSON-LD the model describes")
    func documentNoteIsJSONLD() throws {
        let note = WebAnnotation.documentNote("A careful re-reading.",
                                              about: "urn:x-reader:abc",
                                              author: "A Reader")
        let json = try encoded(note)
        #expect(json["@context"] as? String == "http://www.w3.org/ns/anno.jsonld")
        #expect(json["type"] as? String == "Annotation")
        #expect(json["motivation"] as? String == "describing")
        let body = try #require(json["body"] as? [String: Any])
        #expect(body["type"] as? String == "TextualBody")
        #expect(body["value"] as? String == "A careful re-reading.")
        #expect(body["format"] as? String == "text/plain")
        let target = try #require(json["target"] as? [String: Any])
        #expect(target["source"] as? String == "urn:x-reader:abc")
        // No selectors at all: the target is the document itself.
        #expect(target["selector"] == nil)
        // `created` is an ISO-8601 instant, not a Foundation number.
        let created = try #require(json["created"] as? String)
        #expect(WebAnnotation.parseISO8601(created) != nil)
    }

    @Test("The page a note was written on travels as a PDF fragment selector")
    func pageTravelsAsFragment() throws {
        let note = WebAnnotation.documentNote("On the train.", about: "urn:x-reader:abc",
                                              author: nil, page: 7)
        let json = try encoded(note)
        let target = try #require(json["target"] as? [String: Any])
        let selectors = try #require(target["selector"] as? [[String: Any]])
        #expect(selectors.count == 1)
        #expect(selectors[0]["type"] as? String == "FragmentSelector")
        #expect(selectors[0]["value"] as? String == "page=7")
        // A page says where the reader stood, not what the note is about, so
        // the note is still about the whole document.
        #expect(note.isAboutWholeDocument)
        #expect(note.pageNumber == 7)
    }

    @Test("Where a note was written survives the round trip")
    func placeRoundTrips() throws {
        let note = WebAnnotation.documentNote(
            "Read by the river.", about: "urn:x-reader:abc", author: "A Reader",
            place: WebAnnotation.Place(name: "London, United Kingdom",
                                       latitude: 51.5072, longitude: -0.1276),
            page: 3)
        let data = try JSONEncoder().encode(note)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let place = try #require(json["reader:place"] as? [String: Any])
        #expect(place["type"] as? String == "Place")
        #expect(place["name"] as? String == "London, United Kingdom")

        let back = try JSONDecoder().decode(WebAnnotation.self, from: data)
        #expect(back.place?.name == "London, United Kingdom")
        #expect(back.place?.latitude == 51.5072)
        #expect(back.pageNumber == 3)
        #expect(back.creator?.name == "A Reader")
        #expect(back.text == "Read by the river.")
    }

    @Test("A DOI names the document to the world; without one, a URN names the card")
    func sourceIRI() {
        #expect(WebAnnotation.source(forRecordID: "abc", doi: "10.1145/3345001")
                == "https://doi.org/10.1145/3345001")
        #expect(WebAnnotation.source(forRecordID: "abc", doi: "https://doi.org/10.1145/3345001")
                == "https://doi.org/10.1145/3345001")
        // Without a DOI the name is the shared one, not Reader's own — see
        // `DocumentIdentity`. A record id with no file behind it is a local
        // name; a record id that is a content hash says so.
        #expect(WebAnnotation.source(forRecordID: "abc", doi: nil) == "urn:origami:local:abc")
        #expect(WebAnnotation.source(forRecordID: "abc", doi: "  ") == "urn:origami:local:abc")
        let hash = String(repeating: "a1b2c3d4", count: 8)
        #expect(WebAnnotation.source(forRecordID: hash, doi: nil) == "urn:origami:sha256:" + hash)
        // Sidecars already on disk name the same documents as before.
        #expect(DocumentIdentity.isSameDocument(
            WebAnnotation.source(forRecordID: "abc", doi: nil), "urn:x-reader:abc"))
        #expect(DocumentIdentity.isSameDocument(
            WebAnnotation.source(forRecordID: hash, doi: nil), "urn:x-reader:" + hash))
    }

    @Test("A highlight with quoted words is not mistaken for a document note")
    func quoteIsNotADocumentNote() {
        let onWords = WebAnnotation(
            motivation: WebAnnotation.Motivation.highlighting,
            target: WebAnnotation.Target(source: "urn:x-reader:abc",
                                         selectors: [.quote(exact: "the words",
                                                            prefix: nil, suffix: nil)]))
        #expect(!onWords.isAboutWholeDocument)
        #expect(onWords.quotedText == "the words")
    }

    @Test("A sidecar is a W3C AnnotationCollection, and goes when its last note goes")
    func sidecarRoundTrip() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("annotation-tests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }

        let note = WebAnnotation.documentNote("Kept.", about: "urn:x-reader:abc",
                                              author: "A Reader", page: 2)
        #expect(AnnotationStore.append(note, for: "abc", in: folder))

        let loaded = AnnotationStore.load(for: "abc", in: folder)
        #expect(loaded.count == 1)
        #expect(loaded.first?.text == "Kept.")

        let data = try #require(AnnotationStore.exportData(for: "abc", in: folder))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["type"] as? String == "AnnotationCollection")
        #expect(json["total"] as? Int == 1)

        #expect(AnnotationStore.loadAll(in: folder)["abc"]?.count == 1)

        #expect(AnnotationStore.remove(id: note.id, for: "abc", in: folder))
        #expect(AnnotationStore.load(for: "abc", in: folder).isEmpty)
        #expect(!FileManager.default.fileExists(
            atPath: AnnotationStore.fileURL(for: "abc", in: folder).path))
    }

    @Test("One unreadable annotation does not sink the sidecar")
    func lossyDecoding() throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("annotation-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let sidecar = """
        {
          "@context": "http://www.w3.org/ns/anno.jsonld",
          "type": "AnnotationCollection",
          "total": 2,
          "items": [
            { "nonsense": true },
            { "id": "urn:uuid:1", "type": "Annotation", "motivation": "describing",
              "created": "2026-09-20T10:00:00Z",
              "body": { "type": "TextualBody", "value": "Still here." },
              "target": { "source": "urn:x-reader:abc" } }
          ]
        }
        """
        try Data(sidecar.utf8).write(to: AnnotationStore.fileURL(for: "abc", in: folder))

        let loaded = AnnotationStore.load(for: "abc", in: folder)
        #expect(loaded.count == 1)
        #expect(loaded.first?.text == "Still here.")
    }
}
