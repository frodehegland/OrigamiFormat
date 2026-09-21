import Foundation

// The annotation model, held once for every app that writes one. Reader and
// Origami Text each carried a copy, kept in step by hand and no longer in
// step: 58% of the lines still matched, and the two had come to disagree
// about what a document even is (see `DocumentIdentity`).
//
// This file is the union of both, and both halves are kept, because each
// app was right about its own: Origami Text contributed the annotation
// *kinds* a reader stamps on words and the places a note can stand
// (`origami:placement` on the page, `origami:float` in a room); Reader
// contributed passage anchoring, the page selector, and `reader:place` —
// where a note was written, so a reader's notes can be put on a map.

/// One W3C Web Annotation (https://www.w3.org/TR/annotation-model/) — the
/// same model Hypothesis and Readium use — targeting a document in the
/// library.
///
/// The Codable implementation is hand-written so the JSON is real JSON-LD:
/// `@context` on every annotation, `"type": "Annotation"`, and selectors
/// discriminated by their `type` (`FragmentSelector`, `TextQuoteSelector`,
/// `TextPositionSelector`). A whole-document note simply has no selectors:
/// its target is the document itself.
public nonisolated struct WebAnnotation: Identifiable, Hashable, Sendable {

    public static let context = "http://www.w3.org/ns/anno.jsonld"
    /// What FragmentSelector values conform to here: the Origami document's
    /// stable paragraph ids.
    public static let fragmentConformsTo = "https://origamitext.app/ns/data-id"

    /// The recommended motivations (the vocabulary is the W3C's, open).
    public enum Motivation {
        public static let highlighting = "highlighting"
        public static let commenting = "commenting"
        public static let tagging = "tagging"
        /// The whole-document annotation — no selectors; the reader's note
        /// about the document itself.
        public static let describing = "describing"
    }

    public var id: String
    public var motivation: String
    public var created: Date
    public var modified: Date?
    public var creator: Person?
    public var body: TextualBody?
    public var target: Target

    public init(id: String = "urn:uuid:" + UUID().uuidString.lowercased(),
                motivation: String,
                created: Date = Date(),
                modified: Date? = nil,
                creator: Person? = nil,
                body: TextualBody? = nil,
                target: Target,
                place: Place? = nil,
                placement: Placement? = nil,
                float: FloatPosition? = nil) {
        self.id = id
        self.motivation = motivation
        self.created = created
        self.modified = modified
        self.creator = creator
        self.body = body
        self.target = target
        self.place = place
        self.placement = placement
        self.float = float
    }

    public struct Person: Hashable, Sendable {
        public var name: String

        public init(name: String) { self.name = name }
    }

    public struct TextualBody: Hashable, Sendable {
        public var value: String
        /// Why the body is attached, when it differs from the annotation's
        /// motivation — e.g. "describing".
        public var purpose: String?

        public init(value: String, purpose: String? = nil) {
            self.value = value
            self.purpose = purpose
        }
    }

    public struct Target: Hashable, Sendable {
        /// The annotated document's IRI — its DOI where it has one, else a
        /// `urn:x-reader:<record id>` naming the card in the store.
        public var source: String
        public var selectors: [Selector]

        public init(source: String, selectors: [Selector] = []) {
            self.source = source
            self.selectors = selectors
        }
    }

    /// The selector ladder, most robust first: the stable paragraph id, the
    /// exact words with disambiguating context, a position hint, and the
    /// coarse fraction through the document (Readium's ProgressionSelector).
    /// A whole-document note carries none of them.
    public enum Selector: Hashable, Sendable {
        case fragment(value: String, conformsTo: String?)
        case quote(exact: String, prefix: String?, suffix: String?)
        case position(start: Int, end: Int)
        case progression(Double)
        /// The page a note was written on, 1-based — a PDF's own fragment
        /// identifier (RFC 8118, `#page=7`), so any PDF reader understands it.
        case page(Int)
    }

    /// Where a note was written — the reader's own place, not the document's.
    /// Carried as `reader:place`, an extension in Reader's namespace, in the
    /// same spirit as Origami's `origami:placement`. Schema.org's Place
    /// shape, so a consumer that resolves the vocabulary reads it directly:
    /// a name, and the coordinates it was resolved from.
    public struct Place: Hashable, Sendable {
        /// What people call it — "London, United Kingdom".
        public var name: String
        public var latitude: Double?
        public var longitude: Double?

        public init(name: String, latitude: Double? = nil, longitude: Double? = nil) {
            self.name = name
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    /// Where the reader stood when they wrote this, when they chose to say.
    public var place: Place?

    /// Where a page note stands on the rendering — an extension the sidecar
    /// carries (`origami:placement`), so slips travel with their
    /// annotations. Anchored to the nearest stable element with an offset
    /// from its top-left; with no anchor the offsets read as absolute page
    /// coordinates.
    public struct Placement: Hashable, Sendable {
        public var near: String?
        public var dx: Double
        public var dy: Double

        public init(near: String?, dx: Double, dy: Double) {
            self.near = near
            self.dx = dx
            self.dy = dy
        }
    }

    /// The page note's standing place, when it has one. Nil for annotations
    /// anchored to words.
    public var placement: Placement?

    /// A floated passage's standing place in a Map's own space
    /// (`origami:float`) — metres, with the carried space's shift removed,
    /// so the quote rides the map on any device that renders it.
    public struct FloatPosition: Hashable, Sendable {
        public var x: Double
        public var y: Double
        public var z: Double

        public init(x: Double, y: Double, z: Double) {
            self.x = x
            self.y = y
            self.z = z
        }
    }

    /// Where the floated quote stands in the room, when it does.
    public var float: FloatPosition?

    /// The words this annotation stands on, from its quote selector — the
    /// document's own text, not the reader's note (which lives in `body`).
    public var quotedText: String? {
        for selector in target.selectors {
            if case .quote(let exact, _, _) = selector, !exact.isEmpty { return exact }
        }
        return nil
    }

    /// The page this annotation stands on, 1-based, when it names one.
    public var pageNumber: Int? {
        for selector in target.selectors {
            if case .page(let number) = selector { return number }
        }
        return nil
    }

    /// True for the whole-document notes: a describing annotation that
    /// anchors to no words. A page selector does not disqualify it — the page
    /// records where the reader was standing when they wrote, not a passage
    /// the note is about.
    public var isAboutWholeDocument: Bool {
        guard motivation == Motivation.describing else { return false }
        return target.selectors.allSatisfy { selector in
            if case .page = selector { return true }
            return false
        }
    }

    /// The note's text, or an empty string when it carries none.
    public var text: String { body?.value ?? "" }
}

// MARK: - Making one

public extension WebAnnotation {

    /// A note about the whole of a document: the W3C describing motivation
    /// with no selectors, as Origami Text writes it.
    static func documentNote(_ text: String,
                             about source: String,
                             author: String?,
                             place: Place? = nil,
                             page: Int? = nil) -> WebAnnotation {
        var selectors: [Selector] = []
        // A note written while looking at page 7 says so — it is still a note
        // about the document (motivation describing), but the page is worth
        // keeping, and `#page=` is a PDF's own fragment identifier.
        if let page, page > 0 { selectors.append(.page(page)) }
        return WebAnnotation(
            motivation: Motivation.describing,
            creator: (author?.isEmpty == false) ? Person(name: author!) : nil,
            body: TextualBody(value: text, purpose: "describing"),
            target: Target(source: source, selectors: selectors),
            place: place)
    }

    /// A note about a passage rather than about the whole document — what
    /// the Origami profile's addressability is for.
    ///
    /// The target carries the ladder the model recommends, most robust
    /// first: the **stable element id** the document declared (Origami's
    /// `data-id` / `id` — an anchor that does not move when the text
    /// reflows), then the exact words with their surrounding context so the
    /// note re-anchors if the id ever changes, then the place in the book.
    static func passageNote(_ text: String,
                            quoting passage: String,
                            elementID: String?,
                            about source: String,
                            author: String?,
                            place: Place? = nil,
                            page: Int? = nil,
                            prefix: String? = nil,
                            suffix: String? = nil) -> WebAnnotation {
        var selectors: [Selector] = []
        if let elementID, !elementID.isEmpty {
            selectors.append(.fragment(value: elementID, conformsTo: fragmentConformsTo))
        }
        let quoted = passage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !quoted.isEmpty {
            selectors.append(.quote(exact: quoted, prefix: prefix, suffix: suffix))
        }
        if let page, page > 0 { selectors.append(.page(page)) }
        return WebAnnotation(
            motivation: Motivation.commenting,
            creator: (author?.isEmpty == false) ? Person(name: author!) : nil,
            body: text.isEmpty ? nil : TextualBody(value: text, purpose: "commenting"),
            target: Target(source: source, selectors: selectors),
            place: place)
    }

    /// The stable element id this annotation anchors to, when it names one —
    /// the addressable unit the document declared.
    var anchorID: String? {
        for selector in target.selectors {
            if case .fragment(let value, let conformsTo) = selector,
               conformsTo == Self.fragmentConformsTo || conformsTo == nil {
                return value
            }
        }
        return nil
    }

    /// The citation block the Origami profile describes: the source
    /// document's own BibTeX entry, extended with one field naming the
    /// passage. A reference manager that has never heard of the field
    /// ingests the rest as an ordinary entry.
    ///
    /// - Parameters:
    ///   - bibtex: the document's invariant entry, as it carries it.
    ///   - anchor: the addressable unit being cited.
    static func citationBlock(bibtex: String, anchor: String?) -> String {
        let entry = bibtex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let anchor, !anchor.isEmpty else { return entry }
        guard let lastBrace = entry.lastIndex(of: "}") else {
            return entry + "\n  origami-anchor = {\(anchor)},"
        }
        // The field goes inside the entry, before its closing brace, with
        // the comma discipline BibTeX expects.
        var body = String(entry[entry.startIndex..<lastBrace])
        while let last = body.last, last.isWhitespace { body.removeLast() }
        if !body.hasSuffix(",") { body += "," }
        return body + "\n  origami-anchor = {\(anchor)},\n}"
    }

    /// The IRI naming a library work: its DOI where it has one — the name
    /// the rest of the world already uses — else the content-addressed URN
    /// both apps agree on. See `DocumentIdentity` for why this is not each
    /// app's own invention any more.
    static func source(forRecordID recordID: String, doi: String?) -> String {
        DocumentIdentity.canonical(doi: doi, localName: recordID)
    }
}

// MARK: - JSON-LD coding

nonisolated extension WebAnnotation: Codable {

    private enum CodingKeys: String, CodingKey {
        case context = "@context"
        case id, type, motivation, created, modified, creator, body, target
        case place = "reader:place"
        case placement = "origami:placement"
        case float = "origami:float"
    }

    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func parseISO8601(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.context, forKey: .context)
        try container.encode(id, forKey: .id)
        try container.encode("Annotation", forKey: .type)
        try container.encode(motivation, forKey: .motivation)
        try container.encode(Self.iso8601(created), forKey: .created)
        if let modified {
            try container.encode(Self.iso8601(modified), forKey: .modified)
        }
        try container.encodeIfPresent(creator, forKey: .creator)
        try container.encodeIfPresent(body, forKey: .body)
        try container.encode(target, forKey: .target)
        try container.encodeIfPresent(place, forKey: .place)
        try container.encodeIfPresent(placement, forKey: .placement)
        try container.encodeIfPresent(float, forKey: .float)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? "urn:uuid:" + UUID().uuidString.lowercased()
        motivation = try container.decodeIfPresent(String.self, forKey: .motivation)
            ?? Motivation.commenting
        let createdString = try container.decodeIfPresent(String.self, forKey: .created)
        created = createdString.flatMap(Self.parseISO8601) ?? Date()
        let modifiedString = try container.decodeIfPresent(String.self, forKey: .modified)
        modified = modifiedString.flatMap(Self.parseISO8601)
        creator = try? container.decodeIfPresent(Person.self, forKey: .creator)
        body = try? container.decodeIfPresent(TextualBody.self, forKey: .body)
        target = try container.decode(Target.self, forKey: .target)
        place = try? container.decodeIfPresent(Place.self, forKey: .place)
        placement = try? container.decodeIfPresent(Placement.self, forKey: .placement)
        float = try? container.decodeIfPresent(FloatPosition.self, forKey: .float)
    }
}

nonisolated extension WebAnnotation.FloatPosition: Codable {}

nonisolated extension WebAnnotation.Placement: Codable {
    private enum CodingKeys: String, CodingKey { case near, dx, dy }
}

/// The reader's annotation vocabulary — the judgments a reader stamps on
/// words. Each travels as a standard W3C tagging body (purpose "tagging",
/// the tag its value), so any Web Annotation reader shows it; Highlight
/// keeps the plain highlighting motivation it always had.
public nonisolated enum ReaderAnnotationKind: String, CaseIterable, Identifiable, Sendable {
    case important = "Important"
    case quotable = "Quotable"
    case great = "Great"
    case disagree = "Disagree"
    case languageIssue = "Language Issue"
    case problematic = "Problematic"
    case whatIsThis = "What is this?"
    case highlight = "Highlight"
    case strikethrough = "Strikethrough"

    public var id: String { rawValue }

    /// The bare key that fires the kind while the Annotate menu is open.
    public var keyEquivalent: String {
        switch self {
        case .important: "i"
        case .quotable: "q"
        case .great: "g"
        case .disagree: "d"
        case .languageIssue: "l"
        case .problematic: "p"
        case .whatIsThis: "/"
        case .highlight: "h"
        case .strikethrough: "x"
        }
    }

    public var systemImage: String {
        switch self {
        case .important: "exclamationmark.circle"
        case .quotable: "quote.opening"
        case .great: "star"
        case .disagree: "hand.thumbsdown"
        case .languageIssue: "character.cursor.ibeam"
        case .problematic: "exclamationmark.triangle"
        case .whatIsThis: "questionmark.circle"
        case .highlight: "highlighter"
        case .strikethrough: "strikethrough"
        }
    }

    /// The kind an annotation carries, when it carries one: its tagging
    /// body's value, or Highlight for a plain highlighting motivation.
    public static func kind(of annotation: WebAnnotation) -> ReaderAnnotationKind? {
        if annotation.body?.purpose == "tagging",
           let value = annotation.body?.value,
           let kind = ReaderAnnotationKind(rawValue: value) {
            return kind
        }
        if annotation.motivation == WebAnnotation.Motivation.highlighting {
            return .highlight
        }
        return nil
    }
}

nonisolated extension WebAnnotation.Person: Codable {
    private enum CodingKeys: String, CodingKey { case type, name }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("Person", forKey: .type)
        try container.encode(name, forKey: .name)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    }
}

