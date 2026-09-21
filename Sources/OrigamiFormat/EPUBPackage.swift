import Foundation

/// An EPUB opened for reading: unpacked once into a cache folder, with its
/// spine (the reading order) and its table of contents read from the book's
/// own package document.
///
/// Ported in spirit from Origami Text's `OrigamiEPUBImporter` — the same
/// ladder (container → OPF → spine, then EPUB 3 `nav` or EPUB 2 NCX) — but
/// written for Reader, which needs the reading order and the contents and
/// nothing else. The book itself is never written to: unpacking copies into
/// Reader's own caches.
public nonisolated struct EPUBBook: Sendable {

    /// The unpacked root. A chapter's resources (images, CSS) resolve
    /// relative to this, which is what the web view is given read access to.
    public let base: URL
    public let title: String
    public let chapters: [Chapter]
    public let contents: [TOCEntry]

    public struct Chapter: Identifiable, Hashable, Sendable {
        /// The chapter's path relative to the unpacked root — its identity,
        /// and what an annotation names when it says where it was written.
        public let id: String
        public let url: URL
        /// The manifest id, so the table of contents can find it.
        public let manifestID: String
    }

    /// One line in the book's own table of contents.
    public struct TOCEntry: Identifiable, Hashable, Sendable {
        public let id: String
        public let label: String
        /// Which chapter it lands in, when the book's spine holds it.
        public let chapterIndex: Int?
        /// The id within that chapter, when the entry points inside one.
        public let fragment: String?
        /// How deep the entry sits in the contents tree, 0 for the top.
        public let depth: Int
    }

    public func chapterIndex(forPath path: String) -> Int? {
        chapters.firstIndex { $0.id == path }
    }
}

