import Foundation

// Origami Text's anchoring ladder, lifted out of its `AnnotationStore.swift`
// and cut free of `LiquidDoc` so it works on any document that can name its
// units and hand over their text. Reader had no re-anchoring at all: a note
// whose element id changed was simply lost. Now both apps run the same
// cascade, which is the point — an anchor that resolves differently in two
// readers is not an anchor.

/// One addressable unit of a document, as the anchoring ladder needs it:
/// a stable id and the words inside it. Origami paragraphs, EPUB elements
/// carrying `data-id`, and PDF text blocks all reduce to this.
public nonisolated struct AnchoredParagraph: Hashable, Sendable {
    public var id: String
    public var text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

/// The anchoring ladder, mirroring the Origami format's own scope rules:
/// resolve the stable id first (it survives re-export and revision), find
/// the exact words within that unit, fall back to a document-wide search
/// disambiguated by the quote's prefix/suffix (the Hypothesis re-anchoring
/// move), and degrade to unit scope rather than break. All text matching is
/// case- and diacritic-insensitive, the format's span rule.
public nonisolated enum AnnotationAnchor {

    public struct Resolution: Hashable, Sendable {
        public enum Method: Hashable, Sendable {
            /// The stable id matched.
            case fragment
            /// The stable id matched and the exact words were found in it.
            case quoteInParagraph
            /// The id was gone; the words were found elsewhere.
            case quoteInDocument
            /// The id matched but the words are gone — unit scope stands.
            case paragraph
        }

        public let paragraphID: String
        /// The words to highlight, when they were found.
        public let exact: String?
        public let method: Method

        public init(paragraphID: String, exact: String?, method: Method) {
            self.paragraphID = paragraphID
            self.exact = exact
            self.method = method
        }
    }

    /// Where an annotation lands in this document, or nil when nothing in it
    /// still matches (an orphan — kept and shown, never lost). The cascade,
    /// Hypothesis's way: the stable id and exact words; the words fuzzily
    /// inside their unit; the exact words anywhere (context-scored); the
    /// words fuzzily anywhere, searched outward from where the position and
    /// progression hints expect them.
    public static func resolve(_ annotation: WebAnnotation,
                               in paragraphs: [AnchoredParagraph]) -> Resolution? {
        var fragmentID: String?
        var quote: (exact: String, prefix: String?, suffix: String?)?
        var positionHint: Int?
        var progressionHint: Double?
        for selector in annotation.target.selectors {
            switch selector {
            case .fragment(let value, _): fragmentID = fragmentID ?? value
            case .quote(let exact, let prefix, let suffix):
                if quote == nil, !exact.isEmpty { quote = (exact, prefix, suffix) }
            case .position(let start, _): positionHint = positionHint ?? start
            case .progression(let value): progressionHint = progressionHint ?? value
            // A page says where the reader was standing, not which words
            // the note is about; it anchors nothing.
            case .page: break
            }
        }
        let anchored = fragmentID.flatMap { id in paragraphs.first { $0.id == id } }

        if let paragraph = anchored {
            if let quote {
                if paragraph.text.range(of: quote.exact, options: matching) != nil {
                    return Resolution(paragraphID: paragraph.id, exact: quote.exact,
                                      method: .quoteInParagraph)
                }
                // The words drifted (an edit, a re-export): find their
                // nearest reading inside the unit, and highlight the
                // document's own words there.
                if let fuzzy = fuzzyMatch(quote.exact, in: paragraph.text) {
                    return Resolution(paragraphID: paragraph.id, exact: fuzzy,
                                      method: .quoteInParagraph)
                }
                // The span is gone from its unit: unit scope stands, per
                // the ladder — never break.
                return Resolution(paragraphID: paragraph.id, exact: nil, method: .paragraph)
            }
            return Resolution(paragraphID: paragraph.id, exact: nil, method: .fragment)
        }

        guard let quote else { return nil }

        // Exact words anywhere, the prefix/suffix breaking ties.
        var best: (id: String, score: Int)?
        for paragraph in paragraphs {
            let text = paragraph.text
            var search = text.startIndex..<text.endIndex
            while let found = text.range(of: quote.exact, options: matching, range: search) {
                var score = 0
                if let prefix = quote.prefix, !prefix.isEmpty {
                    let preceding = String(text[..<found.lowerBound].suffix(prefix.count + 8))
                    if folded(preceding).hasSuffix(folded(prefix)) { score += 1 }
                }
                if let suffix = quote.suffix, !suffix.isEmpty {
                    let following = String(text[found.upperBound...].prefix(suffix.count + 8))
                    if folded(following).hasPrefix(folded(suffix)) { score += 1 }
                }
                if best == nil || score > best!.score {
                    best = (paragraph.id, score)
                }
                guard found.upperBound < text.endIndex else { break }
                search = found.upperBound..<text.endIndex
            }
        }
        if let best {
            return Resolution(paragraphID: best.id, exact: quote.exact,
                              method: .quoteInDocument)
        }

        // Fuzzy anywhere — but hinted: units are tried outward from where
        // the position (or progression) says the words were, so the search
        // usually ends where it starts.
        let ordered = hintOrdered(paragraphs, positionHint: positionHint,
                                  progressionHint: progressionHint)
        for paragraph in ordered {
            if let fuzzy = fuzzyMatch(quote.exact, in: paragraph.text) {
                return Resolution(paragraphID: paragraph.id, exact: fuzzy,
                                  method: .quoteInDocument)
            }
        }

        return nil
    }

    /// The units ordered outward from the hinted place: the position
    /// selector's global offset when there is one, else the progression
    /// fraction, else document order.
    private static func hintOrdered(_ paragraphs: [AnchoredParagraph],
                                    positionHint: Int?,
                                    progressionHint: Double?) -> [AnchoredParagraph] {
        guard positionHint != nil || progressionHint != nil else { return paragraphs }
        var offsets: [Int] = []
        var running = 0
        for paragraph in paragraphs {
            offsets.append(running)
            running += paragraph.text.count + 2
        }
        let target: Int
        if let positionHint {
            target = positionHint
        } else {
            target = Int(Double(running) * min(max(progressionHint ?? 0, 0), 1))
        }
        return zip(paragraphs, offsets)
            .sorted { abs($0.1 - target) < abs($1.1 - target) }
            .map(\.0)
    }

    /// The document's own words nearest the quote, within an edit budget of
    /// a fifth of the quote (at least 2, at most 24 edits) — Sellers's
    /// approximate substring search. Returns the matched words as the
    /// document writes them, so a highlight paints what the page actually
    /// says. Short quotes stay exact-only: fuzziness on a few characters
    /// matches noise.
    public static func fuzzyMatch(_ quote: String, in text: String) -> String? {
        let needle = Array(quote.lowercased())
        let haystack = Array(text.lowercased())
        guard needle.count >= 8, !haystack.isEmpty else { return nil }
        let budget = max(2, min(needle.count / 5, 24))

        // D[i] = fewest edits matching needle[0..<i] ending at the current
        // haystack position; start[i] = where that match began.
        var previousDistance = Array(0...needle.count)
        var previousStart = Array(repeating: 0, count: needle.count + 1)
        var best: (start: Int, end: Int, distance: Int)?

        for j in 1...haystack.count {
            var currentDistance = [0] + Array(repeating: 0, count: needle.count)
            var currentStart = Array(repeating: j, count: needle.count + 1)
            for i in 1...needle.count {
                let substitution = previousDistance[i - 1]
                    + (needle[i - 1] == haystack[j - 1] ? 0 : 1)
                let deletion = previousDistance[i] + 1
                let insertion = currentDistance[i - 1] + 1
                let smallest = min(substitution, min(deletion, insertion))
                currentDistance[i] = smallest
                if smallest == substitution {
                    currentStart[i] = previousStart[i - 1]
                } else if smallest == deletion {
                    currentStart[i] = previousStart[i]
                } else {
                    currentStart[i] = currentStart[i - 1]
                }
            }
            let distance = currentDistance[needle.count]
            if distance <= budget, best == nil || distance < best!.distance {
                best = (currentStart[needle.count], j, distance)
            }
            previousDistance = currentDistance
            previousStart = currentStart
        }

        guard let best else { return nil }
        let characters = Array(text)
        guard best.start < best.end, best.end <= characters.count else { return nil }
        let matched = String(characters[best.start..<best.end])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return matched.isEmpty ? nil : matched
    }

    /// The target for a new annotation on `paragraphID`, carrying the whole
    /// ladder: the stable id, and — when `exact` names words that occur in
    /// the unit — the quote with up to 32 characters of context and a
    /// position hint (character offsets within the unit's text).
    public static func target(source: String,
                              in paragraphs: [AnchoredParagraph],
                              paragraphID: String,
                              exact: String? = nil) -> WebAnnotation.Target {
        var selectors: [WebAnnotation.Selector] = [
            .fragment(value: paragraphID, conformsTo: WebAnnotation.fragmentConformsTo),
        ]
        let paragraph = paragraphs.first { $0.id == paragraphID }
        if let exact, !exact.isEmpty {
            if let text = paragraph?.text,
               let range = text.range(of: exact, options: matching) {
                let prefix = String(text[..<range.lowerBound].suffix(32))
                let suffix = String(text[range.upperBound...].prefix(32))
                selectors.append(.quote(exact: String(text[range]),
                                        prefix: prefix.isEmpty ? nil : prefix,
                                        suffix: suffix.isEmpty ? nil : suffix))
                let start = text.distance(from: text.startIndex, to: range.lowerBound)
                let length = text.distance(from: range.lowerBound, to: range.upperBound)
                selectors.append(.position(start: start, end: start + length))
            } else {
                selectors.append(.quote(exact: exact, prefix: nil, suffix: nil))
            }
        }
        // The coarse fraction through the document — Readium's
        // ProgressionSelector: ordering, hinting, and last resort.
        if !paragraphs.isEmpty,
           let index = paragraphs.firstIndex(where: { $0.id == paragraphID }) {
            selectors.append(.progression(Double(index) / Double(paragraphs.count)))
        }
        return WebAnnotation.Target(source: source, selectors: selectors)
    }

    private static let matching: String.CompareOptions =
        [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
    }
}
