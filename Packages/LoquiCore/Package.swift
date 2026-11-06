// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LoquiCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "LoquiEngines", targets: ["LoquiEngines"]),
        .library(name: "LoquiCatalog", targets: ["LoquiCatalog"]),
        // L'unico modulo linkato dalla tastiera: nessuna dipendenza, nessun codice di rete.
        .library(name: "LoquiShared", targets: ["LoquiShared"]),
    ],
    dependencies: [
        // Senza trait: niente sintesi vocale, diarizzazione e normalizzazione del testo.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.18.2", traits: []),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.1.1"),
    ],
    targets: [
        .target(name: "LoquiShared"),
        .target(
            name: "LoquiCatalog",
            resources: [.copy("Resources/models.json")]
        ),
        .target(
            name: "LoquiEngines",
            dependencies: [
                "LoquiCatalog",
                "LoquiShared",
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),
        .testTarget(name: "LoquiSharedTests", dependencies: ["LoquiShared"]),
        .testTarget(name: "LoquiCatalogTests", dependencies: ["LoquiCatalog"]),
        .testTarget(name: "LoquiEnginesTests", dependencies: ["LoquiEngines"]),
    ]
)
