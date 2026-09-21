import Testing
import Foundation
@testable import OrigamiFormat

/// A book's package document is the only thing Reader reads to catalogue it,
/// so the small amount of XML it understands has to be right.
@Suite("EPUB metadata")
struct EPUBMetadataTests {

    private let opf = """
    <?xml version="1.0" encoding="UTF-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:title>Folding the Page &amp; Other Essays</dc:title>
        <dc:creator id="a1">Frode Hegland</dc:creator>
        <dc:creator id="a2">Doug Engelbart</dc:creator>
        <dc:date>2026-09-04</dc:date>
        <dc:publisher>Future Text</dc:publisher>
        <dc:identifier id="pub-id">urn:isbn:9780306406157</dc:identifier>
        <dc:language>en</dc:language>
      </metadata>
    </package>
    """

    @Test("Every creator is read, in the order the book lists them")
    func creators() {
        #expect(EPUBMetadata.allTagText(in: opf, tag: "dc:creator")
                == ["Frode Hegland", "Doug Engelbart"])
    }

    @Test("Entities in a title are resolved")
    func titleEntities() {
        #expect(EPUBMetadata.firstTagText(in: opf, tag: "dc:title")
                == "Folding the Page & Other Essays")
    }

    @Test("A missing element is nil rather than empty")
    func missingElement() {
        #expect(EPUBMetadata.firstTagText(in: opf, tag: "dc:subject") == nil)
    }

    @Test("An ISBN identifier is recognised; a UUID one is not")
    func identifiers() {
        let isbn = EPUBMetadata(title: nil, creators: [], date: nil, publisher: nil,
                                identifier: "urn:isbn:9780306406157", language: nil)
        #expect(isbn.isbn == "9780306406157")
        #expect(isbn.doi == nil)

        let uuid = EPUBMetadata(title: nil, creators: [], date: nil, publisher: nil,
                                identifier: "urn:uuid:7D6224BC-42A8-5B7F-AA6A-BAD6639B52B0",
                                language: nil)
        #expect(uuid.isbn == nil)

        let doi = EPUBMetadata(title: nil, creators: [], date: nil, publisher: nil,
                               identifier: "https://doi.org/10.1145/3345001", language: nil)
        #expect(doi.doi == "10.1145/3345001")
    }

    @Test("A file that is not a zip is not an EPUB, and never throws at the caller")
    func notAnEPUB() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("not-a-book-\(UUID().uuidString).epub")
        try Data("plain text, not a package".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(EPUBMetadata.read(at: url) == nil)
    }
}
