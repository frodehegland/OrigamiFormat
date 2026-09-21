# OrigamiFormat

The Origami Text format, as code: the annotation model, its sidecar, the
anchoring ladder, document identity, the EPUB container reader, and the
reading presentation. No UI, no app model, no network — Foundation and
Compression only, building for macOS, iOS and visionOS.

## Why it exists

Reader and Origami Text each carried their own copy of this code, kept in
step by hand. They had stopped being in step: `WebAnnotation` was 58%
identical, `AnnotationStore` 53%, the reading palettes 34%. Worse than
drift, the two apps had come to disagree about **what a document is** —
Origami Text named one `origamitext://open/<address>`, Reader named it
`urn:x-reader:<record id>` — so the same book annotated in both produced
notes about two unrelated resources as far as any conforming consumer could
tell.

That is the interoperability failure the Origami format exists to argue
against, happening between its own two readers. A format whose claim is
that structure should be declared and durable should not be implemented
twice by the same people.

So: once, here, tested here, and pointed at anyone implementing the format.

## What's in it

| Type | |
|---|---|
| `WebAnnotation` | one W3C Web Annotation (the model Hypothesis and Readium use), hand-coded so the JSON is real JSON-LD. Motivations, a selector ladder (`FragmentSelector` on the document's own stable id, `TextQuoteSelector` with context, position, Readium progression, RFC 8118 page), and the two apps' extensions: `origami:placement`, `origami:float`, `reader:place` |
| `ReaderAnnotationKind` | the judgments a reader stamps on words, travelling as standard W3C tagging bodies |
| `AnnotationStore` | `<id>.annotations.jsonld` sidecars holding an `AnnotationCollection`. Never written into the document: the book is the author's, the notes are the reader's |
| `AnnotationAnchor` | the re-anchoring cascade — stable id, exact words in that unit, fuzzy words in that unit, exact words anywhere (context-scored), fuzzy words anywhere (hinted by position/progression), and unit scope rather than breaking |
| `DocumentIdentity` | what names a document, and what names the *same* document |
| `EPUBPackage`, `ZipReader`, `EPUBMetadata` | container.xml → OPF → spine, EPUB3 `nav` and EPUB2 NCX, cover images. Nothing is inflated until asked for |
| `EPUBReadingStyle` | the CSS and page scripts a reading lays over a book: typography, the dark-ink correction, on-the-fly code highlighting, `data-latex` gathering, and the selection bridge that reports **which addressable unit** a selection sits in |
| `EPUBReadingTheme` / `Layout` / `Font`, `OrigamiPalette` | the 17 palettes and the reading modes |
| `DOI` | reading a DOI out of text |

## Document identity

1. **The DOI**, where the work has one. It is the name the rest of the
   world already uses, it resolves, and it is not ours to invent.
2. **A content hash** otherwise — `urn:origami:sha256:<hex>` — so two
   readers holding the same file reach the same name without asking
   anybody. A URN, not a URL: it names rather than locates.
3. **A local name** last — `urn:origami:local:<name>` — for a card with
   neither. Better a name one library understands than no name.

Reading is deliberately more generous than writing: `normalised` folds
every form either app has ever written onto one comparable key, so notes
already on disk keep resolving. Use `isSameDocument(_:_:)` rather than
comparing target strings.

## The division of labour

The format's own argument, which the code follows: **the substrate keeps
the structure; the reader presents it.** So `EPUBReadingStyle`'s code
highlighting paints the rendered page and never rewrites the DOM's text —
copy a block and you get the source character for character — and nothing
here writes into a book.

## Using it

```swift
.package(path: "../OrigamiFormat")
```

Reader reaches it through `AugmentedLibraryCore`, which re-exports it;
Origami Text links it into `LiquidView`. Both keep their own colour
plumbing, persisted settings and UI — only the format is shared.

## Tests

71, `swift test`. The palette tests pin the cited clinical values (the
British Dyslexia Association's cream, the CHI 2017 peach, black-on-yellow
for macular degeneration) rather than merely exercising the lookup: those
are accommodations, and a wrong number is a reader who cannot read.

MIT, as the article says the readers are.