public nonisolated enum EPUBPackage {

    /// Opens a book for reading: unpacks it if it has not been unpacked
    /// already, then reads its spine and contents.
    ///
    /// - Parameters:
    ///   - url: the `.epub` file, which is only ever read.
    ///   - cache: the folder to unpack into — one per book, named by its
    ///     content hash, so a book is unpacked once and reopened instantly.
    public static func open(_ url: URL, unpackedInto cache: URL) throws -> EPUBBook {
        let zip = try ZipReader(url: url)
        guard let opfPath = zip.rootFilePath() else { throw EPUBError.corruptContainer }

        // Unpack only when the cache is not already good — reopening a book
        // should cost nothing.
        let opfOnDisk = cache.appendingPathComponent(opfPath)
        if !FileManager.default.fileExists(atPath: opfOnDisk.path) {
            try unpack(zip, into: cache)
        }

        guard let opfData = try? Data(contentsOf: opfOnDisk) else {
            throw EPUBError.corruptContainer
        }
        let opf = String(decoding: opfData, as: UTF8.self)
        let opfDirectory = (opfPath as NSString).deletingLastPathComponent

        let manifest = manifestItems(in: opf)
        let spine = spineOrder(in: opf)
        var chapters: [EPUBBook.Chapter] = []
        for id in spine {
            guard let item = manifest[id] else { continue }
            let path = joined(opfDirectory, item.href)
            let fileURL = cache.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            chapters.append(EPUBBook.Chapter(id: path, url: fileURL, manifestID: id))
        }
        // A book with no usable spine still opens on whatever documents it
        // has, in manifest order — better a readable book than an error.
        if chapters.isEmpty {
            for (id, item) in manifest where item.isContentDocument {
                let path = joined(opfDirectory, item.href)
                let fileURL = cache.appendingPathComponent(path)
                guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
                chapters.append(EPUBBook.Chapter(id: path, url: fileURL, manifestID: id))
            }
            chapters.sort { $0.id < $1.id }
        }
        guard !chapters.isEmpty else { throw EPUBError.corruptContainer }

        let title = EPUBMetadata.firstTagText(in: opf, tag: "dc:title")
            ?? url.deletingPathExtension().lastPathComponent
        let contents = tableOfContents(opf: opf, manifest: manifest, opfDirectory: opfDirectory,
                                       cache: cache, chapters: chapters)
        return EPUBBook(base: cache, title: title, chapters: chapters, contents: contents)
    }

    /// The folder a book unpacks into: one per book, by its content hash.
    public static func cacheFolder(forContentHash hash: String) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("EPUBs", isDirectory: true)
            .appendingPathComponent(hash, isDirectory: true)
    }

    /// A book's own cover image, straight out of the file — the picture the
    /// publisher chose. EPUB 3 marks the manifest item `cover-image`; EPUB 2
    /// names it in a `<meta name="cover" content="…">`. Nil when the book
    /// carries none, which plenty do.
    public static func coverImageData(at url: URL) -> Data? {
        guard let zip = try? ZipReader(url: url),
              let opfPath = zip.rootFilePath(),
              let opfData = zip.entry(opfPath)
        else { return nil }
        let opf = String(decoding: opfData, as: UTF8.self)
        let manifest = manifestItems(in: opf)
        let opfDirectory = (opfPath as NSString).deletingLastPathComponent

        // EPUB 3: the item says it is the cover.
        if let item = manifest.values.first(where: { $0.properties.contains("cover-image") }) {
            if let data = zip.entry(joined(opfDirectory, item.href)) { return data }
        }
        // EPUB 2: the metadata names the item that is.
        for tag in tags(named: "meta", in: opf)
        where attribute("name", in: tag)?.lowercased() == "cover" {
            guard let id = attribute("content", in: tag), let item = manifest[id] else { continue }
            if let data = zip.entry(joined(opfDirectory, item.href)) { return data }
        }
        // Last resort: an image in the manifest that calls itself a cover.
        for (id, item) in manifest where item.mediaType.hasPrefix("image/") {
            let name = (id + " " + item.href).lowercased()
            guard name.contains("cover") else { continue }
            if let data = zip.entry(joined(opfDirectory, item.href)) { return data }
        }
        return nil
    }

    // MARK: - Unpacking

    private static func unpack(_ zip: ZipReader, into directory: URL) throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: directory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in zip.entryNames {
            // Directory placeholders carry no bytes; refuse any name that
            // would escape the unpack directory.
            guard !name.isEmpty, !name.hasSuffix("/"),
                  !name.split(separator: "/").contains("..") else { continue }
            guard let data = zip.entry(name) else { continue }
            let destination = directory.appendingPathComponent(name)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            try data.write(to: destination)
        }
    }

    // MARK: - The package document

    struct ManifestItem {
        let href: String
        let mediaType: String
        let properties: String

        var isContentDocument: Bool {
            mediaType.contains("xhtml") || mediaType.contains("html")
        }
        var isNavigation: Bool { properties.contains("nav") }
    }

    /// The manifest, by item id.
    static func manifestItems(in opf: String) -> [String: ManifestItem] {
        var items: [String: ManifestItem] = [:]
        for tag in tags(named: "item", in: opf) {
            guard let id = attribute("id", in: tag), let href = attribute("href", in: tag) else { continue }
            items[id] = ManifestItem(href: href.removingPercentEncoding ?? href,
                                     mediaType: attribute("media-type", in: tag) ?? "",
                                     properties: attribute("properties", in: tag) ?? "")
        }
        return items
    }

    /// The spine: the manifest ids of the content documents, in reading
    /// order. Documents marked `linear="no"` are skipped — they are the
    /// book's asides, reached from its contents rather than by turning.
    static func spineOrder(in opf: String) -> [String] {
        tags(named: "itemref", in: opf).compactMap { tag in
            guard let idref = attribute("idref", in: tag) else { return nil }
            if attribute("linear", in: tag)?.lowercased() == "no" { return nil }
            return idref
        }
    }

    // MARK: - The table of contents

    private static func tableOfContents(opf: String, manifest: [String: ManifestItem],
                                        opfDirectory: String, cache: URL,
                                        chapters: [EPUBBook.Chapter]) -> [EPUBBook.TOCEntry] {
        // EPUB 3: the navigation document, named in the manifest.
        if let navItem = manifest.values.first(where: { $0.isNavigation }) {
            let path = joined(opfDirectory, navItem.href)
            if let data = try? Data(contentsOf: cache.appendingPathComponent(path)) {
                let entries = navEntries(in: String(decoding: data, as: UTF8.self),
                                         relativeTo: (path as NSString).deletingLastPathComponent,
                                         chapters: chapters)
                if !entries.isEmpty { return entries }
            }
        }
        // EPUB 2: the NCX, named by the spine's `toc` attribute.
        if let spineTag = tags(named: "spine", in: opf).first,
           let tocID = attribute("toc", in: spineTag),
           let ncx = manifest[tocID] {
            let path = joined(opfDirectory, ncx.href)
            if let data = try? Data(contentsOf: cache.appendingPathComponent(path)) {
                return ncxEntries(in: String(decoding: data, as: UTF8.self),
                                  relativeTo: (path as NSString).deletingLastPathComponent,
                                  chapters: chapters)
            }
        }
        return []
    }

    /// The EPUB 3 navigation document: the `toc` nav's links, in order, with
    /// nesting depth from the list nesting.
    static func navEntries(in xhtml: String, relativeTo directory: String,
                           chapters: [EPUBBook.Chapter]) -> [EPUBBook.TOCEntry] {
        // The toc nav, when the document marks one; else the whole document,
        // which for a nav-only file is the same thing.
        var scope = xhtml
        if let range = xhtml.range(of: #"<nav[^>]*epub:type\s*=\s*"[^"]*toc[^"]*"[^>]*>"#,
                                   options: [.regularExpression, .caseInsensitive]),
           let end = xhtml.range(of: "</nav>", options: .caseInsensitive,
                                 range: range.upperBound..<xhtml.endIndex) {
            scope = String(xhtml[range.upperBound..<end.lowerBound])
        }

        var entries: [EPUBBook.TOCEntry] = []
        var depth = 0
        var index = scope.startIndex
        while index < scope.endIndex {
            if let open = scope.range(of: "<ol", options: .caseInsensitive, range: index..<scope.endIndex),
               let anchor = scope.range(of: "<a ", options: .caseInsensitive, range: index..<scope.endIndex),
               open.lowerBound < anchor.lowerBound {
                depth += 1
                index = open.upperBound
                continue
            }
            if let close = scope.range(of: "</ol>", options: .caseInsensitive, range: index..<scope.endIndex),
               let anchor = scope.range(of: "<a ", options: .caseInsensitive, range: index..<scope.endIndex),
               close.lowerBound < anchor.lowerBound {
                depth = max(0, depth - 1)
                index = close.upperBound
                continue
            }
            guard let anchor = scope.range(of: "<a ", options: .caseInsensitive, range: index..<scope.endIndex),
                  let tagEnd = scope.range(of: ">", range: anchor.upperBound..<scope.endIndex),
                  let close = scope.range(of: "</a>", options: .caseInsensitive,
                                          range: tagEnd.upperBound..<scope.endIndex)
            else { break }
            let tag = String(scope[anchor.lowerBound..<tagEnd.upperBound])
            let label = plainText(String(scope[tagEnd.upperBound..<close.lowerBound]))
            if let href = attribute("href", in: tag), !label.isEmpty {
                entries.append(entry(href: href, label: label, depth: max(0, depth - 1),
                                     directory: directory, chapters: chapters,
                                     ordinal: entries.count))
            }
            index = close.upperBound
        }
        return entries
    }

    /// The EPUB 2 NCX: navPoints, with `playOrder` as written.
    static func ncxEntries(in xml: String, relativeTo directory: String,
                           chapters: [EPUBBook.Chapter]) -> [EPUBBook.TOCEntry] {
        var entries: [EPUBBook.TOCEntry] = []
        var index = xml.startIndex
        while let point = xml.range(of: "<navPoint", options: .caseInsensitive,
                                    range: index..<xml.endIndex) {
            let rest = point.upperBound..<xml.endIndex
            guard let labelOpen = xml.range(of: "<text", options: .caseInsensitive, range: rest),
                  let labelStart = xml.range(of: ">", range: labelOpen.upperBound..<xml.endIndex),
                  let labelEnd = xml.range(of: "</text>", options: .caseInsensitive,
                                           range: labelStart.upperBound..<xml.endIndex),
                  let contentTag = xml.range(of: "<content", options: .caseInsensitive,
                                             range: labelEnd.upperBound..<xml.endIndex),
                  let contentEnd = xml.range(of: ">", range: contentTag.upperBound..<xml.endIndex)
            else { break }
            let label = plainText(String(xml[labelStart.upperBound..<labelEnd.lowerBound]))
            let tag = String(xml[contentTag.lowerBound..<contentEnd.upperBound])
            if let src = attribute("src", in: tag), !label.isEmpty {
                entries.append(entry(href: src, label: label, depth: 0,
                                     directory: directory, chapters: chapters,
                                     ordinal: entries.count))
            }
            index = contentEnd.upperBound
        }
        return entries
    }

    private static func entry(href: String, label: String, depth: Int,
                              directory: String, chapters: [EPUBBook.Chapter],
                              ordinal: Int) -> EPUBBook.TOCEntry {
        let parts = href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(parts.first ?? "")
        let fragment = parts.count > 1 ? String(parts[1]) : nil
        let decoded = path.removingPercentEncoding ?? path
        let full = joined(directory, decoded)
        let index = chapters.firstIndex { $0.id == full }
        return EPUBBook.TOCEntry(id: "\(ordinal)-\(href)", label: label,
                                 chapterIndex: index, fragment: fragment, depth: depth)
    }

    // MARK: - Small XML helpers

    /// Every `<name …>` tag in the document, as written.
    static func tags(named name: String, in xml: String) -> [String] {
        var found: [String] = []
        var index = xml.startIndex
        while let open = xml.range(of: "<\(name)", options: .caseInsensitive,
                                   range: index..<xml.endIndex) {
            // `<item` must not match `<itemref`.
            let afterName = open.upperBound
            if afterName < xml.endIndex {
                let next = xml[afterName]
                guard next == " " || next == ">" || next == "\n" || next == "\r" || next == "\t" || next == "/"
                else { index = open.upperBound; continue }
            }
            guard let end = xml.range(of: ">", range: open.upperBound..<xml.endIndex) else { break }
            found.append(String(xml[open.lowerBound..<end.upperBound]))
            index = end.upperBound
        }
        return found
    }

    /// One attribute's value from a tag, single or double quoted. The name
    /// must start the attribute: a search for `type` must not be answered by
    /// `media-type`, nor `src` by `data-src`, so a hyphen counts as part of
    /// the name rather than as a word boundary.
    static func attribute(_ name: String, in tag: String) -> String? {
        for pattern in ["\(name)\\s*=\\s*\"[^\"]*\"", "\(name)\\s*=\\s*'[^']*'"] {
            guard let range = tag.range(of: "(?<![\\w-])" + pattern,
                                        options: [.regularExpression, .caseInsensitive])
            else { continue }
            let text = tag[range]
            guard let quote = text.firstIndex(where: { $0 == "\"" || $0 == "'" }) else { continue }
            let value = text[text.index(after: quote)..<text.index(before: text.endIndex)]
            return String(value)
        }
        return nil
    }

    /// `a/b` from `a` and `b`, with `a` empty meaning the root.
    static func joined(_ directory: String, _ path: String) -> String {
        guard !directory.isEmpty else { return path }
        return (directory as NSString).appendingPathComponent(path)
    }

    /// A label's words, with any markup inside it dropped.
    private static func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
