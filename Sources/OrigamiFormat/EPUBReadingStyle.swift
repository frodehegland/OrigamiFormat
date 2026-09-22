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

        // Where the viewport is the sideways scroller, `html` is what
        // carries the overflow and the definite height the columns measure
        // themselves against.
        let viewport = settings.layout == .horizontal
            && settings.horizontalScroller == .viewport
            ? """

            height: 100%;
                    overflow-x: auto;
                    overflow-y: hidden;
                    -webkit-overflow-scrolling: touch;
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
                return """
                max-width: none;
                        margin: 0;
                        padding: 2.5em 2em;
                        height: 100%;
                        box-sizing: border-box;
                        column-width: 30em;
                        column-gap: 4em;
                        column-fill: auto;
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
