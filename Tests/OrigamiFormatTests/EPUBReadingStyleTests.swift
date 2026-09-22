import Testing
import Foundation
@testable import OrigamiFormat

/// A reading can be wrong in ways that are invisible in a screenshot of the
/// light appearance: unreadable in the dark, unmovable in size, or quietly
/// overruled by the book's own stylesheet. These are those cases.
@Suite("EPUB reading style")
struct EPUBReadingStyleTests {

    private func css(_ settings: EPUBReadingStyle.Settings) -> String {
        EPUBReadingStyle.css(settings)
    }

    @Test("A light reading is dark ink on light paper")
    func lightReading() {
        let sheet = css(.init(dark: false))
        #expect(sheet.contains("color-scheme: light"))
        #expect(sheet.contains("background: #fbfaf8"))
        #expect(sheet.contains("color: #16171a"))
    }

    @Test("A dark reading states both colours, so a book that sets neither is readable")
    func darkReading() {
        let sheet = css(.init(dark: true))
        #expect(sheet.contains("color-scheme: dark"))
        #expect(sheet.contains("background: #1c1d1f"))
        #expect(sheet.contains("color: #e8e6e3"))
    }

    @Test("Only a dark reading clears the book's own backgrounds")
    func darkClearsBookBackgrounds() {
        // A white box behind a paragraph is the commonest way a book breaks
        // a dark reading — and in the light it must be left alone.
        #expect(css(.init(dark: true)).contains("background-color: transparent !important"))
        #expect(!css(.init(dark: false)).contains("background-color: transparent !important"))
    }

    @Test("A theme's own palette reaches the page")
    func themePalette() {
        let sepia = css(.init(theme: .sepia))
        #expect(sepia.contains("background: #eee2cc"))
        #expect(sepia.contains("color: #32281d"))
        // Black on yellow, as macular readers asked for.
        let macular = css(.init(theme: .macular))
        #expect(macular.contains("background: #ffff00"))
        #expect(macular.contains("color: #000000"))
    }

    @Test("A dark theme in a light window still reads as dark")
    func darkThemeInLightWindow() {
        // Night's light-appearance paper is pale, but Solarized's dark
        // paper in a dark window must still trigger the corrections — the
        // judgement is the colour's, not the system's.
        #expect(EPUBReadingTheme.solarized.paperIsDark(dark: true))
        #expect(!EPUBReadingTheme.solarized.paperIsDark(dark: false))
        let settings = EPUBReadingStyle.Settings(theme: .solarized, dark: true)
        #expect(settings.readsDark)
        #expect(css(settings).contains("background-color: transparent !important"))
    }

    @Test("The reader's text size and leading are the page's")
    func textScaleAndLeading() {
        #expect(css(.init(scale: 1)).contains("font-size: 17.0px"))
        #expect(css(.init(scale: 1.6)).contains("font-size: 27.2px"))
        #expect(css(.init(scale: 0.8)).contains("font-size: 13.6px"))
        // Nothing a caller can pass may collapse the words to nothing.
        #expect(css(.init(scale: 0)).contains("font-size: 8.5px"))
        #expect(css(.init(lineSpacing: 2.0)).contains("line-height: 2.00"))
        // The controls stop at 1.2; the stylesheet defends at 1.1 anyway, so
        // a value from anywhere else can still be read.
        #expect(css(.init(lineSpacing: 0.1)).contains("line-height: 1.10"))
    }

    @Test("Each layout sets the measure it promises")
    func layouts() {
        #expect(css(.init(layout: .scrolling)).contains("max-width: 34em"))
        #expect(css(.init(layout: .fullWidth)).contains("max-width: none"))
        #expect(css(.init(layout: .focus)).contains("max-width: 30em"))

        // Horizontal is pages side by side: columns a measure wide, a page
        // tall, turned sideways. Where the body scrolls — macOS — the
        // overflow and the page-tall height are the body's.
        let horizontal = css(.init(layout: .horizontal, horizontalScroller: .body))
        #expect(horizontal.contains("column-width: 30em"))
        #expect(horizontal.contains("height: 100vh"))
        #expect(horizontal.contains("overflow-x: auto"))
        #expect(horizontal.contains("overflow-y: hidden"))
        #expect(EPUBReadingLayout.horizontal.isPaged)
        #expect(!EPUBReadingLayout.scrolling.isPaged)
    }