nonisolated extension WebAnnotation.TextualBody: Codable {
    private enum CodingKeys: String, CodingKey { case type, value, format, purpose }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("TextualBody", forKey: .type)
        try container.encode(value, forKey: .value)
        try container.encode("text/plain", forKey: .format)
        try container.encodeIfPresent(purpose, forKey: .purpose)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        purpose = try container.decodeIfPresent(String.self, forKey: .purpose)
    }
}

nonisolated extension WebAnnotation.Place: Codable {
    private enum CodingKeys: String, CodingKey { case type, name, latitude, longitude }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("Place", forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
    }
}

nonisolated extension WebAnnotation.Target: Codable {
    private enum CodingKeys: String, CodingKey { case source, selector }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        if !selectors.isEmpty {
            try container.encode(selectors, forKey: .selector)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        // The spec allows a single selector or an array; a selector of an
        // unknown type is skipped, never fatal.
        if let list = try? container.decode([Lossy].self, forKey: .selector) {
            selectors = list.compactMap(\.selector)
        } else if let one = try? container.decode(Lossy.self, forKey: .selector) {
            selectors = [one.selector].compactMap { $0 }
        } else {
            selectors = []
        }
    }

    private struct Lossy: Decodable {
        let selector: WebAnnotation.Selector?
        init(from decoder: Decoder) throws {
            selector = try? WebAnnotation.Selector(from: decoder)
        }
    }
}

