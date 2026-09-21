import Foundation
import Compression

// The ZIP reader is ported from Origami Text's `OrigamiEPUBImport.swift`
// (`ZipReader`) — keep synced; a fix here should be carried back. It is here
// rather than in the app so the EPUB reader, when it lands, reads books
// through the same code that catalogues them.

public enum EPUBError: Error {
    case notAnEPUB
    case corruptContainer
    case unsupportedCompression(Int)
}

/// What a book says about itself: the Dublin Core metadata in its OPF
/// package document. Read without unpacking the book — only the container
/// pointer and the package document are inflated.
public nonisolated struct EPUBMetadata: Sendable {
    public var title: String?
    public var creators: [String]
    public var date: String?
    public var publisher: String?
    /// `dc:identifier`, which for a published book is usually its ISBN and
    /// occasionally a DOI or a URN.
    public var identifier: String?
    public var language: String?

    /// The ISBN in `identifier`, digits only, when it looks like one.
    public var isbn: String? {
        guard let identifier else { return nil }
        let digits = identifier.filter { $0.isNumber || $0 == "X" || $0 == "x" }
        guard digits.count == 10 || digits.count == 13 else { return nil }
        return digits.uppercased()
    }

    /// The DOI in `identifier`, when it carries one.
    public var doi: String? {
        guard let identifier else { return nil }
        return DOI.extract(from: identifier)
    }

    /// Reads a book's own metadata. Nil when the file is not a readable EPUB
    /// — a half-downloaded iCloud placeholder, say — which is never fatal:
    /// the catalogue simply skips it this time.
    public static func read(at url: URL) -> EPUBMetadata? {
        guard let zip = try? ZipReader(url: url),
              let opfPath = zip.rootFilePath(),
              let opfData = zip.entry(opfPath)
        else { return nil }
        let opf = String(decoding: opfData, as: UTF8.self)
        return EPUBMetadata(
            title: firstTagText(in: opf, tag: "dc:title") ?? firstTagText(in: opf, tag: "title"),
            creators: allTagText(in: opf, tag: "dc:creator")
                + (firstTagText(in: opf, tag: "dc:creator") == nil
                   ? allTagText(in: opf, tag: "creator") : []),
            date: firstTagText(in: opf, tag: "dc:date") ?? firstTagText(in: opf, tag: "date"),
            publisher: firstTagText(in: opf, tag: "dc:publisher"),
            identifier: firstTagText(in: opf, tag: "dc:identifier"),
            language: firstTagText(in: opf, tag: "dc:language"))
    }

    // MARK: - The little XML we need

    /// The text of the first `<tag …>…</tag>`, entities resolved. A book's
    /// package document is small and regular; this is deliberately not a
    /// general XML parser.
    static func firstTagText(in xml: String, tag: String) -> String? {
        allTagText(in: xml, tag: tag).first
    }

    static func allTagText(in xml: String, tag: String) -> [String] {
        var results: [String] = []
        var search = xml.startIndex..<xml.endIndex
        while let open = xml.range(of: "<\(tag)", options: [.caseInsensitive], range: search),
              let openEnd = xml.range(of: ">", range: open.upperBound..<xml.endIndex),
              let close = xml.range(of: "</\(tag)>", options: [.caseInsensitive],
                                    range: openEnd.upperBound..<xml.endIndex) {
            let text = String(xml[openEnd.upperBound..<close.lowerBound])
            let cleaned = decodedEntities(text).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { results.append(cleaned) }
            guard close.upperBound < xml.endIndex else { break }
            search = close.upperBound..<xml.endIndex
        }
        return results
    }

    private static func decodedEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}

