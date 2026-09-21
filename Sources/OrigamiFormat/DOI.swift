import Foundation

/// Reading a DOI out of text.
///
/// This is here, in the format, rather than beside the PDF code that used to
/// own it, because document identity depends on it: a DOI is the name the
/// rest of the world already has for a work, so it is the first thing an
/// annotation's target should say. See `DocumentIdentity`.
public nonisolated enum DOI {

    /// A DOI as it appears in text: `10.` then a registrant and a suffix.
    /// The suffix is greedy, so trailing sentence punctuation is trimmed.
    private static let pattern = #"10\.\d{4,9}/[^\s"'<>&]+"#

    /// The first DOI found in a string, normalised (lowercased, trailing
    /// punctuation removed), or nil.
    public static func extract(from text: String) -> String? {
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive])
        else { return nil }
        var doi = String(text[range])
        while let last = doi.last, ".,;:)]}>".contains(last) { doi.removeLast() }
        let normalised = doi.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalised.isEmpty ? nil : normalised
    }

    /// The bare DOI — no resolver prefix, no `doi:` scheme — from whatever
    /// form it arrived in. Empty input, and input carrying no DOI at all,
    /// both give nil rather than a half-cleaned string.
    public static func bare(_ text: String?) -> String? {
        guard let text else { return nil }
        let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://doi.org/", with: "")
            .replacingOccurrences(of: "http://doi.org/", with: "")
            .replacingOccurrences(of: "https://dx.doi.org/", with: "")
            .replacingOccurrences(of: "http://dx.doi.org/", with: "")
            .replacingOccurrences(of: "doi:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped.lowercased()
    }
}