    @Test("Where the body cannot scroll, nothing scrolls — the columns are moved")
    func horizontalOnTheViewport() {
        // iOS and visionOS: WebKit ignores overflow on the body, so asking
        // for it there produces no sideways scroller at all. Rather than
        // move the overflow to html and snap a scroll view afterwards, the
        // columns are carried by a transform — see `pagedByTransform`.
        let viewport = css(.init(layout: .horizontal, horizontalScroller: .viewport))
        #expect(viewport.contains("column-width: 30em"))
        // The body claims no overflow it will not be given…
        let body = viewport.components(separatedBy: "body {").last ?? ""
        #expect(!body.contains("overflow-x"))
        // …and does not measure itself against a viewport unit that moves.
        #expect(!viewport.contains("height: 100vh"))
        // html gives the columns their definite height, and clips them.
        let html = viewport.components(separatedBy: "html {").last?
            .components(separatedBy: "}").first ?? ""
        #expect(html.contains("height: 100%"))
    }

    @Test("A tablet in Horizontal reads as a book: two pages side by side")
    func spreadOfTwo() {
        let viewport = css(.init(layout: .horizontal, horizontalScroller: .viewport))
        #expect(viewport.contains("@media (min-width: 700px)"))
        #expect(viewport.contains("column-count: 2"))
        // The measure is overridden, or the count would not win.
        #expect(viewport.contains("column-width: auto"))

        // macOS sizes its own window, so the measure keeps answering to it.
        let body = css(.init(layout: .horizontal, horizontalScroller: .body))
        #expect(!body.contains("column-count"))

        // And no other layout is a spread.
        for layout in EPUBReadingLayout.allCases where layout != .horizontal {
            #expect(!css(.init(layout: layout, horizontalScroller: .viewport))
                .contains("column-count"))
        }
    }

    @Test("Paged columns are moved by a transform, so there is no part way")
    func pagedByTransform() {
        let viewport = css(.init(layout: .horizontal, horizontalScroller: .viewport))
        // The columns are carried by a transition, not by a scroller…
        #expect(viewport.contains("transform: translateX(0px)"))
        #expect(viewport.contains("transition: transform"))
        // …and there is no scroller to be left between two columns.
        let html = viewport.components(separatedBy: "html {").last?
            .components(separatedBy: "}").first ?? ""
        #expect(html.contains("overflow: hidden"))
        #expect(!html.contains("overflow-x: auto"))
    }

    @Test("A swipe steps one column, and only when it means to")
    func swipeIntent() {
        let script = EPUBReadingStyle.columnPagingScript
        // An index, clamped — the reading is at a column or it is nowhere.
        #expect(script.contains("Math.min(Math.max(0, index + delta), last)"))
        // Far enough, and more sideways than up.
        #expect(script.contains("Math.abs(dx) < 40"))
        #expect(script.contains("Math.abs(dx) < Math.abs(dy)"))
        // Selecting words is not turning a page.
        #expect(script.contains("String(selection).trim()"))
        // Fingers left brings the next column in.
        #expect(script.contains("turn(dx < 0 ? 1 : -1)"))
        // A rotation keeps the reader on the column they were reading.
        #expect(script.contains("addEventListener('resize'"))
        #expect(script.contains("if (index > last) { index = last; }"))
        // Injected twice over one page must not make two pagers.
        #expect(script.contains("if (window.__origamiPaging) { return; }"))
    }

    @Test("An arrow and a finger move the reading the same way")
    func arrowsUseThePager() {
        let forward = EPUBReadingStyle.turnPageScript(forward: true)
        #expect(forward.contains("window.__origamiTurn"))
        // And where nothing is paged, the old scrolling still stands.
        #expect(forward.contains("body.scrollBy"))
        #expect(forward.contains("window.scrollBy"))
    }

    @Test("The page reports what one column measures, and again when resized")
    func columnMetrics() {
        let script = EPUBReadingStyle.columnMetricsScript
        // The pitch is a column plus the gap after it — what a swipe of one
        // column has to move by.
        #expect(script.contains("pitch: width + gap"))
        #expect(script.contains("kind: 'metrics'"))
        // Read from the page, because only the page knows what the media
        // query, the stylesheet and the reading's padding resolved to.
        #expect(script.contains("style.columnCount"))
        #expect(script.contains("style.columnGap"))
        #expect(script.contains("paddingLeft"))
        // Rotating the iPad changes all of it.
        #expect(script.contains("addEventListener('resize'"))
    }

    @Test("Only Horizontal touches the viewport's overflow")
    func otherLayoutsLeaveTheViewportAlone() {
        for layout in EPUBReadingLayout.allCases where layout != .horizontal {
            let sheet = css(.init(layout: layout, horizontalScroller: .viewport))
            let html = sheet.components(separatedBy: "html {").last?
                .components(separatedBy: "}").first ?? ""
            #expect(!html.contains("overflow-x"), "\(layout.rawValue) should not touch the viewport")
        }
    }

    @Test("A page turn moves whichever element actually scrolls")
    func pageTurnFindsTheScroller() {
        let forward = EPUBReadingStyle.turnPageScript(forward: true)
        // The body when it has its own scroller, the window when it has not
        // — decided in the page, because it differs by platform.
        #expect(forward.contains("body.scrollWidth > body.clientWidth"))
        #expect(forward.contains("body.scrollBy"))
        #expect(forward.contains("window.scrollBy"))
        let back = EPUBReadingStyle.turnPageScript(forward: false)
        #expect(back.contains("-1"))
    }

    @Test("A face is asked for only when the reader asked for one")
    func faces() {
        // The book's own face is the default, and saying nothing is how CSS
        // leaves it alone.
        #expect(!css(.init(bodyFont: .book)).contains("font-family:"))
        #expect(css(.init(bodyFont: .serif)).contains("'New York'"))
        #expect(css(.init(headingFont: .rounded)).contains("ui-rounded"))
        #expect(EPUBReadingFont.book.cssFamily == nil)
    }

    @Test("The paper behind the page matches the paper in it")
    func paperMatchesTheStylesheet() {
        // #1c1d1f is (28, 29, 31)/255; #eee2cc is (238, 226, 204)/255.
        let dark = EPUBReadingStyle.paper(.init(dark: true))
        #expect(abs(dark.red - 28.0 / 255) < 0.005)
        #expect(abs(dark.blue - 31.0 / 255) < 0.005)
        let sepia = EPUBReadingStyle.paper(.init(theme: .sepia))
        #expect(abs(sepia.red - 238.0 / 255) < 0.005)
        #expect(abs(sepia.green - 226.0 / 255) < 0.005)
        #expect(abs(sepia.blue - 204.0 / 255) < 0.005)
    }

    @Test("Every theme is legible: ink and paper are never the same")
    func everyThemeHasContrast() {
        for theme in EPUBReadingTheme.allCases {
            for dark in [false, true] {
                let paper = EPUBReadingTheme.luminance(of: theme.paperHex(dark: dark))
                let ink = EPUBReadingTheme.luminance(of: theme.inkHex(dark: dark))
                #expect(abs(paper - ink) > 0.15,
                        "\(theme.displayName) (\(dark ? "dark" : "light")) has too little contrast")
            }
        }
    }

    @Test("The reading keeps images inside it, whatever the layout")
    func imagesAndCode() {
        for layout in EPUBReadingLayout.allCases {
            let sheet = css(.init(layout: layout))
            #expect(sheet.contains("img, svg, video { max-width: 100%; height: auto; }"))
            #expect(sheet.contains("white-space: pre-wrap"))
        }
    }

    @Test("Turning a page moves by one screenful, in the direction asked")
    func pageTurns() {
        // The direction is now carried in the step rather than in the
        // literal, so the same two lines serve whichever element scrolls.
        let forward = EPUBReadingStyle.turnPageScript(forward: true)
        #expect(forward.contains("var sign = 1"))
        #expect(forward.contains("(body.clientWidth || window.innerWidth) * sign"))
        #expect(forward.contains("left: step"))
        #expect(EPUBReadingStyle.turnPageScript(forward: false).contains("var sign = -1"))
    }

    @Test("The style script survives a stylesheet with backticks or backslashes")
    func styleScriptEscaping() {
        // The CSS goes into a JavaScript template literal; an unescaped
        // backtick would end it early and break every later rule.
        let script = EPUBReadingStyle.styleScript(css: "body::after { content: \"`\\\\\" }")
        #expect(script.contains("\\`"))
        #expect(script.contains("\\\\"))
        #expect(script.contains("reader-typography"))
        // Appended to <head> when there is one, <html> when there is not.
        #expect(script.contains("document.head || document.documentElement"))
    }

    @Test("The dark ink pass only lifts ink that is too dark to read")
    func darkInkThreshold() {
        let script = EPUBReadingStyle.darkInkScript
        #expect(script.contains("0.2126"))          // the luminance it judges by
        #expect(script.contains("value < 0.35"))    // and the line it draws
        #expect(script.contains("getComputedStyle(document.body).color"))
    }
}
