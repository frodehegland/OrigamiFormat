import Testing
import Foundation
@testable import OrigamiFormat

/// The palettes are accommodations, not decoration — several are cited
/// clinical values — so these pin the numbers rather than merely exercising
/// the lookup.
@Suite("Reading palettes")
struct OrigamiPaletteTests {

    @Test("Every theme the reading offers has colours, and system has none")
    func coverage() {
        for theme in EPUBReadingTheme.allCases where theme != .system {
            #expect(theme.palette != nil, "\(theme.rawValue) lost its palette")
        }
        #expect(EPUBReadingTheme.system.palette == nil)
        #expect(OrigamiPalette.ordered.count == EPUBReadingTheme.allCases.count - 1)
    }

    @Test("Origami Text's name for the system theme means the same theme")
    func highContrastIsSystem() {
        // Origami Text persists `highContrast`; Reader persists `system`.
        #expect(OrigamiPalette.colours("highContrast") == nil)
        #expect(OrigamiPalette.colours("system") == nil)
        #expect(OrigamiPalette.canonicalName("highContrast") == OrigamiPalette.systemName)
    }

    @Test("The documented accommodations keep their documented values")
    func citedValues() throws {
        // British Dyslexia Association cream; intentionally below 4.5:1.
        let cream = try #require(OrigamiPalette.colours("cream"))
        #expect(cream.lightPaper == "#fffdd0")
        // Rello & Bigham, CHI 2017 — the peach that read best.
        #expect(try #require(OrigamiPalette.colours("softPeach")).lightPaper == "#ffe4c4")
        // Black on yellow, for macular degeneration.
        let macular = try #require(OrigamiPalette.colours("macular"))
        #expect(macular.lightPaper == "#ffff00" && macular.lightInk == "#000000")
        // Schoonover's Solarized base3/base00 and base03/base0.
        let solarized = try #require(OrigamiPalette.colours("solarized"))
        #expect(solarized.lightPaper == "#fdf6e3" && solarized.darkPaper == "#002b36")
    }

    @Test("A name neither app knows gets no colours rather than a guess")
    func unknownName() {
        #expect(OrigamiPalette.colours("chartreuse") == nil)
        #expect(OrigamiPalette.colours("") == nil)
    }

    @Test("Darkness is judged from the colour, not from the system")
    func darkness() {
        // Night is a dark page even when the system is in a light appearance.
        #expect(EPUBReadingTheme.night.paperIsDark(dark: true))
        #expect(!EPUBReadingTheme.macular.paperIsDark(dark: false))
        #expect(OrigamiPalette.isDark("#000000"))
        #expect(!OrigamiPalette.isDark("#ffffff"))
    }

    @Test("A malformed hex is refused rather than read as black")
    func malformedHex() {
        #expect(OrigamiPalette.components(of: "#xyzxyz") == nil)
        #expect(OrigamiPalette.components(of: "#fff") == nil)
        #expect(OrigamiPalette.components(of: "") == nil)
        // White, with or without the hash, and with stray spaces.
        let white = OrigamiPalette.components(of: "  #FFFFFF ")
        #expect(white?.red == 1 && white?.green == 1 && white?.blue == 1)
    }

    @Test("The table has no duplicate names")
    func noDuplicates() {
        let names = OrigamiPalette.ordered.map(\.name)
        #expect(Set(names).count == names.count)
    }
}
