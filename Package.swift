// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PolkaKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LibraryCore", targets: ["LibraryCore"]),
        .library(name: "BookCatalog", targets: ["BookCatalog"])
    ],
    targets: [
        .target(name: "LibraryCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "BookCatalog"),
        .testTarget(name: "LibraryCoreTests", dependencies: ["LibraryCore"]),
        .testTarget(name: "BookCatalogTests", dependencies: ["BookCatalog"])
    ]
)