nonisolated extension WebAnnotation.Selector: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, value, conformsTo, exact, prefix, suffix, start, end
    }

    private enum SelectorError: Error { case unknownType(String) }

    /// What a page FragmentSelector conforms to: the PDF fragment identifier
    /// syntax, RFC 8118 — `#page=7`.
    static let pageConformsTo = "http://tools.ietf.org/rfc/rfc8118"

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fragment(let value, let conformsTo):
            try container.encode("FragmentSelector", forKey: .type)
            try container.encode(value, forKey: .value)
            try container.encodeIfPresent(conformsTo, forKey: .conformsTo)
        case .quote(let exact, let prefix, let suffix):
            try container.encode("TextQuoteSelector", forKey: .type)
            try container.encode(exact, forKey: .exact)
            try container.encodeIfPresent(prefix, forKey: .prefix)
            try container.encodeIfPresent(suffix, forKey: .suffix)
        case .position(let start, let end):
            try container.encode("TextPositionSelector", forKey: .type)
            try container.encode(start, forKey: .start)
            try container.encode(end, forKey: .end)
        case .progression(let value):
            // Readium's ProgressionSelector: the fraction through the
            // resource — ordering, and the landing of last resort.
            try container.encode("ProgressionSelector", forKey: .type)
            try container.encode(value, forKey: .value)
        case .page(let number):
            try container.encode("FragmentSelector", forKey: .type)
            try container.encode("page=\(number)", forKey: .value)
            try container.encode(Self.pageConformsTo, forKey: .conformsTo)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        switch type {
        case "FragmentSelector":
            let value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
            let conformsTo = try container.decodeIfPresent(String.self, forKey: .conformsTo)
            // `page=7` is a page, whatever it says it conforms to.
            if value.hasPrefix("page="), let number = Int(value.dropFirst(5)) {
                self = .page(number)
            } else {
                self = .fragment(value: value, conformsTo: conformsTo)
            }
        case "TextQuoteSelector":
            self = .quote(exact: try container.decodeIfPresent(String.self, forKey: .exact) ?? "",
                          prefix: try container.decodeIfPresent(String.self, forKey: .prefix),
                          suffix: try container.decodeIfPresent(String.self, forKey: .suffix))
        case "TextPositionSelector":
            self = .position(start: try container.decodeIfPresent(Int.self, forKey: .start) ?? 0,
                             end: try container.decodeIfPresent(Int.self, forKey: .end) ?? 0)
        case "ProgressionSelector":
            self = .progression(try container.decodeIfPresent(Double.self, forKey: .value) ?? 0)
        default:
            throw SelectorError.unknownType(type)
        }
    }
}
