import Foundation

/// The reading palettes, held once.
///
/// Reader and Origami Text each carried their own copy of this table. The
/// hex values happened to still agree when they were compared, which is
/// luck rather than a property: nothing connected them, and several are not
/// aesthetic choices that may drift freely — they are documented
/// accommodations, and a wrong value is a reader who cannot read.
///
/// Sources: the British Dyslexia Association's style guide (cream); Rello &
/// Bigham, CHI 2017 (softPeach); the Irlen Institute's overlay tints;
/// Almutairi et al. on macular degeneration (black on yellow); Schoonover's
/// Solarized; TheraSpecs FL-41 (night); Knowledge Space's own gradations.
///
/// Each app keeps its own enum and its own colour plumbing — SwiftUI
/// `Color`, user overrides, persisted raw values. Only the numbers live
/// here, so only the numbers cannot drift.
public nonisolated enum OrigamiPalette {

    /// One theme's four colours: paper and ink, for a light appearance and
    /// for a dark one.
    public struct Colours: Hashable, Sendable {
        public var lightPaper: String
        public var lightInk: String
        public var darkPaper: String
        public var darkInk: String

        public init(lightPaper: String, lightInk: String,
                    darkPaper: String, darkInk: String) {
            self.lightPaper = lightPaper
            self.lightInk = lightInk
            self.darkPaper = darkPaper
            self.darkInk = darkInk
        }
    }

    /// The canonical name for the theme that has no palette of its own —
    /// the one that defers to the host app's ordinary paper and ink.
    /// Origami Text calls it `highContrast`; Reader calls it `system`.
    public static let systemName = "system"

    /// Every named palette, in the order the two apps present them.
    /// `system` is absent by design: it has no colours to state.
    public static let ordered: [(name: String, colours: Colours)] = [
        ("sepia",       Colours(lightPaper: "#eee2cc", lightInk: "#32281d",
                                darkPaper: "#393329", darkInk: "#ede3d3")),
        ("grey",        Colours(lightPaper: "#dddddd", lightInk: "#272727",
                                darkPaper: "#3f3f3f", darkInk: "#dddddd")),
        ("gentle",      Colours(lightPaper: "#ffffff", lightInk: "#666666",
                                darkPaper: "#353534", darkInk: "#aeaeae")),
        ("lowContrast", Colours(lightPaper: "#dcdddc", lightInk: "#585958",
                                darkPaper: "#222221", darkInk: "#7b7a79")),
        ("warm",        Colours(lightPaper: "#f5ecdc", lightInk: "#494742",
                                darkPaper: "#3d3633", darkInk: "#f9f9f8")),
        ("warmStrong",  Colours(lightPaper: "#c3ad9b", lightInk: "#26231f",
                                darkPaper: "#26201e", darkInk: "#ffffff")),
        ("cool",        Colours(lightPaper: "#d8e1ea", lightInk: "#575a5d",
                                darkPaper: "#2b3e4f", darkInk: "#b1bbc0")),
        ("coolStrong",  Colours(lightPaper: "#b7c4cf", lightInk: "#37536b",
                                darkPaper: "#2c3840", darkInk: "#b1b9be")),
        ("cream",       Colours(lightPaper: "#fffdd0", lightInk: "#1a1a2e",
                                darkPaper: "#1a1a0a", darkInk: "#fffdd0")),
        ("softPeach",   Colours(lightPaper: "#ffe4c4", lightInk: "#2c1810",
                                darkPaper: "#2c1810", darkInk: "#ffe4c4")),
        ("irlenYellow", Colours(lightPaper: "#fffff0", lightInk: "#1a1a1a",
                                darkPaper: "#1a1a00", darkInk: "#fffff0")),
        ("irlenGreen",  Colours(lightPaper: "#d8f5d8", lightInk: "#0d2d0d",
                                darkPaper: "#0d2d0d", darkInk: "#d8f5d8")),
        ("irlenPurple", Colours(lightPaper: "#e8d9f0", lightInk: "#1f0d2d",
                                darkPaper: "#1f0d2d", darkInk: "#e8d9f0")),
        ("macular",     Colours(lightPaper: "#ffff00", lightInk: "#000000",
                                darkPaper: "#333300", darkInk: "#ffff00")),
        ("night",       Colours(lightPaper: "#faf5e4", lightInk: "#2d1a0d",
                                darkPaper: "#1a1209", darkInk: "#d4b896")),
        ("solarized",   Colours(lightPaper: "#fdf6e3", lightInk: "#657b83",
                                darkPaper: "#002b36", darkInk: "#839496")),
    ]

    private static let table: [String: Colours] =
        Dictionary(uniqueKeysWithValues: ordered.map { ($0.name, $0.colours) })

    /// The palette a theme name stands for, or nil for the system theme
    /// (under either app's name for it) and for a name neither app knows.
    public static func colours(_ name: String) -> Colours? {
        table[canonicalName(name)]
    }

    /// Folds each app's spelling onto one name. Origami Text's
    /// `highContrast` and Reader's `system` are the same theme.
    public static func canonicalName(_ name: String) -> String {
        name == "highContrast" ? systemName : name
    }

    // MARK: - Reading a hex

    public static func components(of hex: String) -> (red: Double, green: Double, blue: Double)? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xff) / 255,
                Double((value >> 8) & 0xff) / 255,
                Double(value & 0xff) / 255)
    }

    /// Relative luminance, the sRGB coefficients — what decides whether a
    /// page needs the book's own near-black ink lifted.
    public static func luminance(of hex: String) -> Double {
        guard let parts = components(of: hex) else { return 1 }
        return 0.2126 * parts.red + 0.7152 * parts.green + 0.0722 * parts.blue
    }

    /// Whether a paper is dark enough that a book's own ink will vanish on
    /// it. Asked of the colour, not of the system: Night read in daylight
    /// is a dark page in a light appearance.
    public static func isDark(_ hex: String) -> Bool { luminance(of: hex) < 0.45 }
}
