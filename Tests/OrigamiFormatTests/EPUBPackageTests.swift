import Testing
import Foundation
@testable import OrigamiFormat

/// The reading order and the contents are the two things a reader cannot
/// recover from if they are wrong: chapters out of order, or a contents that
/// lands nowhere.
@Suite("EPUB package")
struct EPUBPackageTests {

    private let opf3 = """
    <?xml version="1.0"?>
    <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
     <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Three Chapters</dc:title></metadata>
     <manifest>
      <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
      <item id="c1" href="text/one.xhtml" media-type="application/xhtml+xml"/>
      <item id="c2" href="text/two.xhtml" media-type="application/xhtml+xml"/>
      <item id="c3" href="text/three.xhtml" media-type="application/xhtml+xml"/>
      <item id="aside" href="text/aside.xhtml" media-type="application/xhtml+xml"/>
     </manifest>
     <spine>
      <itemref idref="c1"/>
      <itemref idref="c2"/>
      <itemref idref="aside" linear="no"/>
      <itemref idref="c3"/>
     </spine>
    </package>
    """

    private func chapters(_ paths: [String]) -> [EPUBBook.Chapter] {
        paths.enumerated().map { index, path in
            EPUBBook.Chapter(id: path, url: URL(fileURLWithPath: "/tmp/" + path),
                             manifestID: "c\(index)")
        }
    }

    @Test("The manifest is read by id, with its properties")
    func manifest() {
        let manifest = EPUBPackage.manifestItems(in: opf3)
        #expect(manifest.count == 5)
        #expect(manifest["c2"]?.href == "text/two.xhtml")
        #expect(manifest["nav"]?.isNavigation == true)
        #expect(manifest["c1"]?.isNavigation == false)
        #expect(manifest["c1"]?.isContentDocument == true)
    }

    @Test("The spine keeps the book's order, and leaves out what is not linear")
    func spine() {
        // `linear="no"` marks a book's asides — reached from the contents,
        // never by turning the page.
        #expect(EPUBPackage.spineOrder(in: opf3) == ["c1", "c2", "c3"])
    }

    @Test("An `<item>` is not an `<itemref>`")
    func tagNamesAreExact() {
        #expect(EPUBPackage.tags(named: "item", in: opf3).count == 5)
        #expect(EPUBPackage.tags(named: "itemref", in: opf3).count == 4)
    }

    @Test("Attributes are read in either quote, and only the one asked for")
    func attributes() {
        let tag = "<item id='c1' href=\"text/one.xhtml\" media-type=\"application/xhtml+xml\"/>"
        #expect(EPUBPackage.attribute("id", in: tag) == "c1")
        #expect(EPUBPackage.attribute("href", in: tag) == "text/one.xhtml")
        // `media-type` must not be answered by a search for `type`.
        #expect(EPUBPackage.attribute("type", in: tag) == nil)
    }

    @Test("An EPUB 3 navigation document gives labels, chapters, fragments and depth")
    func navigation() {
        let nav = """
        <html xmlns:epub="http://www.idpf.org/2007/ops"><body>
        <nav epub:type="toc"><ol>
         <li><a href="text/one.xhtml">One</a>
           <ol><li><a href="text/one.xhtml#part-b">One, part B</a></li></ol></li>
         <li><a href="text/two.xhtml">Two &amp; a half</a></li>
        </ol></nav></body></html>
        """
        let entries = EPUBPackage.navEntries(
            in: nav, relativeTo: "OEBPS",
            chapters: chapters(["OEBPS/text/one.xhtml", "OEBPS/text/two.xhtml"]))
        #expect(entries.count == 3)
        #expect(entries[0].label == "One")
        #expect(entries[0].chapterIndex == 0)
        #expect(entries[0].depth == 0)
        #expect(entries[1].label == "One, part B")
        #expect(entries[1].fragment == "part-b")
        #expect(entries[1].depth == 1)          // nested one list deep
        #expect(entries[2].label == "Two & a half")
        #expect(entries[2].chapterIndex == 1)
    }

    @Test("An EPUB 2 NCX gives the same shape")
    func ncx() {
        let ncx = """
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><navMap>
         <navPoint id="n1" playOrder="1"><navLabel><text>Beginnings</text></navLabel><content src="a.html"/></navPoint>
         <navPoint id="n2" playOrder="2"><navLabel><text>Endings</text></navLabel><content src="b.html#end"/></navPoint>
        </navMap></ncx>
        """
        let entries = EPUBPackage.ncxEntries(in: ncx, relativeTo: "",
                                             chapters: chapters(["a.html", "b.html"]))
        #expect(entries.count == 2)
        #expect(entries[0].label == "Beginnings")
        #expect(entries[0].chapterIndex == 0)
        #expect(entries[1].label == "Endings")
        #expect(entries[1].chapterIndex == 1)
        #expect(entries[1].fragment == "end")
    }

    @Test("A contents entry pointing outside the spine still lists, landing nowhere")
    func entryWithNoChapter() {
        let nav = """
        <nav epub:type="toc"><ol><li><a href="missing.xhtml">Gone</a></li></ol></nav>
        """
        let entries = EPUBPackage.navEntries(in: nav, relativeTo: "",
                                             chapters: chapters(["a.html"]))
        #expect(entries.count == 1)
        #expect(entries[0].chapterIndex == nil)
    }

    @Test("Paths join under the package document's own folder")
    func pathJoining() {
        #expect(EPUBPackage.joined("OEBPS", "text/one.xhtml") == "OEBPS/text/one.xhtml")
        #expect(EPUBPackage.joined("", "package.opf") == "package.opf")
    }
}
