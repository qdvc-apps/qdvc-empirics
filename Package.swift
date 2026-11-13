// swift-tools-version: 5.10
//
// QDVC Empirics for macOS — a native app for qualitative data analysis of
// interview transcripts, documents and articles: highlight selections, code
// them to open codes, build axial codes from those, answer codebooks, and
// keep it all in a Git-friendly folder of plain YAML files.
//
// The workspace (YAML) never holds the full-texts; those stay in a separate,
// read-only folder whose location is remembered per Mac (docs/FILE_FORMAT.md).
//
// No dependencies, and nothing in the app touches the network
// (docs/MAINTENANCE.md §Network).
//
// Build:   swift build            (or open this folder in Xcode)
// Test:    swift test
// Bundle:  scripts/build-app.sh   (ad-hoc signed, sandboxed .app; no Apple account needed)

import PackageDescription

var products: [Product] = [
    .library(name: "EmpiricsCore", targets: ["EmpiricsCore"]),
]
var targets: [Target] = [
    // Pure model layer: Foundation only (its own YAML reader and writer and
    // its own SHA-256), no AppKit/SwiftUI, unit-testable on Linux too.
    .target(name: "EmpiricsCore"),
    .testTarget(
        name: "EmpiricsCoreTests",
        dependencies: ["EmpiricsCore"]
    ),
]

#if os(macOS)
// The SwiftUI/AppKit front-end. Declared on macOS only, so the core and its
// tests also build with a Linux Swift toolchain (docs/MAINTENANCE.md).
products.insert(.executable(name: "QDVCEmpirics", targets: ["QDVCEmpirics"]), at: 0)
targets.insert(.executableTarget(name: "QDVCEmpirics", dependencies: ["EmpiricsCore"]), at: 1)
#endif

let package = Package(
    name: "QDVCEmpirics",
    platforms: [.macOS("14.4")],
    products: products,
    targets: targets
)
