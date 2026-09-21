import Foundation

/// What a document *is*, said the same way by every app that annotates one.
///
/// This exists because Reader and Origami Text had come to disagree. An
/// annotation's target names its document by IRI, and the two apps minted
/// different IRIs for the same book — Origami Text wrote
/// `origamitext://open/<address>`, Reader wrote `urn:x-reader:<record id>`.
/// So a passage annotated in both apps produced two annotations about, as
/// far as any conforming consumer could tell, two unrelated resources. The
/// sidecars were readable by each other and still didn't join up.
///
/// The rule, in order:
///
/// 1. **The DOI**, where the work has one. It is the name the rest of the
///    world already uses, it resolves, and it is not ours to invent.
/// 2. **A content hash** otherwise — `urn:origami:sha256:<hex>` — because
///    two readers with the same file should reach the same name for it
///    without asking anybody. A URN, not a URL, because it names rather
///    than locates.
/// 3. **The app's own local name** as a last resort, for a card with
///    neither: better a name only one app understands than no name.
///
/// Reading is deliberately more generous than writing: `normalised` maps
/// every form either app has ever written onto a comparable key, so notes
/// already on disk keep working. Reader's record ids are content SHA-256s,
/// so its existing `urn:x-reader:<hash>` sidecars normalise onto the same
/// key as a freshly minted `urn:origami:sha256:<hash>` — the migration
/// costs nothing and loses nothing.
public nonisolated enum DocumentIdentity {

    /// The URN scheme for a content-addressed document.
    public static let hashScheme = "urn:origami:sha256:"
    /// The URN scheme for a document only one library can name — a card
    /// with no file to hash and no DOI to cite.
    public static let localScheme = "urn:origami:local:"
    /// Reader's historical URN, still read.
    public static let legacyReaderScheme = "urn:x-reader:"
    /// Origami Text's historical URL, still read.
    public static let legacyOrigamiScheme = "origamitext://open/"

    /// The IRI to write for a document, by the rule above. `localName` is
    /// the app's own identifier — a Reader record id, an Origami address —
    /// used only when there is nothing better.
    public static func canonical(doi: String? = nil,
                                 contentHash: String? = nil,
                                 localName: String? = nil) -> String {
        if let bare = DOI.bare(doi) {
            return "https://doi.org/" + bare
        }
        if let contentHash, isContentHash(contentHash) {
            return hashScheme + contentHash.lowercased()
        }
        if let localName, !localName.isEmpty {
            // A record id that happens to be a content hash is one: say so,
            // rather than minting a private name for it.
            if isContentHash(localName) { return hashScheme + localName.lowercased() }
            return localScheme + localName
        }
        return ""
    }

    /// A comparable key for an IRI, folding every form the two apps have
    /// written onto one value. Two IRIs name the same document exactly when
    /// their keys are equal.
    public static func normalised(_ iri: String) -> String {
        let trimmed = iri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Any spelling of a DOI, including a bare one.
        if let bare = doiPortion(of: trimmed) { return "doi:" + bare }

        if let hash = after(hashScheme, in: trimmed) { return "sha256:" + hash.lowercased() }

        if let name = after(localScheme, in: trimmed) { return "local:" + name }

        if let name = after(legacyReaderScheme, in: trimmed) {
            return isContentHash(name) ? "sha256:" + name.lowercased() : "local:" + name
        }

        if let address = after(legacyOrigamiScheme, in: trimmed) {
            return isContentHash(address) ? "sha256:" + address.lowercased() : "local:" + address
        }

        return trimmed.lowercased()
    }

    /// Whether two targets are about the same document, whichever app wrote
    /// them and whenever.
    public static func isSameDocument(_ one: String, _ other: String) -> Bool {
        let a = normalised(one)
        return !a.isEmpty && a == normalised(other)
    }

    /// The DOI an IRI carries, if it carries one — `https://doi.org/10.x/y`,
    /// `doi:10.x/y`, or the bare `10.x/y`.
    public static func doiPortion(of iri: String) -> String? {
        let lowered = iri.lowercased()
        for prefix in ["https://doi.org/", "http://doi.org/",
                       "https://dx.doi.org/", "http://dx.doi.org/", "doi:"]
        where lowered.hasPrefix(prefix) {
            return DOI.bare(String(iri.dropFirst(prefix.count)))
        }
        // A bare DOI stands on its own, but only when the whole string is
        // one — a sentence that mentions a DOI is not an identifier.
        if lowered.hasPrefix("10."), let bare = DOI.extract(from: iri), bare == lowered {
            return bare
        }
        return nil
    }

    /// A lowercase hex SHA-256, which is what both apps' content hashes are.
    /// Reader also mints `rec-…` ids for cards with no file; those are not
    /// hashes and stay local names.
    public static func isContentHash(_ text: String) -> Bool {
        text.count == 64 && text.allSatisfy { $0.isHexDigit }
    }

    private static func after(_ prefix: String, in text: String) -> String? {
        guard text.lowercased().hasPrefix(prefix.lowercased()) else { return nil }
        let rest = String(text.dropFirst(prefix.count))
        return rest.isEmpty ? nil : rest
    }
}
