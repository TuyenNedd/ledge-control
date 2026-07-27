// swift-tools-version:6.0
import PackageDescription

// LedgeCore holds every decision the app makes and depends on nothing but the standard
// library, so it builds and tests on any platform. The Ledge executable is macOS-only and is
// therefore added to the manifest conditionally — this keeps `swift build` and `swift test`
// working on Linux, where the gesture logic is developed and verified.
var targets: [Target] = [
    .target(
        name: "LedgeCore",
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
        name: "LedgeCoreTests",
        dependencies: ["LedgeCore"],
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),
]

#if os(macOS)
targets.append(
    .executableTarget(
        name: "Ledge",
        dependencies: ["LedgeCore"],
        // The AppKit layer is single-threaded, main-thread-bound, and full of imported
        // types that predate Sendable. Swift 6 strict concurrency adds nothing here but
        // noise, so this target stays in language mode 5.
        swiftSettings: [.swiftLanguageMode(.v5)]
    )
)
#endif

let package = Package(
    name: "Ledge",
    platforms: [.macOS(.v14)],
    targets: targets
)
