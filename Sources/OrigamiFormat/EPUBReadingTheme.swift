import Foundation

/// The reading's colours, ported from Origami Text's `ReaderTheme` — the
/// same names, the same palettes, so a book looks the same in both apps.
///
/// These are not decoration. Several are the standard accommodations: the
/// British Dyslexia Association's cream, the soft peach that read best for
/// dyslexic readers in the CHI 2017 study, the Irlen overlay simulations,
/// black-on-yellow for macular degeneration, and a warm night palette that
/// avoids the blue-heavy tones that trigger photophobia.
public nonisolated enum EPUBReadingTheme: String, CaseIterable, Identifiable, Sendable {
    // Standard
    case system
    case sepia
    case grey
    // Gentle contrast gradations (from Knowledge Space)
    case gentle
    case lowContrast
    case warm
    case warmStrong
    case cool
    case coolStrong
    // Dyslexia / visual stress
    case cream          // BDA standard; intentionally below 4.5:1
    case softPeach      // top CHI 2017 performer for dyslexic readers
    // Irlen syndrome overlay simulations
    case irlenYellow
    case irlenGreen
    case irlenPurple
    // Macular degeneration
    case macular        // black on yellow; most AMD readers preferred this
    // Photophobia / night reading
    case night          // warm dark, no blue-heavy tones
    case solarized      // Schoonover's perceptually uniform scheme

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system:       "System"
        case .sepia:        "Sepia"
        case .grey:         "Grey"
        case .gentle:       "Gentle"
        case .lowContrast:  "Low Contrast"
        case .warm:         "Warm"
        case .warmStrong:   "Warm Strong"
        case .cool:         "Cool"
        case .coolStrong:   "Cool Strong"
        case .cream:        "Cream"
        case .softPeach:    "Soft Peach"
        case .irlenYellow:  "Irlen Yellow"
        case .irlenGreen:   "Irlen Green"
        case .irlenPurple:  "Irlen Purple"
        case .macular:      "Macular"
        case .night:        "Night"
        case .solarized:    "Solarized"
        }
    }

    /// Why a reader might choose it, where the reason is not the look.
    public var note: String? {
        switch self {
        case .cream:       "British Dyslexia Association"
        case .softPeach:   "Read best for dyslexic readers (CHI 2017)"
        case .irlenYellow, .irlenGreen, .irlenPurple: "Irlen overlay"
        case .macular:     "Macular degeneration"
        case .night:       "Night reading, photophobia"
        default:           nil
        }
    }

    /// Light background, light text, dark background, dark text — read from
    /// `OrigamiPalette`, the one table both apps now share, so the numbers
    /// cannot drift apart again. `system` has none: it follows the host
    /// app's ordinary paper and ink.
    public var palette: (lightPaper: String, lightInk: String,
                         darkPaper: String, darkInk: String)? {
        guard let colours = OrigamiPalette.colours(rawValue) else { return nil }
        return (colours.lightPaper, colours.lightInk,
                colours.darkPaper, colours.darkInk)
    }

    /// Reader's own paper and ink, used by `system` and as the fallback.
    static let systemLight = (paper: "#fbfaf8", ink: "#16171a")
    static let systemDark = (paper: "#1c1d1f", ink: "#e8e6e3")

    public func paperHex(dark: Bool) -> String {
        guard let palette else { return dark ? Self.systemDark.paper : Self.systemLight.paper }
        return dark ? palette.darkPaper : palette.lightPaper
    }

    public func inkHex(dark: Bool) -> String {
        guard let palette else { return dark ? Self.systemDark.ink : Self.systemLight.ink }
        return dark ? palette.darkInk : palette.lightInk
    }

    /// Whether the paper is dark enough that the book's own near-black ink
    /// has to be lifted. A theme can be dark in a light appearance (Night
    /// read in daylight), so this asks the colour rather than the system.
    public func paperIsDark(dark: Bool) -> Bool {
        OrigamiPalette.isDark(paperHex(dark: dark))
    }

    /// The paper as components, for the view behind the page.
    public func paperComponents(dark: Bool) -> (red: Double, green: Double, blue: Double) {
        OrigamiPalette.components(of: paperHex(dark: dark)) ?? (1, 1, 1)
    }

    public static func components(of hex: String) -> (red: Double, green: Double, blue: Double)? {
        OrigamiPalette.components(of: hex)
    }

    static func luminance(of hex: String) -> Double { OrigamiPalette.luminance(of: hex) }
}

/// How the book is laid out — Origami Text's reading modes, in the terms a
/// WebView rendering can honour.
public nonisolated enum EPUBReadingLayout: String, CaseIterable, Identifiable, Sendable {
    /// The book's own pages, read down. The one vertical reading — Full
    /// Width used to stand beside it, offering the same reading with the
    /// margins taken off, which is a setting rather than a way of reading.
    case scrolling
    /// Pages side by side — two, or more when the window is wide, with the
    /// text flowing on from one into the next.
    case horizontal
    /// A column for each of the book's sections, side by side: the column
    /// begins at its heading and holds that section and nothing else, and a
    /// section longer than the screen is scrolled within its own column.
    /// Origami Text's reading — what it shows is the shape of the argument
    /// rather than a continuous ribbon of prose.
    case columns
    /// The reading alone: no rail, no foot, a narrow measure.
    case focus

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .scrolling:  "Scroll"
        case .horizontal: "Horizontal"
        case .columns:    "Columns"
        case .focus:      "Focus"
        }
    }

    public var help: String {
        switch self {
        case .scrolling:  "The book's own pages, read down"
        case .horizontal: "Pages side by side, the text flowing on from one to the next"
        case .columns:    "A column for each section, scrolled within itself"
        case .focus:      "The reading alone, with nothing else on screen"
        }
    }

    public var systemImage: String {
        switch self {
        case .scrolling:  "scroll"
        case .horizontal: "book.pages"
        case .columns:    "rectangle.split.3x1"
        case .focus:      "rectangle.center.inset.filled"
        }
    }

    /// Whether the reader turns pages sideways rather than scrolling down.
    public var isPaged: Bool { self == .horizontal || self == .columns }

    /// Whether each column is one of the book's own sections, rather than
    /// the next stretch of a continuous flow.
    public var isSectioned: Bool { self == .columns }
}

/// The faces a reading can be set in. A book's own font is kept where the
/// reader has not asked for one.
public nonisolated enum EPUBReadingFont: String, CaseIterable, Identifiable, Sendable {
    case book
    case system
    case serif
    case sansSerif
    case rounded
    case monospaced

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .book:       "The Book's Own"
        case .system:     "System"
        case .serif:      "Serif"
        case .sansSerif:  "Sans Serif"
        case .rounded:    "Rounded"
        case .monospaced: "Monospaced"
        }
    }

    /// The CSS family, or nil to leave the book's own face alone.
    public var cssFamily: String? {
        switch self {
        case .book:       nil
        case .system:     "-apple-system, BlinkMacSystemFont, system-ui, sans-serif"
        case .serif:      "'New York', Georgia, 'Iowan Old Style', serif"
        case .sansSerif:  "'SF Pro Text', -apple-system, Helvetica, Arial, sans-serif"
        case .rounded:    "'SF Pro Rounded', ui-rounded, -apple-system, sans-serif"
        case .monospaced: "'SF Mono', ui-monospace, Menlo, monospace"
        }
    }
}
