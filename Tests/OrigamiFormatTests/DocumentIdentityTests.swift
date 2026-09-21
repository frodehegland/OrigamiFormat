import Testing
import Foundation
@testable import OrigamiFormat

/// The bug these exist to prevent: Reader and Origami Text naming the same
/// book differently, so a reader's notes from the two apps are, to any
/// conforming consumer, notes about two unrelated resources.
@Suite("Document identity")
struct DocumentIdentityTests {

    let hash = String(repeating: "a1b2c3d4", count: 8)   // 64 hex characters

    @Test("A DOI wins — it is the name the world already has")
    func doiWins() {
        let iri = DocumentIdentity.canonical(doi: "10.1145/3345001",
                                             contentHash: hash,
                                             localName: "whatever")
        #expect(iri == "https://doi.org/10.1145/3345001")
    }

    @Test("A DOI is recognised however it was written down")
    func doiSpellings() {
        let forms = ["10.1145/3345001", "doi:10.1145/3345001",
                     "https://doi.org/10.1145/3345001",
                     "http://dx.doi.org/10.1145/3345001",
                     "  HTTPS://DOI.ORG/10.1145/3345001  "]
        let keys = Set(forms.map(DocumentIdentity.normalised))
        #expect(keys == ["doi:10.1145/3345001"])
    }

    @Test("Without a DOI the content hash names it, so two readers agree")
    func hashNames() {
        #expect(DocumentIdentity.canonical(contentHash: hash)
                == "urn:origami:sha256:" + hash)
    }

    @Test("Reader's existing sidecars join up with newly written ones")
    func readerMigration() {
        // Reader's record ids are content SHA-256s, so its historical URN
        // and the canonical one are the same document — no migration, no
        // orphaned notes.
        let old = "urn:x-reader:" + hash
        let new = DocumentIdentity.canonical(contentHash: hash)
        #expect(old != new)
        #expect(DocumentIdentity.isSameDocument(old, new))
    }

    @Test("A card with no file keeps its local name rather than a false hash")
    func recordWithoutAFile() {
        // Reader mints `rec-…` for imported cards with nothing to hash.
        let iri = DocumentIdentity.canonical(localName: "rec-9f2a1c")
        #expect(iri == "urn:origami:local:rec-9f2a1c")
        #expect(DocumentIdentity.normalised(iri) == "local:rec-9f2a1c")
        // And the form Reader used to write means the same thing.
        #expect(DocumentIdentity.isSameDocument(iri, "urn:x-reader:rec-9f2a1c"))
    }

    @Test("Origami Text's own URL still resolves to the same document")
    func origamiLegacy() {
        #expect(DocumentIdentity.normalised("origamitext://open/" + hash)
                == "sha256:" + hash)
        #expect(DocumentIdentity.isSameDocument("origamitext://open/" + hash,
                                                "urn:x-reader:" + hash))
    }

    @Test("Two different documents stay different")
    func differentDocuments() {
        #expect(!DocumentIdentity.isSameDocument("urn:x-reader:" + hash,
                                                 "urn:x-reader:" + String(repeating: "f", count: 64)))
        #expect(!DocumentIdentity.isSameDocument("https://doi.org/10.1/a",
                                                 "https://doi.org/10.1/b"))
        // An empty name matches nothing, including another empty name.
        #expect(!DocumentIdentity.isSameDocument("", ""))
    }

    @Test("Prose that merely mentions a DOI is not an identifier")
    func proseIsNotAnIdentifier() {
        let sentence = "10.1145/3345001 is the paper we mean"
        #expect(DocumentIdentity.doiPortion(of: sentence) == nil)
    }

    @Test("Only a real SHA-256 counts as a content hash")
    func hashShape() {
        #expect(DocumentIdentity.isContentHash(hash))
        #expect(!DocumentIdentity.isContentHash("rec-9f2a1c"))
        #expect(!DocumentIdentity.isContentHash(String(repeating: "z", count: 64)))
        #expect(!DocumentIdentity.isContentHash(String(repeating: "a", count: 63)))
    }

    @Test("An annotation written by Reader names the document canonically")
    func throughTheAnnotation() {
        let withDOI = WebAnnotation.source(forRecordID: hash, doi: "10.1145/3345001")
        #expect(withDOI == "https://doi.org/10.1145/3345001")
        let without = WebAnnotation.source(forRecordID: hash, doi: nil)
        #expect(without == "urn:origami:sha256:" + hash)
    }
}
