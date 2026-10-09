// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CCEmail",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CCEmail", targets: ["CCEmail"]),
    ],
    targets: [
        // Parsing, file I/O and the claude process wrapper. No SwiftUI, so it's unit-testable.
        .target(name: "CCEmailCore"),
        // The SwiftUI app.
        .executableTarget(
            name: "CCEmail",
            dependencies: ["CCEmailCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CCEmailCoreTests",
            dependencies: ["CCEmailCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
