// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "LlamaFramework",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "LlamaFramework",
            targets: ["llama"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "llama",
            path: "../../ios-app/MedicationAdherenceApp/Frameworks/llama.xcframework"
        )
    ]
)
