import Foundation

/// The typography Reader lays over a book's own stylesheet, and the one
/// correction it makes to a book's colours.
///
/// This is pure text so it can be tested: what a reading looks like should
/// not be knowable only by looking at it. The web view injects the result at
/// document start and again at document end, so it has the last word over a
/// book that styles its own body.
public nonisolated enum EPUBReadingStyle {

    /// Who scrolls, when a book is set in pages side by side.
    ///
    /// On macOS `overflow-x` on `body` gives the body its own scroller and
    /// everything works. On iOS and visionOS it does not: WebKit hands the
    /// document scroll to the web view's own scroll view and **ignores
    /// `overflow` on `body`**, so no sideways scroller is ever made — the
    /// columns collapse and Horizontal reads exactly like Scrolling. There
    /// the overflow has to go on `html`, where it propagates to the
    /// viewport, and the page turn has to move the window rather than the
    /// body.
    public enum HorizontalScroller: String, Hashable, Sendable, CaseIterable {
        /// The body scrolls itself.
        case body
        /// The viewport scrolls, because the body cannot.
        case viewport

        /// What this platform's WebKit actually does.
        public static var platformDefault: HorizontalScroller {
            #if os(macOS)
            .body
            #else
            .viewport
            #endif
        }
    }

    /// Everything the reader has chosen about how a book is set.
    public struct Settings: Hashable, Sendable {
        public var theme: EPUBReadingTheme
        public var layout: EPUBReadingLayout
        /// A multiple of Reader's own reading size.
        public var scale: Double
        /// Lines of the body, as a multiple: 1.6 is the default measure.
        public var lineSpacing: Double
        public var bodyFont: EPUBReadingFont
        public var headingFont: EPUBReadingFont
        /// Whether the system appearance is dark; a theme may override it.
        public var dark: Bool
        /// Who scrolls sideways in Horizontal. Defaults to what the running
        /// platform's WebKit does; stated rather than assumed so both
        /// arrangements can be tested anywhere.
        public var horizontalScroller: HorizontalScroller

        public init(theme: EPUBReadingTheme = .system,
                    layout: EPUBReadingLayout = .scrolling,
                    scale: Double = 1,
                    lineSpacing: Double = 1.6,
                    bodyFont: EPUBReadingFont = .book,
                    headingFont: EPUBReadingFont = .book,
                    dark: Bool = false,
                    horizontalScroller: HorizontalScroller = .platformDefault) {
            self.theme = theme
            self.layout = layout
            self.scale = scale
            self.lineSpacing = lineSpacing
            self.bodyFont = bodyFont
            self.headingFont = headingFont
            self.dark = dark
            self.horizontalScroller = horizontalScroller
        }

        public var paperHex: String { theme.paperHex(dark: dark) }
        public var inkHex: String { theme.inkHex(dark: dark) }
        /// Whether the paper is dark enough to need the book's own ink
        /// lifted and its backgrounds cleared — a theme can be dark in a
        /// light appearance (Night read in daylight).
        public var readsDark: Bool { theme.paperIsDark(dark: dark) }
    }

    /// Reader's ink and paper, which are not a preference.
    ///
    /// Most books set neither colour, and a book that sets only one (dark
    /// grey text, assuming white paper) is unreadable on a dark page. So the
    /// reading states both — and on dark paper it also clears the book's own
    /// backgrounds, a white box behind a paragraph being the commonest way a
    /// book breaks a dark reading.
    public static func css(_ settings: Settings) -> String {
        let ink = settings.inkHex
        let paper = settings.paperHex
        let dark = settings.readsDark
        let quiet = dark ? "#a7a49f" : "#5b5f66"
        let rule = dark ? "#3a3c3f" : "#dcd9d4"
        let block = dark ? "#141517" : "#f1efec"
        let size = String(format: "%.1f", 17 * max(0.5, settings.scale))
        let leading = String(format: "%.2f", max(1.1, settings.lineSpacing))
        let clearBookBackgrounds = dark
            ? "body *, body *::before, body *::after { background-color: transparent !important; }"
            : ""
        let bodyFamily = settings.bodyFont.cssFamily.map { "font-family: \($0);" } ?? ""
        let headingFamily = settings.headingFont.cssFamily.map { "font-family: \($0);" } ?? ""

        // Where the reading is paged by transform, `html` is the window
        // onto it: it clips, and it gives the definite height the columns
        // measure themselves against.
        //
        // Both paged readings need this, and Columns needs it on every
        // platform — its columns are real boxes, so there was never a
        // body-overflow question for the scroller to answer. Leaving it to
        // Horizontal alone was a real fault: `body { height: 100% }`
        // resolved against an auto-height `html`, so the flex row had no
        // height to stretch to and the columns grew to their content
        // instead of the screen; and with nothing clipping, the document
        // itself scrolled sideways, so the transform slid the whole reading
        // off to the left.
        let viewport = paged(settings)
            ? """

            height: 100%;
                    overflow: hidden;
            """
            : ""

        return """
        :root { color-scheme: \(dark ? "dark" : "light"); }
        html {
            -webkit-text-size-adjust: 100%;
            background: \(paper);
            color: \(ink);\(viewport)
        }
        body {
            \(measure(settings))
            line-height: \(leading);
            font-size: \(size)px;
            \(bodyFamily)
            background: \(paper);
            color: \(ink);
            text-rendering: optimizeLegibility;
            -webkit-font-smoothing: antialiased;
        }
        \(clearBookBackgrounds)
        h1, h2, h3, h4, h5, h6 { color: \(ink); line-height: 1.25; \(headingFamily) }
        /* Links and citations read in the body's own ink. A scholarly
           page is dense with them — every reference, every glossary term,
           every cross-reference — and in blue the page turns into a
           thicket of blue, which is a map of the markup rather than a
           reading of the argument. They keep their underline, so a reader
           can still find them; only the colour goes. */
        a, a:visited { color: \(ink); }
        blockquote {
            margin: 1.2em 0;
            padding-left: 1em;
            border-left: 3px solid \(rule);
            color: \(quiet);
        }
        hr { border: none; border-top: 1px solid \(rule); }
        figcaption, small, .caption { color: \(quiet); }
        img, svg, video { max-width: 100%; height: auto; }
        /* A 3-D figure. `model` is not an HTML element and this WebKit reports
           it as an unknown one, which means `display: inline` and a width of
           zero — so the poster inside it was the only thing with any size, and
           the figure held together by accident. Making it a block, and giving
           the poster the figure's width, is what turns that accident into a
           picture. The same rules serve a book that wraps its model in an
           `object` or a plain link, which is what a conforming EPUB does. */
        model, object[type^="model/"] { display: block; }
        /* `max-width`, not `width`: the poster is a screenshot of Author's
           model window, so it is opaque and carries Author's own page colour
           — cream, at 960 square in the export this was written against. Bled
           to the measure it reads as a change of paper, and in a dark reading
           as a hole in the page. At its own size inside a frame it reads as
           what it is: a plate. */
        model > img, object[type^="model/"] > img {
            display: block;
            max-width: 100%;
            height: auto;
            margin: 0 auto;
        }
        figure.origami-model {
            margin: 1.5em 0;
            padding: 0.75em;
            border: 1px solid \(rule);
            border-radius: 8px;
        }
        /* It opens, so it has to look like it opens. */
        .origami-model { cursor: pointer; }
        figure.origami-model figcaption { color: \(quiet); }
        /* A model the book gave no poster is still something to press. */
        .origami-model-plate {
            display: block;
            padding: 2.5em 1em;
            text-align: center;
            font-size: 0.9em;
            color: \(quiet);
            background: \(block);
            border-radius: 6px;
        }
        table { max-width: 100%; border-collapse: collapse; }
        td, th { border: 1px solid \(rule); padding: 0.3em 0.5em; }
        pre, code { white-space: pre-wrap; word-wrap: break-word; }
        pre { background: \(block) !important; padding: 0.8em; border-radius: 6px; }
        \(spread(settings))
        \(sectionColumns(settings))
        """
    }

    /// Whether this reading is carried by a transform, so `html` must clip
    /// it and give it a height.
    static func paged(_ settings: Settings) -> Bool {
        settings.layout.isSectioned
            || (settings.layout == .horizontal
                && settings.horizontalScroller == .viewport)
    }

    /// The section columns' own rules: how wide a column is, and that it
    /// scrolls within itself rather than overflowing into its neighbour.
    private static func sectionColumns(_ settings: Settings) -> String {
        guard settings.layout == .columns else { return "" }
        return """
        .origami-column {
          flex: 0 0 calc(100% / var(--origami-columns, 1));
          height: 100%;
          overflow-y: auto;
          overflow-x: hidden;
          box-sizing: border-box;
          padding: 2.5em 2em 0.75em;
          border-right: 1px solid color-mix(in srgb, currentColor 12%, transparent);
          -webkit-overflow-scrolling: touch;
        }
        .origami-column > :first-child { margin-top: 0; }
        /* Each column keeps its own heading in view while its section is
           scrolled, so a reader who has scrolled down three screens still
           knows which section they are in. Without this only the first
           column was ever labelled, because only the first heading stayed
           on screen. */
        .origami-column > h1:first-child,
        .origami-column > h2:first-child,
        .origami-column > h3:first-child,
        .origami-column > h4:first-child,
        .origami-column > h5:first-child,
        .origami-column > h6:first-child {
          position: sticky;
          top: 0;
          z-index: 2;
          margin: 0 0 0.6em;
          padding: 0.15em 0 0.35em;
          /* `settings.paperHex`, not `paper` — in this function that name is
             the static `paper(_:)` above, and interpolating it put a
             function's description where a colour belonged. A sticky heading
             with no background has the text scroll up through it. */
          background: \(settings.paperHex);
        }
        /* The passthrough wrappers a book puts around its content take no
           part in the row; their children are the columns. */
        .origami-passthrough { display: contents; }
        /* Separators between sections are spacing for a page that scrolls
           down, and stray empty boxes in a row. */
        .origami-passthrough > br, body > br { display: none; }
        """
    }

    /// Two pages side by side, on a screen wide enough for them.
    ///
    /// Only where the viewport scrolls — on macOS the reader sizes the
    /// window and `column-width` should keep answering to it.
    private static func spread(_ settings: Settings) -> String {
        guard settings.layout == .horizontal,
              settings.horizontalScroller == .viewport else { return "" }
        return """
        @media (min-width: 700px) {
          body { column-count: 2; column-width: auto; }
        }
        """
    }

    /// How wide the words run, and — in Horizontal — how the page is cut
    /// into columns the window turns through sideways.
    private static func measure(_ settings: Settings) -> String {
        switch settings.layout {
        case .scrolling:
            // The width, with a small margin either side. Scroll used to be
            // a centred 34em column with Full Width standing beside it to
            // take the margins off — which made a setting into a way of
            // reading. With one vertical reading left, it is the one that
            // uses the screen: a reader who wants a narrower measure has a
            // window to narrow, and on a phone there was never room for the
            // empty space anyway.
            //
            // The foot is 2em clear at the bottom so the last line is not
            // under it, and the top has a little more than the sides so the
            // first line is not against the edge.
            //
            // `!important` because the measure is the reader's to set, not
            // the book's. The article we test against ships
            // `body { max-width: 38em; margin: 1em auto }` in its own
            // stylesheet, and a book only has to write `html body` — one
            // step more specific than our `body` — to win the cascade and
            // put its margins back. Reader offers the reader a measure;
            // that promise cannot be contingent on what a publisher wrote.
            return """
            max-width: none !important;
                    margin: 0 !important;
                    padding: 2.5em 2em 5em !important;
            """
        case .focus:
            // Nothing else on screen, so the column can be narrower and
            // the air around it wider — the reading and nothing but.
            //
            // A *share* of the view rather than a fixed measure, which is
            // Origami Text's answer: its reading column is 680 points in a
            // window and, in full screen, 67% of a built-in display (45%
            // of an external one). A fixed 30em was fine on a tablet and a
            // thin ribbon down the middle of a Mac, which is the same
            // fault by a different name — the number was right for one
            // screen and wrong for the rest.
            //
            // 67vw follows it, with a floor so a phone gets a reading
            // rather than a sliver: at 393pt that floor gives 22em of the
            // 23em available, and at 1440 the share gives 965 — Origami
            // Text's own full-screen width to the point.
            return """
            max-width: max(22em, 67vw) !important;
                    margin: 0 auto !important;
                    padding: 5em 1.5em 8em !important;
            """
        case .columns:
            // Not a flow. Each of the book's sections is its own box, laid
            // out in a row, and a section taller than the screen scrolls
            // inside its own box rather than spilling into the next one.
            // Origami Text's reading: what you see is the shape of the
            // argument, one section at a time, not a ribbon of prose cut
            // into screen-sized pieces.
            return """
            max-width: none !important;
                    margin: 0 !important;
                    padding: 0 !important;
                    height: 100%;
                    box-sizing: border-box;
                    display: flex;
                    flex-direction: row;
                    align-items: stretch;
                    transform: translateX(0px);
                    transition: transform 0.28s cubic-bezier(0.22, 0.61, 0.36, 1);
                    will-change: transform;
            """
        case .horizontal:
            // Pages side by side: the text is cut into columns as wide as a
            // comfortable measure, and the reading moves sideways through
            // them. A definite height is what makes a column a page.
            //
            // Which element scrolls is not a preference — see
            // `HorizontalScroller`. Where the viewport scrolls, the body
            // must not claim an overflow it will not be given, and its
            // height comes from `html` (set in `css`) rather than from
            // `100vh`, which the dynamic viewport moves about under it.
            switch settings.horizontalScroller {
            case .body:
                return """
                max-width: none !important;
                        margin: 0 !important;
                        padding: 2.5em 2em 0.75em !important;
                        height: 100vh;
                        box-sizing: border-box;
                        column-width: 30em;
                        column-gap: 4em;
                        column-fill: auto;
                        overflow-x: auto;
                        overflow-y: hidden;
                """
            case .viewport:
                // A tablet in Horizontal reads as a book: two pages side by
                // side, stated as a count rather than left to a measure.
                // `column-width` on a 744pt iPad mini gives one column and
                // on a 1133pt one gives two, so the spread changed when the
                // reader turned the device — which is not what a book does.
                // Below tablet width one column stands, because two on a
                // phone is two things too narrow to read.
                // Not a scroller. The columns are moved by a transform,
                // so the reading is always *at* a column and never between
                // two — which is Origami Text's iOS reading exactly: it
                // paginates, holds an index, and animates from one to the
                // next. A scroll view can always be left part way; an index
                // cannot.
                return """
                max-width: none !important;
                        margin: 0 !important;
                        padding: 2.5em 2em 0.75em !important;
                        height: 100%;
                        box-sizing: border-box;
                        column-width: 30em;
                        column-gap: 4em;
                        column-fill: auto;
                        transform: translateX(0px);
                        transition: transform 0.28s cubic-bezier(0.22, 0.61, 0.36, 1);
                        will-change: transform;
                """
            }
        }
    }

    /// The paper as components, for the view behind the page.
    public static func paper(_ settings: Settings) -> (red: Double, green: Double, blue: Double) {
        settings.theme.paperComponents(dark: settings.dark)
    }

    /// A book that hardcodes near-black ink would vanish on dark paper, so
    /// there any ink too close to the paper's own darkness is given the
    /// reading's. Origami Text makes the same correction for a book's
    /// unreadable greys.
    public static let darkInkScript = """
    (function() {
      var ink = getComputedStyle(document.body).color;
      function luminance(colour) {
        var parts = (colour || '').match(/\\d+(\\.\\d+)?/g);
        if (!parts || parts.length < 3) { return null; }
        return (0.2126 * parts[0] + 0.7152 * parts[1] + 0.0722 * parts[2]) / 255;
      }
      document.querySelectorAll('body *').forEach(function(element) {
        if (!element.childNodes.length) { return; }
        var value = luminance(getComputedStyle(element).color);
        if (value !== null && value < 0.35) { element.style.color = ink; }
      });
    })();
    """

    /// Colours a book's code, on the reader's side.
    ///
    /// The Origami profile's division of labour: the substrate keeps the
    /// source exactly as written — no styling spans, no inline colour — and
    /// the reading application paints it. So this runs over the rendered
    /// page and never rewrites the text: the DOM's `textContent` is
    /// untouched, so copying a block still yields the source character for
    /// character.
    ///
    /// The language is read from `class="language-…"` (the profile's
    /// convention) or `data-language="…"` (what Origami Text's exporter
    /// writes today); a block that names neither is left plain, because
    /// guessing a language colours the wrong words.
    public static func codeHighlightScript(dark: Bool) -> String {
        let comment = dark ? "#7f8c8d" : "#6a737d"
        let keyword = dark ? "#c792ea" : "#8250df"
        let string = dark ? "#c3e88d" : "#0a7d33"
        let number = dark ? "#f78c6c" : "#b5551d"
        return """
        (function() {
          var palette = { comment: '\(comment)', keyword: '\(keyword)',
                          string: '\(string)', number: '\(number)' };
          var words = {
            swift: 'func|let|var|if|else|guard|return|struct|class|enum|protocol|extension|import|for|in|while|switch|case|default|throws|try|async|await|public|private|static|self|nil|true|false',
            javascript: 'function|const|let|var|if|else|return|class|new|for|while|switch|case|default|try|catch|async|await|import|export|this|null|true|false|typeof',
            python: 'def|class|if|elif|else|return|import|from|for|while|try|except|with|as|lambda|yield|None|True|False|and|or|not|in|is',
            html: 'DOCTYPE|html|head|body|div|span|section|p|a|script|style|link|meta',
            css: 'color|background|margin|padding|font|display|position|width|height|border'
          };
          function languageOf(block) {
            var named = (block.className || '').match(/language-([\\w+#-]+)/);
            if (named) { return named[1].toLowerCase(); }
            var carried = block.getAttribute('data-language')
              || (block.parentElement && block.parentElement.getAttribute('data-language'));
            return carried ? carried.toLowerCase() : null;
          }
          function escapeHTML(text) {
            return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
          }
          document.querySelectorAll('pre code').forEach(function(block) {
            if (block.dataset.readerPainted === 'yes') { return; }
            var language = languageOf(block);
            if (!language) { return; }
            var vocabulary = words[language] || words[language.replace(/[0-9]+$/, '')];
            if (!vocabulary) { return; }
            // The source, kept exactly — what a copy must still yield.
            var source = block.textContent;
            var html = escapeHTML(source)
              .replace(/(\\/\\/[^\\n]*|#[^\\n]*)/g,
                       '<span style="color:' + palette.comment + '">$1</span>')
              .replace(/('[^'\\n]*'|&quot;[^&\\n]*&quot;|"[^"\\n]*")/g,
                       '<span style="color:' + palette.string + '">$1</span>')
              .replace(/\\b(\\d+(\\.\\d+)?)\\b/g,
                       '<span style="color:' + palette.number + '">$1</span>')
              .replace(new RegExp('\\\\b(' + vocabulary + ')\\\\b', 'g'),
                       '<span style="color:' + palette.keyword + '">$1</span>');
            block.innerHTML = html;
            block.dataset.readerPainted = 'yes';
            block.dataset.readerSource = source;
          });
        })();
        """
    }

    /// The LaTeX a book carries beside its MathML, when it carries any —
    /// the Origami profile's `data-latex` fallback, gathered so the reading
    /// can offer it for copying.
    public static let mathLaTeXScript = """
    (function() {
      var found = [];
      document.querySelectorAll('[data-latex]').forEach(function(element) {
        var latex = element.getAttribute('data-latex');
        if (latex) { found.push(latex); }
      });
      return found.join('\n\n');
    })();
    """

    /// Reports what the reader has selected, and **which addressable unit
    /// it sits in** — the id the document declared on the element, which is
    /// the whole point of the profile's high-resolution addressing.
    ///
    /// Origami documents put a stable `data-id` on every unit and an `id`
    /// on the element; either serves, and the nearest ancestor carrying one
    /// wins. A book with no ids still reports the words, so a note can
    /// quote even where it cannot anchor.
    public static let selectionBridgeScript = """
    (function() {
      function unitOf(node) {
        var element = node && (node.nodeType === 1 ? node : node.parentElement);
        while (element && element !== document.body) {
          var id = element.getAttribute('data-id') || element.getAttribute('id');
          if (id) { return id; }
          element = element.parentElement;
        }
        return null;
      }
      function report() {
        var selection = window.getSelection();
        var text = selection ? String(selection) : '';
        var payload = { kind: 'selection', text: text.trim(),
                        unit: null, before: null, after: null };
        if (payload.text && selection.rangeCount) {
          var range = selection.getRangeAt(0);
          payload.unit = unitOf(range.startContainer);
          // A little context either side, so a note re-anchors when ids change.
          var whole = (range.startContainer.textContent || '');
          var start = range.startOffset, end = range.endOffset;
          payload.before = whole.slice(Math.max(0, start - 32), start) || null;
          payload.after = whole.slice(end, end + 32) || null;
        }
        window.webkit.messageHandlers.reader.postMessage(payload);
      }
      document.addEventListener('selectionchange', report);
      document.addEventListener('mouseup', report);
      document.addEventListener('keyup', report);

      // A plain tap on the page, reported so a reading with its chrome
      // hidden can bring it back. This has to come from inside the page:
      // the web view consumes touches, so a tap gesture on the view around
      // it never fires — which is why a hover reveal alone left a
      // touch-only reader with no way back out of a bare reading.
      //
      // A tap that is really something else is not one: following a link,
      // or finishing a selection, is the reader doing that instead.
      document.addEventListener('click', function(event) {
        var target = event.target;
        if (target && target.closest && target.closest('a')) { return; }
        var selection = window.getSelection();
        if (selection && String(selection).trim()) { return; }
        window.webkit.messageHandlers.reader.postMessage({ kind: 'tap' });
      });
    })();
    """

    /// Turning a page in Horizontal: the window scrolls by its own width,
    /// which is exactly one screenful of columns.
    /// Reports a tap on a citation, with the reference the book itself
    /// prints for it.
    ///
    /// Every shape a package may carry is recognised, because they disagree:
    /// Origami Text's exports mark a citation with `class="citation"` and a
    /// `data-citation-id`; Author writes `data-citation-key`; the EPUB and
    /// ARIA vocabularies use `epub:type="biblioref"` and
    /// `role="doc-biblioref"`; and an ordinary book often has nothing but an
    /// `<a href="#bib-12">`. A reader tapping `[12]` means the same thing in
    /// all of them.
    ///
    /// The reference text is read **here**, in the page, rather than asked
    /// for afterwards: the anchor's href names an element in this document,
    /// and following it is a DOM lookup the app would otherwise have to ask
    /// for over the bridge and wait for. So the card can show the book's own
    /// words at once, and only the *live* part — what the world knows about
    /// the work now — has to be waited for.
    ///
    /// The default action is suppressed, because a citation that jumps the
    /// reading to the backmatter has lost the reader their place; the card
    /// brings the reference to them instead.
    public static let citationBridgeScript = """
    (function() {
      function isCitation(a) {
        if (!a || a.tagName !== 'A') { return false; }
        if (a.classList && a.classList.contains('citation')) { return true; }
        if (a.getAttribute('data-citation-id')) { return true; }
        if (a.getAttribute('data-citation-key')) { return true; }
        var role = a.getAttribute('role') || '';
        if (role.indexOf('doc-biblioref') >= 0) { return true; }
        if (role.indexOf('doc-noteref') >= 0) { return true; }
        var kind = a.getAttribute('epub:type')
          || a.getAttributeNS('http://www.idpf.org/2007/ops', 'type') || '';
        if (kind.indexOf('biblioref') >= 0) { return true; }
        if (kind.indexOf('noteref') >= 0) { return true; }
        return false;
      }

      // What the book prints for this citation: the element its href names.
      // A list item, a paragraph, a table row — whatever the backmatter is
      // made of, its text is the reference.
      function referenceText(a) {
        var href = a.getAttribute('href') || '';
        var hash = href.indexOf('#');
        if (hash < 0) { return ''; }
        var id = decodeURIComponent(href.slice(hash + 1));
        if (!id) { return ''; }
        var target = document.getElementById(id);
        if (!target) { return ''; }
        // An anchor sitting inside its entry names the entry, not itself.
        if (target.tagName === 'A' || !(target.textContent || '').trim()) {
          target = target.parentElement || target;
        }
        return (target.textContent || '').replace(/\\s+/g, ' ').trim();
      }

      document.addEventListener('click', function(event) {
        var anchor = event.target.closest ? event.target.closest('a') : null;
        if (!isCitation(anchor)) { return; }
        // The reading keeps its place; the reference comes to the reader.
        event.preventDefault();
        event.stopImmediatePropagation();
        var href = anchor.getAttribute('href') || '';
        var text = referenceText(anchor);
        var doi = (text.match(/10\\.\\d{4,9}\\/[^\\s"'<>&]+/) || [''])[0]
          .replace(/[.,;:)\\]}>]+$/, '');
        window.webkit.messageHandlers.reader.postMessage({
          kind: 'citation',
          key: anchor.getAttribute('data-citation-id')
            || anchor.getAttribute('data-citation-key')
            || href.replace(/^.*#/, ''),
          label: (anchor.textContent || '').trim(),
          href: href,
          text: text,
          doi: doi
        });
      }, true);
    })();
    """

    /// Finds the book's 3-D figures and hands them to the app when tapped.
    ///
    /// The page cannot show them itself. `model` is a WebKit proposal, not an
    /// HTML element, and it is not implemented here: the element parses as an
    /// unknown one, so its `source` child is inert and the USDZ beside it is
    /// never fetched. What a reader sees is the poster, and only because the
    /// fallback `img` happens to be a child of an inline box.
    ///
    /// So the page's job is to *find* the model and say where it is; the app
    /// opens it natively. Three spellings are recognised, because a book may
    /// use any of them and only the middle one validates: Apple's `model`,
    /// the conforming `object`, and a plain link to the file — which is what
    /// a book that wants to work everywhere writes.
    ///
    /// The href is resolved against the chapter, so the app is handed a real
    /// file inside the unpacked book rather than a relative path it would
    /// have to join itself.
    ///
    /// The poster is the figure's resting state and stays that way. In plain
    /// HTML the child `img` is fallback content, shown only when `model` is
    /// unsupported — but in an Author export it is not a thumbnail. The
    /// writer opened the model, turned it to the side worth showing and took
    /// that still, so it is editorial. Rendering the model in the column, in
    /// its own default orientation, would throw that choice away silently.
    /// Nothing here animates, either: a moving object in running prose is a
    /// distraction until it is asked for.
    public static let modelBridgeScript = """
    (function() {
      if (window.__origamiModels) { return; }
      window.__origamiModels = true;

      // What counts as a model at all, and the narrower set this reader can
      // actually render. A book may offer glTF beside USD; the poster and the
      // file are still worth offering when neither can be drawn here.
      var ANY_3D = /\\.(usdz|usda|usdc|usd|reality|glb|gltf)(\\?|#|$)/i;
      var RENDERABLE = /\\.(usdz|usda|usdc|usd|reality)(\\?|#|$)/i;
      var RENDERABLE_TYPE = /(usd|vnd\\.usdz|x-reality|reality)/i;

      // A book's chapter is XHTML, and in XML `tagName` is what the author
      // typed rather than the upper case an HTML document reports. Comparing
      // against 'MODEL' therefore matched nothing at all — in a book, which
      // is the only place this runs.
      function tag(el) {
        return (el && el.tagName ? el.tagName : '').toLowerCase();
      }

      /// The source to open, and whether it is one we can draw.
      ///
      /// A `model` may carry several `source` children — usdz beside glb —
      /// and the rule is to take the first one *we support*, not simply the
      /// first one written. Taking the first would hand the app a glTF it
      /// cannot render while a perfectly good USD sat underneath it.
      function chooseSource(el) {
        if (!el) { return null; }
        if (tag(el) === 'model') {
          var sources = el.querySelectorAll('source[src]');
          var fallback = null;
          for (var i = 0; i < sources.length; i++) {
            var src = sources[i].getAttribute('src') || '';
            var type = sources[i].getAttribute('type') || '';
            if (!src) { continue; }
            if (RENDERABLE.test(src) || RENDERABLE_TYPE.test(type)) {
              return { src: src, renderable: true };
            }
            if (!fallback && ANY_3D.test(src)) { fallback = src; }
          }
          var own = el.getAttribute('src') || '';
          if (!fallback && ANY_3D.test(own)) { fallback = own; }
          return fallback ? { src: fallback, renderable: false } : null;
        }
        var direct = tag(el) === 'object'
          ? (el.getAttribute('data') || '') : (el.getAttribute('href') || '');
        if (!ANY_3D.test(direct)) { return null; }
        return { src: direct, renderable: RENDERABLE.test(direct) };
      }

      function posterOf(el) {
        var img = el.querySelector ? el.querySelector('img[src]') : null;
        return img ? img.getAttribute('src') : '';
      }

      /// The writer's own description, and nothing standing in for it.
      ///
      /// An empty `alt` means the figure is undescribed, and the filename is
      /// not a description: announcing "Spiral_Notebook__3D.usdz" would
      /// assert an accessibility the document does not have. Author withdraws
      /// the package's `alternativeText` claim in that case precisely so it
      /// can be trusted, and this must not undo that. The caption counts,
      /// because a caption is prose the writer wrote.
      function describedBy(el) {
        var figure = el.closest ? el.closest('figure') : null;
        var caption = figure ? figure.querySelector('figcaption') : null;
        if (caption && (caption.textContent || '').trim()) {
          return (caption.textContent || '').replace(/\\s+/g, ' ').trim();
        }
        var img = el.querySelector ? el.querySelector('img[alt]') : null;
        return img ? (img.getAttribute('alt') || '').trim() : '';
      }

      /// A model with no poster still has to occupy something a finger can
      /// find. The filename is fair as a *name* here — it is labelling a
      /// control, not claiming to describe the object.
      function plate(el) {
        if (tag(el) !== 'model') { return; }
        if (el.querySelector('img')) { return; }
        if (el.querySelector('.origami-model-plate')) { return; }
        var box = document.createElement('div');
        box.className = 'origami-model-plate';
        box.setAttribute('role', 'img');
        var name = el.getAttribute('data-filename') || '';
        box.textContent = name || 'A 3-D model';
        el.appendChild(box);
      }

      function hosts() {
        var found = [];
        var declared = document.querySelectorAll('model, object[type^="model/"]');
        for (var i = 0; i < declared.length; i++) { found.push(declared[i]); }
        var links = document.querySelectorAll('a[href]');
        for (var j = 0; j < links.length; j++) {
          if (ANY_3D.test(links[j].getAttribute('href') || '')) { found.push(links[j]); }
        }
        return found;
      }

      window.__origamiMarkModels = function() {
        var marked = 0;
        hosts().forEach(function(el) {
          if (!chooseSource(el)) { return; }
          el.classList.add('origami-model');
          plate(el);
          var figure = el.closest ? el.closest('figure') : null;
          if (figure) { figure.classList.add('origami-model'); }
          marked += 1;
        });
        return marked;
      };

      document.addEventListener('click', function(event) {
        var marked = event.target.closest ? event.target.closest('.origami-model') : null;
        if (!marked) { return; }
        var host = tag(marked) === 'figure'
          ? marked.querySelector('model, object, a[href]') : marked;
        var chosen = chooseSource(host);
        if (!chosen) { return; }
        // The reading keeps its place; the model opens over it.
        event.preventDefault();
        event.stopImmediatePropagation();
        var poster = posterOf(host);
        function attr(name) { return host.getAttribute(name) || ''; }
        window.webkit.messageHandlers.reader.postMessage({
          kind: 'model',
          href: new URL(chosen.src, document.baseURI).href,
          renderable: chosen.renderable,
          poster: poster ? new URL(poster, document.baseURI).href : '',
          // The writer's description, or empty — never the filename.
          description: describedBy(host),
          filename: attr('data-filename'),
          mediaType: attr('data-media-type'),
          bytes: attr('data-model-bytes'),
          // Absent means genuinely unknown, and Author omits rather than
          // guesses: a reader told "metres" about a centimetre model builds
          // something a hundred times too big. Passed through as written so
          // the app can tell "unknown" from "one metre".
          units: attr('data-model-units'),
          extent: attr('data-model-extent'),
          up: attr('data-model-up'),
          reduced: attr('data-model-reduced'),
          sourceBytes: attr('data-model-source-bytes'),
          original: attr('data-model-source')
        });
      }, true);

      window.__origamiMarkModels();
    })();
    """

    /// The colours the reader's marks and the search are painted in.
    ///
    /// A separate stylesheet from the reading's own, injected under its own
    /// id: the reading's sheet is rewritten whenever a theme or a size
    /// changes, and these rules do not depend on any of that. `::highlight()`
    /// takes no colour from a `Highlight` object — the group is named in
    /// JavaScript and coloured in CSS — so the two have to agree on the
    /// names, which is what `groups` is for.
    ///
    /// The app owns the palette because the app owns the categories: the
    /// format has no opinion about what "Disagree" looks like.
    public static func markStyleScript(groups: [(name: String, background: String)]) -> String {
        let rules = groups
            .map { "::highlight(\($0.name)) { background-color: \($0.background); }" }
            .joined(separator: "\n")
        return styleScript(css: """
        \(rules)
        /* The search's own two: every hit quietly, and the one the reader is
           standing on plainly. Deliberately not a mark's colour — a search
           makes a different kind of claim about a word than a highlight. */
        ::highlight(origami-find) { background-color: rgba(255, 214, 10, 0.45); }
        ::highlight(origami-find-at) { background-color: rgba(255, 149, 0, 0.85); }
        """, id: "reader-marks")
    }

    /// Finds text in the open chapter, and marks every hit.
    ///
    /// Painted with the CSS Custom Highlight API rather than by wrapping
    /// matches in elements. Wrapping would work, and every web reader used to
    /// do it, but it *changes the document*: inserting a `mark` splits text
    /// nodes and adds boxes, which moves the line breaks. This reading counts
    /// its lines and breaks its columns on those exact boxes, so a search
    /// would re-break the page it is trying to help the reader look at — and
    /// clearing the search would break it back. A highlight range paints over
    /// the layout and leaves it alone.
    ///
    /// Matches are sought within a text node rather than across the whole
    /// chapter's text. A phrase interrupted by a `strong` or a footnote mark
    /// is therefore missed; in running prose that is rare, and the cost of
    /// the alternative is walking a flattened copy of the chapter and mapping
    /// offsets back into nodes on every keystroke.
    public static let findScript = """
    (function() {
      if (window.__origamiFind) { return; }

      var hits = [];
      var at = -1;

      function report() {
        window.webkit.messageHandlers.reader.postMessage({
          kind: 'find', matches: hits.length, index: hits.length ? at + 1 : 0
        });
      }

      function paint() {
        if (!window.CSS || !CSS.highlights) { return; }
        CSS.highlights.delete('origami-find');
        CSS.highlights.delete('origami-find-at');
        if (!hits.length) { return; }
        var rest = [];
        for (var i = 0; i < hits.length; i++) { if (i !== at) { rest.push(hits[i]); } }
        if (rest.length) {
          CSS.highlights.set('origami-find', new Highlight(...rest));
        }
        if (at >= 0) { CSS.highlights.set('origami-find-at', new Highlight(hits[at])); }
      }

      function show() {
        if (at < 0 || !hits[at]) { return; }
        var rect = hits[at].getBoundingClientRect();
        if (!rect || (!rect.top && !rect.left)) { return; }
        // Brought into view by its own element, because in a paged reading
        // there is nothing to scroll — the column has to be turned to, and
        // `scrollIntoView` on a transformed row does nothing useful.
        var node = hits[at].startContainer;
        var element = node.nodeType === 1 ? node : node.parentElement;
        if (!element) { return; }
        if (window.__origamiRevealElement) {
          window.__origamiRevealElement(element);
        } else {
          element.scrollIntoView({ block: 'center', inline: 'nearest' });
        }
      }

      window.__origamiFind = function(query) {
        hits = [];
        at = -1;
        var wanted = String(query || '').trim().toLowerCase();
        if (wanted.length < 2) { paint(); report(); return; }
        var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
          acceptNode: function(node) {
            if (!node.nodeValue || !node.nodeValue.trim()) {
              return NodeFilter.FILTER_REJECT;
            }
            var parent = node.parentElement;
            // A script or a style is not the book, and neither is the
            // Visual-Meta block the page carries for machines.
            if (!parent || parent.closest('script, style, #visual-meta')) {
              return NodeFilter.FILTER_REJECT;
            }
            return NodeFilter.FILTER_ACCEPT;
          }
        });
        var node;
        while ((node = walker.nextNode())) {
          var haystack = node.nodeValue.toLowerCase();
          var from = haystack.indexOf(wanted);
          while (from >= 0) {
            var range = document.createRange();
            range.setStart(node, from);
            range.setEnd(node, from + wanted.length);
            hits.push(range);
            from = haystack.indexOf(wanted, from + wanted.length);
          }
        }
        if (hits.length) { at = 0; }
        paint();
        show();
        report();
      };

      window.__origamiFindStep = function(delta) {
        if (!hits.length) { report(); return; }
        // Wraps, because a reader at the last hit means the first one.
        at = (at + (delta < 0 ? -1 : 1) + hits.length) % hits.length;
        paint();
        show();
        report();
      };

      window.__origamiFindClear = function() {
        hits = [];
        at = -1;
        paint();
        report();
      };
    })();
    """

    /// Remembers where the reader had got to, and puts them back.
    ///
    /// Reported as a fraction of the chapter rather than a pixel offset: the
    /// reader may come back at a different text size, on a different screen,
    /// or in a different one of the readings, and a pixel offset means none
    /// of those. A fraction means "about a third of the way in", which is
    /// what a person remembers anyway.
    ///
    /// Throttled by a frame's grace, because a scroll reports continuously
    /// and this ends in a write to disk.
    public static let positionScript = """
    (function() {
      if (window.__origamiPosition) { return; }
      window.__origamiPosition = true;

      var pending = null;

      function scroller() {
        // Whichever thing actually scrolls in this reading.
        var body = document.body;
        if (body.scrollHeight > body.clientHeight + 4) { return body; }
        var root = document.documentElement;
        if (root.scrollHeight > root.clientHeight + 4) { return root; }
        return null;
      }

      function fraction() {
        var box = scroller();
        if (!box) { return 0; }
        var travel = box.scrollHeight - box.clientHeight;
        if (travel <= 0) { return 0; }
        return Math.min(Math.max(box.scrollTop / travel, 0), 1);
      }

      function tell() {
        window.webkit.messageHandlers.reader.postMessage({
          kind: 'position', fraction: fraction()
        });
      }

      window.addEventListener('scroll', function() {
        if (pending) { return; }
        pending = setTimeout(function() { pending = null; tell(); }, 400);
      }, true);

      window.__origamiGoToFraction = function(wanted) {
        var box = scroller();
        if (!box) { return; }
        var travel = box.scrollHeight - box.clientHeight;
        if (travel <= 0) { return; }
        box.scrollTop = travel * Math.min(Math.max(Number(wanted) || 0, 0), 1);
      };
    })();
    """

    /// Paints the reader's own highlights back onto the page.
    ///
    /// The marks are not in the book — they are W3C annotations in a sidecar,
    /// so the book is never written to — which means every open has to find
    /// the quoted words again. The quote is looked for inside the element the
    /// annotation named; failing that, anywhere in the chapter. A quote whose
    /// words have gone is simply not painted, and says so, rather than being
    /// drawn somewhere plausible and wrong.
    ///
    /// Same painting as the search, and for the same reason: a highlight that
    /// re-broke the lines would move the sentence it is marking.
    public static let highlightScript = """
    (function() {
      if (window.__origamiPaintMarks) { return; }

      function textNodes(root) {
        var found = [];
        var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
          acceptNode: function(node) {
            if (!node.nodeValue) { return NodeFilter.FILTER_REJECT; }
            var parent = node.parentElement;
            if (!parent || parent.closest('script, style, #visual-meta')) {
              return NodeFilter.FILTER_REJECT;
            }
            return NodeFilter.FILTER_ACCEPT;
          }
        });
        var node;
        while ((node = walker.nextNode())) { found.push(node); }
        return found;
      }

      /// The range holding `exact` within `root`, preferring the occurrence
      /// that follows `prefix` — which is what makes a second "the same
      /// sentence" land on the right one.
      function locate(root, exact, prefix) {
        if (!root || !exact) { return null; }
        var wanted = exact.replace(/\\s+/g, ' ').trim();
        if (!wanted) { return null; }
        var nodes = textNodes(root);
        var best = null;
        for (var i = 0; i < nodes.length; i++) {
          var haystack = nodes[i].nodeValue.replace(/\\s+/g, ' ');
          var from = haystack.indexOf(wanted);
          while (from >= 0) {
            var range = document.createRange();
            range.setStart(nodes[i], from);
            range.setEnd(nodes[i], from + wanted.length);
            if (!best) { best = range; }
            if (prefix) {
              var runUp = haystack.slice(Math.max(0, from - prefix.length), from);
              if (runUp.indexOf(prefix.replace(/\\s+/g, ' ').slice(-12)) >= 0) {
                return range;
              }
            } else {
              return range;
            }
            from = haystack.indexOf(wanted, from + wanted.length);
          }
        }
        return best;
      }

      /// `marks` is [{ id, exact, prefix, element, group }]. Grouped by
      /// `group` so one highlight layer serves each colour.
      window.__origamiPaintMarks = function(marks) {
        if (!window.CSS || !CSS.highlights) { return 0; }
        var known = window.__origamiMarkGroups || [];
        for (var g = 0; g < known.length; g++) { CSS.highlights.delete(known[g]); }

        var byGroup = {};
        var missing = [];
        (marks || []).forEach(function(mark) {
          var root = null;
          if (mark.element) { root = document.getElementById(mark.element); }
          var range = locate(root || document.body, mark.exact, mark.prefix)
            || (root ? locate(document.body, mark.exact, mark.prefix) : null);
          if (!range) { missing.push(mark.id); return; }
          var group = mark.group || 'origami-mark';
          (byGroup[group] = byGroup[group] || []).push(range);
        });

        var groups = Object.keys(byGroup);
        groups.forEach(function(group) {
          CSS.highlights.set(group, new Highlight(...byGroup[group]));
        });
        window.__origamiMarkGroups = groups;

        window.webkit.messageHandlers.reader.postMessage({
          kind: 'marks', painted: (marks || []).length - missing.length, missing: missing
        });
        return groups.length;
      };
    })();
    """

    /// Hands a tapped picture to the app, so it can be lifted out of the
    /// column and looked at properly.
    ///
    /// A figure in a book is printed at the measure's width, which on a phone
    /// or in a column is often smaller than the plate it was drawn at. The
    /// reading cannot help that — the text has to keep its measure — so the
    /// picture leaves the page instead.
    ///
    /// Three kinds of image are deliberately left alone. A 3-D figure's
    /// poster, because tapping that opens the model and the model is the
    /// point. An image inside a link, because the link is what the author
    /// meant to be tappable. And anything small, because a page is full of
    /// bullets, rules, logos and inline glyphs that are images in markup and
    /// furniture in fact — lifting a 16-point icon into a window of its own
    /// would be a joke at the reader's expense.
    public static let imageBridgeScript = """
    (function() {
      if (window.__origamiImages) { return; }
      window.__origamiImages = true;

      // Below this, in points on screen, an image is furniture.
      var SMALLEST = 48;

      function liftable(img) {
        if (!img || !img.getAttribute('src')) { return false; }
        if (img.closest && img.closest('.origami-model')) { return false; }
        if (img.closest && img.closest('a[href]')) { return false; }
        var box = img.getBoundingClientRect();
        return Math.min(box.width, box.height) >= SMALLEST;
      }

      // What the book calls it: the figure's caption if there is one, else
      // the alternative text. Both may be missing, and then the window falls
      // back to the filename.
      function labelOf(img) {
        var figure = img.closest ? img.closest('figure') : null;
        var caption = figure ? figure.querySelector('figcaption') : null;
        if (caption && (caption.textContent || '').trim()) {
          return (caption.textContent || '').replace(/\\s+/g, ' ').trim();
        }
        return (img.getAttribute('alt') || '').trim();
      }

      document.addEventListener('click', function(event) {
        var img = event.target && event.target.tagName
          && event.target.tagName.toLowerCase() === 'img' ? event.target : null;
        if (!liftable(img)) { return; }
        // The reading keeps its place; the picture comes out over it.
        event.preventDefault();
        event.stopImmediatePropagation();
        window.webkit.messageHandlers.reader.postMessage({
          kind: 'image',
          href: new URL(img.getAttribute('src'), document.baseURI).href,
          label: labelOf(img)
        });
      }, true);
    })();
    """

    /// Gathers the book's content into one box per section, so each can be
    /// a column of its own.
    ///
    /// A book's markup is rarely already divided this way: some are a flat
    /// run of `h2`, `p`, `p`, `h2`, … and only an Origami EPUB reliably
    /// wraps its sections. So the boxes are made here, at each heading.
    ///
    /// **Nothing is rewritten** — the nodes are moved into wrappers, not
    /// re-created, so text, ids, `data-id`s, anchors and event handlers all
    /// survive and a copy still yields the book's own words. That matters
    /// for more than tidiness: an annotation anchors to a `data-id`, and an
    /// id that changed under a reading would orphan every note on it.
    ///
    /// A heading with nothing of its own — a part title followed straight
    /// away by a subheading — joins the next box rather than taking a
    /// column to say one line. Origami Text does the same, and for the same
    /// reason: a column should be worth turning to.
    public static let sectionColumnsScript = """
    (function() {
      if (window.__origamiSections) { return; }
      window.__origamiSections = true;

      var heading = /^H[1-6]$/;

      // The element actually holding the flow. A book commonly wraps its
      // content one or two levels down, and grouping `body`'s own children
      // would then make a single box of the whole chapter — which is
      // exactly what went wrong: an Origami EPUB puts its headings inside
      // <section> elements, so no child of body was ever a heading and no
      // second column was ever opened.
      function flow() {
        var node = document.body;
        for (var depth = 0; depth < 6; depth++) {
          if (node.children.length !== 1) { break; }
          var only = node.children[0];
          if (!only.querySelector) { break; }
          if (!only.querySelector('h1,h2,h3,h4,h5,h6,p,section')) { break; }
          only.classList.add('origami-passthrough');
          node = only;
        }
        return node;
      }

      function box() {
        var made = document.createElement('div');
        made.className = 'origami-column';
        made.dataset.origamiWrapped = 'yes';
        return made;
      }

      window.__origamiGroupSections = function() {
        var root = flow();
        if (root.dataset.origamiSectioned === 'yes') { return; }

        var children = Array.prototype.slice.call(root.children);
        var sections = children.filter(function(el) { return el.tagName === 'SECTION'; });
        var boxes = [];

        if (sections.length > 1) {
          // The book already says where its sections are. Marking them
          // keeps their ids, their data-ids and everything anchored to
          // them — a wrapper would be a second element to get wrong.
          var lead = null;
          for (var i = 0; i < children.length; i++) {
            var child = children[i];
            if (child.tagName === 'SECTION') {
              child.classList.add('origami-column');
              child.dataset.origamiClassed = 'yes';
              boxes.push(child);
              lead = null;
            } else if (child.tagName === 'BR') {
              continue;   // a separator between sections; the CSS hides it
            } else {
              // Anything before the first section — a title, a byline, an
              // abstract table — is a column of its own.
              if (lead === null) { lead = box(); boxes.push(lead); }
              lead.appendChild(child);
            }
          }
        } else {
          // A flat book: h2, p, p, h2, … Group at each heading, and let a
          // heading with nothing of its own join the next box rather than
          // take a column to say one line.
          var nodes = Array.prototype.slice.call(root.childNodes);
          var current = null;
          var hasBody = false;
          for (var j = 0; j < nodes.length; j++) {
            var node = nodes[j];
            if (node.nodeType === 3 && !node.textContent.trim()) { continue; }
            if (node.nodeType === 1 && node.tagName === 'BR') { continue; }
            var isHeading = node.nodeType === 1 && heading.test(node.tagName);
            if (isHeading && (current === null || hasBody)) {
              current = box(); boxes.push(current); hasBody = false;
            }
            if (current === null) { current = box(); boxes.push(current); hasBody = false; }
            current.appendChild(node);
            if (!isHeading) { hasBody = true; }
          }
        }

        // In document order, so the reading still reads forwards.
        for (var k = 0; k < boxes.length; k++) { root.appendChild(boxes[k]); }
        root.dataset.origamiSectioned = 'yes';
        document.body.dataset.origamiColumns = 'sections';
      };

      // Leaving Columns has to give the book back. Switching layout only
      // restates the stylesheet — it does not reload the page — so a
      // grouping left standing would break every other reading.
      window.__origamiUngroupSections = function() {
        var root = flow();
        var boxes = Array.prototype.slice.call(
          document.getElementsByClassName('origami-column'));
        for (var i = 0; i < boxes.length; i++) {
          var element = boxes[i];
          if (element.dataset.origamiWrapped === 'yes') {
            // A box this script made: give its children back and go.
            while (element.firstChild) {
              element.parentNode.insertBefore(element.firstChild, element);
            }
            element.parentNode.removeChild(element);
          } else {
            // A section of the book's own: it was only ever classed.
            element.classList.remove('origami-column');
            delete element.dataset.origamiClassed;
          }
        }
        var through = Array.prototype.slice.call(
          document.getElementsByClassName('origami-passthrough'));
        for (var j = 0; j < through.length; j++) {
          through[j].classList.remove('origami-passthrough');
        }
        delete root.dataset.origamiSectioned;
        delete document.body.dataset.origamiColumns;
      };

      // The stylesheet decides: Columns is the reading that lays the body
      // out as a row, so the page can tell without being told.
      if (getComputedStyle(document.body).display === 'flex') {
        window.__origamiGroupSections();
      }
    })();
    """

    /// Trims each column to a whole number of lines.
    ///
    /// A column with a definite height shows only the lines that fit, and
    /// what is left below the last one is wasted — up to a full line of it,
    /// on top of whatever padding the stylesheet asked for. Together that
    /// was enough to look like room for another line, because it was.
    ///
    /// So the leftover is measured and given back: the bottom padding
    /// starts small, the page works out how many whole lines the space
    /// holds, and then sets the padding to exactly the remainder. The text
    /// block becomes a whole number of lines — the most the column can
    /// hold — and the space under the last line is deliberate rather than
    /// accidental.
    ///
    /// Reads `line-height` rather than assuming it: the reader sets the
    /// leading, and a book may set its own.
    public static let fitLinesScript = """
    (function() {
      if (window.__origamiFitting) { return; }
      window.__origamiFitting = true;

      function fit(element) {
        var style = getComputedStyle(element);
        // A column only has lines to fit if its height is definite.
        if (style.overflowY === 'visible' && style.height === 'auto') { return; }
        var line = parseFloat(style.lineHeight);
        if (!isFinite(line) || line <= 0) { return; }
        var top = parseFloat(style.paddingTop) || 0;
        // Start from the stylesheet's own small value, not from whatever
        // this function set last time, or each pass would shrink the text.
        element.style.paddingBottom = '';
        var floor = parseFloat(getComputedStyle(element).paddingBottom) || 0;
        var box = element.clientHeight;
        var available = box - top - floor;
        if (available < line) { return; }
        var lines = Math.floor(available / line);
        var wanted = box - top - lines * line;
        if (wanted > floor + 0.5) {
          element.style.paddingBottom = wanted + 'px';
        }
      }

      window.__origamiFitLines = function() {
        var boxes = document.getElementsByClassName('origami-column');
        if (boxes.length) {
          for (var i = 0; i < boxes.length; i++) { fit(boxes[i]); }
          return;
        }
        // Horizontal: the columns are the body's own, so the body is what
        // has to hold whole lines.
        if (getComputedStyle(document.body).columnCount !== 'auto') {
          fit(document.body);
        }
      };

      window.addEventListener('resize', function() { window.__origamiFitLines(); });
      window.__origamiFitLines();
    })();
    """

    /// Paging by column, done in the page: a swipe steps an index and the
    /// stylesheet's transition carries the columns across.
    ///
    /// This is Origami Text's iOS reading, in the one form a rendered book
    /// allows. There, Horizontal is not a scroll view — the document is
    /// paginated, an index is held, and moving between pages is
    /// `withAnimation(.easeInOut)`. The reading is therefore always *at* a
    /// page. A scroll view cannot promise that: snapping only corrects the
    /// resting place after the fact, so a slow drag still shows two half
    /// columns on the way, and an interrupted one can stop anywhere.
    ///
    /// So the columns are moved by a transform and there is no scroller to
    /// be part way through. The index is clamped, kept across a rotation
    /// (the column it was on stays the column it is on), and reported so
    /// the app can say where the reader is. `__origamiTurn` is left on the
    /// window so the foot's arrows and the arrow keys move the same way a
    /// finger does.
    public static let columnPagingScript = """
    (function() {
      if (window.__origamiPaging) { return; }
      window.__origamiPaging = true;

      var index = 0;
      var pitch = 0;
      var last = 0;
      var shown = 1;

      function measure() {
        var body = document.body;
        var style = getComputedStyle(body);
        if (body.dataset.origamiColumns === 'sections') {
          var boxes = body.getElementsByClassName('origami-column');
          if (!boxes.length) { pitch = body.clientWidth; shown = 1; last = 0; return; }
          // Origami Text's rule, which it arrived at by reading on these
          // screens: two columns at least, one more for every 460 points,
          // and never more columns than the book has sections — three
          // columns for a two-section chapter would be a third of the view
          // showing nothing.
          var width = body.clientWidth;
          shown = Math.min(Math.max(Math.floor(width / 460), 2), boxes.length);
          // One departure from Origami Text's rule, because Origami Text
          // wrote it for a Mac window and an iPad: its floor of two would
          // put two 196-point columns on a phone, which is two things too
          // narrow to read. A column has to stay wide enough to hold a
          // line, and below that one column is the honest answer.
          if (shown > 1 && width / shown < 320) {
            shown = Math.max(1, Math.floor(width / 320));
          }
          // The count goes to the stylesheet, which owns the arithmetic:
          // the page knows the number, CSS knows what to do with it.
          body.style.setProperty('--origami-columns', shown);
          pitch = width / shown;
          last = Math.max(0, boxes.length - shown);
          return;
        }
        var count = parseInt(style.columnCount) || 1;
        var gap = parseFloat(style.columnGap) || 0;
        if (!isFinite(gap)) { gap = 0; }
        var inner = body.clientWidth
          - (parseFloat(style.paddingLeft) || 0)
          - (parseFloat(style.paddingRight) || 0);
        var measure = count > 0 ? (inner - gap * (count - 1)) / count : inner;
        pitch = measure + gap;
        shown = count;
        // The last index that still leaves the view full of columns.
        var total = pitch > 0 ? Math.ceil(body.scrollWidth / pitch) : 1;
        last = Math.max(0, total - count);
      }

      function apply(animated) {
        var body = document.body;
        if (!animated) { body.style.transition = 'none'; }
        body.style.transform = 'translateX(' + (-index * pitch) + 'px)';
        if (!animated) {
          // Let the cut land before the transition is allowed back.
          void body.offsetWidth;
          body.style.transition = '';
        }
        window.webkit.messageHandlers.reader.postMessage({
          kind: 'paging', index: index, last: last, pitch: pitch, shown: shown
        });
      }

      // Leaving a paged reading has to put the body back where it was.
      // The transform is an *inline* style, so it outlives the stylesheet
      // that asked for it: page to column five, switch to Scroll, and the
      // reading stays translated a thousand points to the left with
      // nothing to say why. Scroll and Focus were both "way off to the
      // left" for exactly this reason.
      window.__origamiClearPaging = function() {
        index = 0;
        var body = document.body;
        body.style.transition = 'none';
        body.style.transform = '';
        body.style.removeProperty('--origami-columns');
        void body.offsetWidth;
        body.style.transition = '';
        window.webkit.messageHandlers.reader.postMessage({
          kind: 'paging', index: 0, last: 0, pitch: 0, shown: 1
        });
      };

      window.__origamiRemeasure = function() {
        measure();
        if (index > last) { index = last; }
        apply(false);
      };

      function turn(delta) {
        var wanted = Math.min(Math.max(0, index + delta), last);
        if (wanted === index) { return; }
        index = wanted;
        apply(true);
      }
      window.__origamiTurn = turn;
      // A button or an arrow key turns the whole spread — every column in
      // view moves on, which is what turning a page means. A swipe nudges
      // by one. Origami Text draws the same line, and it is the right one:
      // a finger is a small correction, a button is a decision.
      window.__origamiTurnSpread = function(direction) {
        turn(direction * Math.max(1, shown));
      };

      // A rotation changes the pitch and the count; the reader stays on the
      // column they were reading rather than being thrown to an offset that
      // no longer means anything.
      window.addEventListener('resize', function() {
        measure();
        if (index > last) { index = last; }
        apply(false);
      });

      // A swipe is a horizontal intent: far enough, and more sideways than
      // up. Anything else is left to the page — a tap, a selection drag, a
      // link.
      var startX = 0, startY = 0, tracking = false;
      document.addEventListener('touchstart', function(event) {
        if (event.touches.length !== 1) { tracking = false; return; }
        startX = event.touches[0].clientX;
        startY = event.touches[0].clientY;
        tracking = true;
      }, { passive: true });
      document.addEventListener('touchend', function(event) {
        if (!tracking) { return; }
        tracking = false;
        var touch = event.changedTouches[0];
        if (!touch) { return; }
        var dx = touch.clientX - startX;
        var dy = touch.clientY - startY;
        if (Math.abs(dx) < 40 || Math.abs(dx) < Math.abs(dy)) { return; }
        var selection = window.getSelection();
        if (selection && String(selection).trim()) { return; }
        // Fingers left brings the next column in, as a page turns.
        turn(dx < 0 ? 1 : -1);
      }, { passive: true });

      measure();
      apply(false);
      document.addEventListener('DOMContentLoaded', function() {
        measure();
        apply(false);
      });
    })();
    """

    /// What one column measures, end to end — its width plus the gap after
    /// it — reported from the page and again whenever the page is resized.
    ///
    /// The app cannot work this out: the column count comes from a media
    /// query, the gap from the stylesheet and the padding from the reading,
    /// and only the page knows what they all resolved to. Without it a
    /// swipe can only snap to whole screenfuls.
    public static let columnMetricsScript = """
    (function() {
      function report() {
        var body = document.body;
        var style = getComputedStyle(body);
        var count = parseInt(style.columnCount) || 1;
        var gap = parseFloat(style.columnGap) || 0;
        if (!isFinite(gap)) { gap = 0; }
        var inner = body.clientWidth
          - (parseFloat(style.paddingLeft) || 0)
          - (parseFloat(style.paddingRight) || 0);
        var width = count > 0 ? (inner - gap * (count - 1)) / count : inner;
        window.webkit.messageHandlers.reader.postMessage({
          kind: 'metrics',
          pitch: width + gap,
          columns: count
        });
      }
      report();
      window.addEventListener('resize', report);
      document.addEventListener('DOMContentLoaded', report);
    })();
    """

    /// Turning a page in Horizontal: one screenful of columns sideways.
    ///
    /// Which element to move is decided at run time rather than assumed,
    /// because it differs by platform: on macOS the body has its own
    /// sideways scroller, and on iOS and visionOS it never does — the
    /// window is the scroller there, and asking the body to scroll is a
    /// silent no-op, which is what made the page arrows appear dead.
    public static func turnPageScript(forward: Bool) -> String {
        """
        (function() {
          var sign = \(forward ? "1" : "-1");
          // Where the columns are paged by transform, the pager owns the
          // move — so an arrow and a finger do exactly the same thing.
          if (typeof window.__origamiTurnSpread === 'function') {
            window.__origamiTurnSpread(sign);
            return;
          }
          var body = document.body;
          var step = (body.clientWidth || window.innerWidth) * sign;
          if (body.scrollWidth > body.clientWidth + 1) {
            body.scrollBy({ left: step, behavior: 'smooth' });
          } else {
            window.scrollBy({ left: step, behavior: 'smooth' });
          }
        })();
        """
    }

    /// Adds — or moves — the one style element carrying Reader's CSS. Moving
    /// it matters: at document start there is no `<head>` to attach to, so
    /// the first injection lands on `<html>`, ahead of the book's own
    /// stylesheet; running again at document end puts it last, where it wins.
    /// Declares the viewport, because the book almost never does.
    ///
    /// Without `width=device-width` WebKit lays the page out at its default
    /// 980-point width and then scales the result down to fit the screen. On
    /// the smallest iPad that is a factor of 0.76, applied to everything at
    /// once: the reader asks for 17-point text and gets 13, and the 2em the
    /// reading sets either side arrives as 1.5em. It reads as a page of a
    /// desktop web site seen from too far away — which is exactly what it
    /// is.
    ///
    /// Nothing in the book will say it: the ACM article Reader tests
    /// against declares a charset and nothing else, and a reflowable book
    /// has no reason to think about viewports at all. So the reading says
    /// it on the book's behalf, and the reader's chosen size becomes the
    /// size on the glass.
    public static let viewportScript = """
    (function() {
      var meta = document.querySelector('meta[name="viewport"]');
      if (!meta) {
        meta = document.createElement('meta');
        meta.setAttribute('name', 'viewport');
        (document.head || document.documentElement).appendChild(meta);
      }
      // A book that ships a fixed-width viewport of its own is making the
      // same mistake in its own hand, so this is set rather than defaulted.
      meta.setAttribute('content', 'width=device-width, initial-scale=1');
    })();
    """

    /// `id` names the sheet, so a second one can stand beside the reading's
    /// own without either overwriting the other: the typography is rewritten
    /// on every change of theme or size, and the marks' colours are not.
    public static func styleScript(css: String, id: String = "reader-typography") -> String {
        let escaped = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
        let elementID = id
            .replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(of: "'", with: "")
        return """
        (function() {
          var id = '\(elementID)';
          var style = document.getElementById(id);
          if (!style) {
            style = document.createElement('style');
            style.id = id;
          }
          style.textContent = `\(escaped)`;
          (document.head || document.documentElement).appendChild(style);
        })();
        """
    }
}
