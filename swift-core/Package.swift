// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "MedicationAdherenceCore",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "MedicationAdherenceCore",
            targets: ["MedicationAdherenceCore"]
        )
    ],
    targets: [
        .target(
            name: "MedicationAdherenceCore"
        ),
        .testTarget(
            name: "MedicationAdherenceCoreTests",
            dependencies: ["MedicationAdherenceCore"]
        )
    ],
    swiftLanguageModes: [.v6]
)
