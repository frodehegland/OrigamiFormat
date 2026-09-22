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

    @Test("A column holds as many whole lines as it can")
    func fitsWholeLines() {
        let script = EPUBReadingStyle.fitLinesScript
        // A column with a definite height shows only the lines that fit,
        // and what is left under the last one is wasted — up to a whole
        // line of it, on top of the stylesheet's padding. That together is
        // what looked like room for another line.
        #expect(script.contains("Math.floor(available / line)"))
        // The leading is read, never assumed: the reader sets it, and a
        // book may set its own.
        #expect(script.contains("parseFloat(style.lineHeight)"))
        // Measured from the stylesheet's own value, not from whatever the
        // last pass left, or each pass would shrink the text a little more.
        #expect(script.contains("element.style.paddingBottom = ''"))
        // Both readings: the section boxes, or the body's own columns.
        #expect(script.contains("getElementsByClassName('origami-column')"))
        #expect(script.contains("columnCount !== 'auto'"))
        // Rotating the iPad changes the height, so it fits again.
        #expect(script.contains("addEventListener('resize'"))

        // And the stylesheet leaves it room to claim: a small bottom
        // padding to grow from rather than 2.5em of fixed air.
        for layout in [EPUBReadingLayout.horizontal, .columns] {
            #expect(css(.init(layout: layout, horizontalScroller: .viewport))
                .contains("0.75em"), "\(layout.rawValue)")
        }
    }

    @Test("The reader's measure beats the book's own stylesheet")
    func measureIsTheReaders() {
        // The article we test against ships
        // `body { max-width: 38em; margin: 1em auto }`, and a book only has
        // to write `html body` — one step more specific than our `body` —
        // to win the cascade and put its margins back. Reader offers the
        // reader a measure; that cannot depend on what a publisher wrote.
        for layout in EPUBReadingLayout.allCases {
            let sheet = css(.init(layout: layout))
            let body = sheet.components(separatedBy: "body {").dropFirst().first?
                .components(separatedBy: "}").first ?? ""
            #expect(body.contains("max-width") , "\(layout.rawValue) states no measure")
            #expect(body.contains("!important"), "\(layout.rawValue) can be overruled")
        }
    }

    @Test("Focus takes a share of the view, as Origami Text does")
    func focusIsAShare() {
        let sheet = css(.init(layout: .focus))
        // Origami Text's reading column is 680pt in a window and 67% of a
        // built-in display in full screen. A fixed measure was right for
        // one screen and a thin ribbon on the rest.
        #expect(sheet.contains("max(22em, 67vw)"))
        // Still centred, and still the narrower reading — Focus is the
        // words alone, so it does not simply become Scroll.
        #expect(sheet.contains("margin: 0 auto !important"))
        #expect(!css(.init(layout: .scrolling)).contains("67vw"))
        // Scroll fills: no measure to leave space beside.
        #expect(css(.init(layout: .scrolling)).contains("max-width: none !important"))
    }

    @Test("Links read in the body's ink, not in blue")
    func linksAreNotBlue() {
        // A scholarly page is dense with links — references, glossary
        // terms, cross-references — and in blue it becomes a map of the
        // markup rather than a reading.
        for dark in [false, true] {
            let sheet = css(.init(dark: dark))
            let ink = EPUBReadingTheme.system.inkHex(dark: dark)
            #expect(sheet.contains("a, a:visited { color: \(ink); }"))
        }
        // No blue anywhere in the stylesheet any more.
        #expect(!css(.init()).contains("#0a58c2"))
        #expect(!css(.init(dark: true)).contains("#7fb6ff"))
        // A theme's own ink is used where a theme sets one.
        let sepia = css(.init(theme: .sepia))
        #expect(sepia.contains("a, a:visited { color: \(EPUBReadingTheme.sepia.inkHex(dark: false)); }"))
    }

    @Test("Each layout sets the measure it promises")
    func layouts() {
        // Full Width is gone: it offered the same reading as Scroll with
        // the margins taken off, which is a setting rather than a way of
        // reading. Scroll is the one vertical reading, and it is the one
        // that uses the screen.
        #expect(EPUBReadingLayout.allCases.count == 4)
        #expect(EPUBReadingLayout.scrolling.displayName == "Scroll")
        #expect(EPUBReadingLayout(rawValue: "fullWidth") == nil)
        let scroll = css(.init(layout: .scrolling))
        #expect(scroll.contains("max-width: none"))
        // A small margin either side, and equal — 2em each.
        #expect(scroll.contains("padding: 2.5em 2em 5em"))
        #expect(!scroll.contains("margin: 0 auto"))
        // Focus keeps its narrow measure: that reading is the words alone,
        // and a line the width of a display is not that.
        #expect(css(.init(layout: .focus)).contains("max(22em, 67vw)"))
        #expect(css(.init(layout: .focus)).contains("max(22em, 67vw)"))

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

    @Test("Columns is a row of section boxes, each scrolled within itself")
    func sectionColumns() {
        let sheet = css(.init(layout: .columns))
        // A row of boxes, not a flow.
        #expect(sheet.contains("display: flex"))
        #expect(sheet.contains("flex-direction: row"))
        #expect(!sheet.contains("column-count"))
        // A section taller than the screen scrolls inside its own box
        // rather than spilling into the next one.
        // The base rule, not one of the width overrides that follow it.
        let column = sheet.components(separatedBy: ".origami-column {")
            .dropFirst().first?
            .components(separatedBy: "}").first ?? ""
        #expect(column.contains("overflow-y: auto"))
        #expect(column.contains("height: 100%"))
        // CSS owns the arithmetic; the page supplies the count, because
        // only the page knows how many sections the book has.
        #expect(column.contains("calc(100% / var(--origami-columns, 1))"))
        // And with no count supplied it is one whole column, never a
        // fraction of one.
        #expect(column.contains("var(--origami-columns, 1)"))
        // Moved by transform like the other paged reading.
        #expect(sheet.contains("transition: transform"))

        // Horizontal is still a flow, and keeps its columns.
        let flowing = css(.init(layout: .horizontal, horizontalScroller: .viewport))
        #expect(!flowing.contains("display: flex"))
        #expect(flowing.contains("column-count: 2"))
        // And no other layout grows section boxes.
        for layout in EPUBReadingLayout.allCases where layout != .columns {
            #expect(!css(.init(layout: layout)).contains(".origami-column"))
        }
    }

    @Test("Columns follows Origami Text's rule, with a floor for a phone")
    func origamiColumnRule() {
        // The rule the page applies, restated here so a change to it has
        // to be a change to this too. Origami Text: two at least, one more
        // for every 460 points, never more than the book has sections.
        func shown(width: Double, sections: Int) -> Int {
            var count = min(max(Int(width / 460), 2), sections)
            if count > 1 && width / Double(count) < 320 {
                count = max(1, Int(width / 320))
            }
            return count
        }
        // An iPad mini is two, whichever way it is held — the ask.
        #expect(shown(width: 744, sections: 14) == 2)
        #expect(shown(width: 1133, sections: 14) == 2)
        // A Mac window earns a third at Origami Text's 460-point step.
        #expect(shown(width: 1440, sections: 14) == 3)
        // Never more columns than sections: three columns for a
        // two-section chapter would leave a third of the view empty.
        #expect(shown(width: 1800, sections: 2) == 2)
        #expect(shown(width: 1800, sections: 1) == 1)
        // The departure: Origami Text's floor of two would put two
        // 196-point columns on a phone.
        #expect(shown(width: 393, sections: 14) == 1)
        // And a column is never narrower than a line needs.
        for width in stride(from: 320.0, through: 2200.0, by: 1.0) {
            let count = shown(width: width, sections: 40)
            #expect(width / Double(count) >= 320,
                    "\(Int(width))pt → \(count) columns")
        }
    }

    @Test("A button turns the spread; a swipe nudges one column")
    func spreadVersusNudge() {
        let script = EPUBReadingStyle.columnPagingScript
        // Origami Text's line: "the buttons turn whole spreads; the swipe
        // nudges."
        #expect(script.contains("__origamiTurnSpread"))
        #expect(script.contains("turn(direction * Math.max(1, shown))"))
        // The swipe still moves exactly one.
        #expect(script.contains("turn(dx < 0 ? 1 : -1)"))
        // And the arrows and keys ask for the spread.
        #expect(EPUBReadingStyle.turnPageScript(forward: true)
            .contains("__origamiTurnSpread"))
        // How many stand across is reported, so the foot can say "3–5 of 12".
        #expect(script.contains("shown: shown"))
    }

    @Test("Every paged reading is clipped and sized by html, on every platform")
    func pagedReadingsAreClipped() {
        // The fault this guards: with no height on html, `body { height:
        // 100% }` resolved against auto and the flex row had nothing to
        // stretch to, so the columns grew to their content rather than the
        // screen — and with nothing clipping, the document scrolled
        // sideways and the transform slid the reading off to the left.
        func html(_ settings: EPUBReadingStyle.Settings) -> String {
            EPUBReadingStyle.css(settings)
                .components(separatedBy: "html {").last?
                .components(separatedBy: "}").first ?? ""
        }
        // Columns is paged on both platforms: its columns are real boxes,
        // so there was never a body-overflow question to answer.
        for scroller in EPUBReadingStyle.HorizontalScroller.allCases {
            let sheet = html(.init(layout: .columns, horizontalScroller: scroller))
            #expect(sheet.contains("height: 100%"), "columns/\(scroller.rawValue)")
            #expect(sheet.contains("overflow: hidden"), "columns/\(scroller.rawValue)")
        }
        // Horizontal only where the viewport is the scroller; where the
        // body scrolls, html must stay out of the way.
        #expect(html(.init(layout: .horizontal, horizontalScroller: .viewport))
            .contains("overflow: hidden"))
        #expect(!html(.init(layout: .horizontal, horizontalScroller: .body))
            .contains("overflow: hidden"))
        // And an unpaged reading is never clipped, or it could not scroll.
        for layout in EPUBReadingLayout.allCases where !layout.isPaged {
            #expect(!html(.init(layout: layout)).contains("overflow: hidden"),
                    "\(layout.rawValue)")
        }
    }

    @Test("Columns and Horizontal are both paged; only Columns is sectioned")
    func layoutKinds() {
        #expect(EPUBReadingLayout.columns.isPaged)
        #expect(EPUBReadingLayout.horizontal.isPaged)
        #expect(EPUBReadingLayout.columns.isSectioned)
        #expect(!EPUBReadingLayout.horizontal.isSectioned)
        #expect(!EPUBReadingLayout.scrolling.isPaged)
        #expect(EPUBReadingLayout.columns.displayName == "Columns")
    }

    @Test("Sections are gathered by moving nodes, never by rewriting them")
    func sectionGrouping() {
        let script = EPUBReadingStyle.sectionColumnsScript
        // A box per heading…
        #expect(script.contains("/^H[1-6]$/"))
        #expect(script.contains("class = 'origami-column'") || script.contains("className = 'origami-column'"))
        // …opened only when the box so far has something of its own, so a
        // bare part title joins the next section instead of taking a column.
        #expect(script.contains("hasBody"))
        // Nodes are appended, not re-created: ids, data-ids and anchors
        // survive, so an annotation anchored to a data-id is not orphaned.
        #expect(script.contains("appendChild(node)"))
        #expect(!script.contains("innerHTML"))
        // Injected twice over one page must not gather twice.
        #expect(script.contains("origamiSectioned === 'yes'"))
    }

    @Test("A book's own sections become the columns, not one box for the lot")
    func sectionsAreFound() {
        let script = EPUBReadingStyle.sectionColumnsScript
        // The fault this guards: an Origami EPUB puts its headings inside
        // <section> elements, so no child of body was ever a heading, no
        // second box was ever opened, and the whole chapter became one
        // column — the only one with a heading, and the only one that
        // scrolled.
        #expect(script.contains("tagName === 'SECTION'"))
        #expect(script.contains("sections.length > 1"))
        // Descending to where the flow really is, for a book that wraps it.
        #expect(script.contains("origami-passthrough"))
        // A marked section keeps its id and everything anchored to it; a
        // wrapper would be a second element to get wrong.
        #expect(script.contains("origamiClassed"))
        // Anything before the first section is a column of its own.
        #expect(script.contains("lead.appendChild(child)"))
    }

    @Test("Leaving Columns gives the book back")
    func groupingIsReversible() {
        let script = EPUBReadingStyle.sectionColumnsScript
        // A layout change restates the stylesheet without reloading, so a
        // grouping left standing would break every other reading.
        #expect(script.contains("__origamiUngroupSections"))
        // A box this script made gives its children back and goes…
        #expect(script.contains("insertBefore(element.firstChild, element)"))
        #expect(script.contains("removeChild(element)"))
        // …and a section of the book's own is only unclassed.
        #expect(script.contains("classList.remove('origami-column')"))
        #expect(script.contains("classList.remove('origami-passthrough')"))
        // Grouping is asked for by the app, but also happens at load when
        // the stylesheet already says Columns.
        #expect(script.contains("getComputedStyle(document.body).display === 'flex'"))
    }

    @Test("Every column keeps its own heading in view while it scrolls")
    func stickyHeadings() {
        let sheet = css(.init(layout: .columns))
        #expect(sheet.contains("position: sticky"))
        // Each column's own first heading, not merely the first in the book.
        #expect(sheet.contains(".origami-column > h2:first-child"))
        // On the paper, so the section's text does not read through it.
        let sticky = sheet.components(separatedBy: "position: sticky").last ?? ""
        #expect(sticky.contains("background:"))
        // And no other reading sticks anything.
        for layout in EPUBReadingLayout.allCases where layout != .columns {
            #expect(!css(.init(layout: layout)).contains("position: sticky"),
                    "\(layout.rawValue)")
        }
    }

    @Test("The pager can be told to measure again after the DOM changes")
    func remeasure() {
        #expect(EPUBReadingStyle.columnPagingScript.contains("__origamiRemeasure"))
    }

    @Test("Leaving a paged reading puts the body back")
    func clearingThePaging() {
        let script = EPUBReadingStyle.columnPagingScript
        // The transform is an inline style, so it outlives the stylesheet
        // that asked for it. Without this, paging to column five and then
        // choosing Scroll left the reading a thousand points to the left.
        #expect(script.contains("__origamiClearPaging"))
        #expect(script.contains("body.style.transform = ''"))
        #expect(script.contains("removeProperty('--origami-columns')"))
        // Unanimated, so it is a cut rather than a slide back across the
        // book the reader has just left.
        let clearing = script.components(separatedBy: "__origamiClearPaging").last ?? ""
        #expect(clearing.contains("transition = 'none'"))
    }

    @Test("The pager asks a section column how wide it is")
    func pagerMeasuresSectionColumns() {
        let script = EPUBReadingStyle.columnPagingScript
        // The width comes from a min() in the stylesheet, which only the
        // page can resolve — so it is measured, not derived.
        #expect(script.contains("origamiColumns === 'sections'"))
        #expect(script.contains("getElementsByClassName('origami-column')"))
        // Origami Text's rule, applied where the page can see both the
        // width and the number of sections.
        #expect(script.contains("Math.floor(width / 460)"))
        #expect(script.contains("setProperty('--origami-columns', shown)"))
        // The last index still leaves the view full.
        #expect(script.contains("boxes.length - shown"))
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
