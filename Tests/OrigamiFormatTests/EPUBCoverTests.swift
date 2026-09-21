import Testing
import Foundation
@testable import OrigamiFormat

/// A book should look like itself on the shelf. Covers are named two
/// different ways depending on the book's age, and plenty of books carry
/// none at all — which is a glyph, not a failure.
@Suite("EPUB covers")
struct EPUBCoverTests {

    /// A one-pixel PNG, so the fixtures are real files with real bytes.
    private let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    private func makeBook(_ opf: String, withCover: Bool, named name: String) throws -> URL {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("epub-cover-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        var entries: [(String, Data)] = [
            ("META-INF/container.xml", Data("""
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
            </container>
            """.utf8)),
            ("OEBPS/content.opf", Data(opf.utf8)),
            ("OEBPS/one.xhtml", Data("<html><body>text</body></html>".utf8)),
        ]
        if withCover { entries.append(("OEBPS/cover.png", png)) }
        try StoredZip.write(entries, to: url)
        return url
    }

    @Test("EPUB 3 names its cover in the manifest item")
    func epub3Cover() throws {
        let url = try makeBook("""
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
         <manifest>
          <item id="cover" href="cover.png" media-type="image/png" properties="cover-image"/>
          <item id="c1" href="one.xhtml" media-type="application/xhtml+xml"/>
         </manifest>
         <spine><itemref idref="c1"/></spine>
        </package>
        """, withCover: true, named: "three.epub")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(EPUBPackage.coverImageData(at: url) == png)
    }

    @Test("EPUB 2 names its cover in the metadata")
    func epub2Cover() throws {
        let url = try makeBook("""
        <package xmlns="http://www.idpf.org/2007/opf" version="2.0">
         <metadata><meta name="cover" content="theCover"/></metadata>
         <manifest>
          <item id="theCover" href="cover.png" media-type="image/png"/>
          <item id="c1" href="one.xhtml" media-type="application/xhtml+xml"/>
         </manifest>
         <spine><itemref idref="c1"/></spine>
        </package>
        """, withCover: true, named: "two.epub")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(EPUBPackage.coverImageData(at: url) == png)
    }

    @Test("A book with no cover answers with none, and does not throw")
    func noCover() throws {
        let url = try makeBook("""
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
         <manifest><item id="c1" href="one.xhtml" media-type="application/xhtml+xml"/></manifest>
         <spine><itemref idref="c1"/></spine>
        </package>
        """, withCover: false, named: "bare.epub")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(EPUBPackage.coverImageData(at: url) == nil)
    }

    @Test("A file that is not a book answers with none")
    func notABook() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("not-a-book-\(UUID().uuidString).epub")
        try Data("plain text".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(EPUBPackage.coverImageData(at: url) == nil)
    }
}

/// The smallest ZIP writer that `ZipReader` can read back: every entry
/// stored, no compression. Tests need to *make* books, and the app only
/// ever reads them, so this lives here rather than in the library.
enum StoredZip {

    static func write(_ entries: [(name: String, data: Data)], to url: URL) throws {
        var archive = Data()
        var directory = Data()
        var offsets: [Int] = []

        for entry in entries {
            offsets.append(archive.count)
            let name = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            archive += localHeader(name: name, data: entry.data, crc: crc)
            archive += name
            archive += entry.data
        }
        for (index, entry) in entries.enumerated() {
            let name = Data(entry.name.utf8)
            directory += centralHeader(name: name, data: entry.data,
                                       crc: crc32(entry.data), offset: offsets[index])
            directory += name
        }
        let directoryOffset = archive.count
        archive += directory
        archive += endRecord(count: entries.count, size: directory.count, offset: directoryOffset)
        try archive.write(to: url)
    }

    private static func localHeader(name: Data, data: Data, crc: UInt32) -> Data {
        var header = Data()
        header += le32(0x0403_4b50)             // local file header
        header += le16(20) + le16(0) + le16(0)  // version, flags, stored
        header += le16(0) + le16(0)             // time, date
        header += le32(crc)
        header += le32(UInt32(data.count)) + le32(UInt32(data.count))
        header += le16(UInt16(name.count)) + le16(0)
        return header
    }

    private static func centralHeader(name: Data, data: Data, crc: UInt32, offset: Int) -> Data {
        var header = Data()
        header += le32(0x0201_4b50)             // central directory header
        header += le16(20) + le16(20) + le16(0) + le16(0)
        header += le16(0) + le16(0)
        header += le32(crc)
        header += le32(UInt32(data.count)) + le32(UInt32(data.count))
        header += le16(UInt16(name.count)) + le16(0) + le16(0)
        header += le16(0) + le16(0) + le32(0)
        header += le32(UInt32(offset))
        return header
    }

    private static func endRecord(count: Int, size: Int, offset: Int) -> Data {
        var record = Data()
        record += le32(0x0605_4b50)
        record += le16(0) + le16(0)
        record += le16(UInt16(count)) + le16(UInt16(count))
        record += le32(UInt32(size)) + le32(UInt32(offset))
        record += le16(0)
        return record
    }

    private static func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xff), UInt8((value >> 8) & 0xff)])
    }

    private static func le32(_ value: UInt32) -> Data {
        Data([UInt8(value & 0xff), UInt8((value >> 8) & 0xff),
              UInt8((value >> 16) & 0xff), UInt8((value >> 24) & 0xff)])
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var table: [UInt32] = (0..<256).map { index in
            var code = UInt32(index)
            for _ in 0..<8 { code = (code & 1) == 1 ? (0xEDB8_8320 ^ (code >> 1)) : (code >> 1) }
            return code
        }
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
        }
        table.removeAll()
        return crc ^ 0xFFFF_FFFF
    }
}