/// A minimal ZIP reader: the central directory drives extraction, and stored
/// and deflated entries both open. Nothing is inflated until an entry is
/// asked for, so reading one small package document out of a large book
/// costs almost nothing.
public nonisolated final class ZipReader {

    /// One central-directory record: where the bytes sit and how they unpack.
    private struct Record {
        let method: Int
        let start: Int
        let compressedSize: Int
        let uncompressedSize: Int
    }

    private let data: Data
    private var records: [String: Record] = [:]
    private var inflatedCache: [String: Data] = [:]
    /// Every entry name in central-directory order.
    public private(set) var entryNames: [String] = []

    /// Maps the file rather than loading it: an archive read for one entry
    /// never occupies memory for the rest.
    public convenience init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    public func entry(_ name: String) -> Data? {
        if let inflated = inflatedCache[name] { return inflated }
        guard let record = records[name] else { return nil }
        let raw = Self.slice(data, record.start, record.compressedSize)
        let bytes: Data
        switch record.method {
        case 0: bytes = raw
        case 8:
            guard let inflated = try? Self.inflated(raw, size: record.uncompressedSize)
            else { return nil }
            bytes = inflated
        default: return nil
        }
        inflatedCache[name] = bytes
        return bytes
    }

    /// The package document's path, from `META-INF/container.xml` — where an
    /// EPUB says its own metadata lives. Falls back to the first `.opf` in
    /// the archive, which is what a malformed book usually still has.
    public func rootFilePath() -> String? {
        if let container = entry("META-INF/container.xml") {
            let xml = String(decoding: container, as: UTF8.self)
            if let range = xml.range(of: #"full-path\s*=\s*"[^"]+""#, options: .regularExpression) {
                let attribute = xml[range]
                if let quoted = attribute.range(of: #""[^"]+""#, options: .regularExpression) {
                    let path = attribute[quoted].dropFirst().dropLast()
                    if !path.isEmpty { return String(path) }
                }
            }
        }
        return entryNames.first { $0.lowercased().hasSuffix(".opf") }
    }

    public init(data: Data) throws {
        self.data = data
        // Find the end-of-central-directory record from the back.
        let minimumEOCD = 22
        guard data.count >= minimumEOCD else { throw EPUBError.notAnEPUB }
        var eocd: Int?
        var probe = data.count - minimumEOCD
        let lowest = max(0, data.count - 66_000)
        while probe >= lowest {
            if Self.le32(data, probe) == 0x0605_4b50 { eocd = probe; break }
            probe -= 1
        }
        guard let eocd else { throw EPUBError.notAnEPUB }

        let count = Int(Self.le16(data, eocd + 10))
        var offset = Int(Self.le32(data, eocd + 16))
        for _ in 0..<count {
            guard offset + 46 <= data.count,
                  Self.le32(data, offset) == 0x0201_4b50 else {
                throw EPUBError.corruptContainer
            }
            let method = Int(Self.le16(data, offset + 10))
            let compressedSize = Int(Self.le32(data, offset + 20))
            let uncompressedSize = Int(Self.le32(data, offset + 24))
            let nameLength = Int(Self.le16(data, offset + 28))
            let extraLength = Int(Self.le16(data, offset + 30))
            let commentLength = Int(Self.le16(data, offset + 32))
            let localOffset = Int(Self.le32(data, offset + 42))
            let name = String(decoding: Self.slice(data, offset + 46, nameLength), as: UTF8.self)

            // The local header's name/extra lengths can differ from the
            // central directory's; the data follows the local header.
            guard localOffset + 30 <= data.count,
                  Self.le32(data, localOffset) == 0x0403_4b50 else {
                throw EPUBError.corruptContainer
            }
            let localName = Int(Self.le16(data, localOffset + 26))
            let localExtra = Int(Self.le16(data, localOffset + 28))
            let start = localOffset + 30 + localName + localExtra
            guard start + compressedSize <= data.count else {
                throw EPUBError.corruptContainer
            }
            guard method == 0 || method == 8 else {
                throw EPUBError.unsupportedCompression(method)
            }
            if records[name] == nil { entryNames.append(name) }
            records[name] = Record(method: method, start: start,
                                   compressedSize: compressedSize,
                                   uncompressedSize: uncompressedSize)
            offset += 46 + nameLength + extraLength + commentLength
        }
    }

    /// Raw DEFLATE, which is what Compression's ZLIB algorithm speaks.
    private static func inflated(_ data: Data, size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { out -> Int in
            data.withUnsafeBytes { input -> Int in
                guard let outBase = out.bindMemory(to: UInt8.self).baseAddress,
                      let inBase = input.bindMemory(to: UInt8.self).baseAddress
                else { return 0 }
                return compression_decode_buffer(outBase, size, inBase, data.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw EPUBError.corruptContainer }
        return output
    }

    private static func le16(_ data: Data, _ offset: Int) -> UInt16 {
        let base = data.startIndex + offset
        return UInt16(data[base]) | (UInt16(data[base + 1]) << 8)
    }

    private static func le32(_ data: Data, _ offset: Int) -> UInt32 {
        let base = data.startIndex + offset
        return UInt32(data[base])
            | (UInt32(data[base + 1]) << 8)
            | (UInt32(data[base + 2]) << 16)
            | (UInt32(data[base + 3]) << 24)
    }

    private static func slice(_ data: Data, _ offset: Int, _ length: Int) -> Data {
        let base = data.startIndex + offset
        return Data(data[base..<base + length])
    }
}
