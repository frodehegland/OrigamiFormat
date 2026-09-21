// swift-tools-version: 6.2
import PackageDescription

// OrigamiFormat — the Origami Text format, and nothing else.
//
// Reader and Origami Text each had their own copy of this code, and the
// copies had begun to drift: the annotation model was 58% identical, the
// theme palettes 34%, and the two apps had come to disagree about what a
// document even *is* (`origamitext://open/<id>` versus
// `urn:x-reader:<id>`), so the same book annotated in both produced notes
// about two different resources. For a format whose argument is that
// structure should be declared and durable, that is the wrong bug to have.
//
// So the format lives here once: the W3C annotation model and its sidecar,
// the anchoring ladder, document identity, the EPUB container reader, and
// the reading presentation (CSS, scripts, palettes). No UI, no app model,
// no network — Foundation and Compression only, so it builds for macOS,
// iOS and visionOS.
//
// `defaultIsolation(MainActor.self)` matches the two modules this code came
// from, so the source compiles unchanged in both.
let package = Package(
    name: "OrigamiFormat",
    platforms: [.macOS("26.0"), .iOS("26.0"), .visionOS("26.0")],
    products: [
        .library(name: "OrigamiFormat", targets: ["OrigamiFormat"]),
    ],
    targets: [
        .target(
            name: "OrigamiFormat",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "OrigamiFormatTests",
            dependencies: ["OrigamiFormat"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
