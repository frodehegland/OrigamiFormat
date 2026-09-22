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
        let link = dark ? "#7fb6ff" : "#0a58c2"
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
        a, a:visited { color: \(link); }
        blockquote {
            margin: 1.2em 0;
            padding-left: 1em;
            border-left: 3px solid \(rule);
            color: \(quiet);
        }
        hr { border: none; border-top: 1px solid \(rule); }
        figcaption, small, .caption { color: \(quiet); }
        img, svg, video { max-width: 100%; height: auto; }
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
          padding: 2.5em 2em;
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
          background: \(paper);
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
            return """
            max-width: 34em;
                    margin: 0 auto;
                    padding: 3em 1.5em 6em;
            """
        case .fullWidth:
            return """
            max-width: none;
                    margin: 0;
                    padding: 2.5em 3em 5em;
            """
        case .focus:
            // Nothing else on screen, so the column can be narrower and the
            // air around it wider — the reading and nothing but.
            return """
            max-width: 30em;
                    margin: 0 auto;
                    padding: 5em 1.5em 8em;
            """
        case .columns:
            // Not a flow. Each of the book's sections is its own box, laid
            // out in a row, and a section taller than the screen scrolls
            // inside its own box rather than spilling into the next one.
            // Origami Text's reading: what you see is the shape of the
            // argument, one section at a time, not a ribbon of prose cut
            // into screen-sized pieces.
            return """
            max-width: none;
                    margin: 0;
                    padding: 0;
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
                max-width: none;
                        margin: 0;
                        padding: 2.5em 2em;
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
                max-width: none;
                        margin: 0;
                        padding: 2.5em 2em;
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
    public static func styleScript(css: String) -> String {
        let escaped = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
        return """
        (function() {
          var id = 'reader-typography';
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
