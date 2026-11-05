// swift-tools-version: 6.3

import Foundation
import PackageDescription

// A local opt-in also works when Xcode is launched from Finder. It is ignored
// source-output state, never included in the source package or CI checkout.
let localOptIn = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().appendingPathComponent("../../.codex-local/enable-local-llama").standardizedFileURL
let localLlamaEnabled = (ProcessInfo.processInfo.environment["MEDCUE_ENABLE_LOCAL_LLAMA"] == "1"
    || FileManager.default.fileExists(atPath: localOptIn.path))
    && ProcessInfo.processInfo.environment["MEDCUE_DISABLE_LOCAL_LLAMA"] != "1"
let llamaProductTargets = localLlamaEnabled ? ["llama"] : ["LlamaFrameworkStub"]
let llamaTargets: [Target] = localLlamaEnabled
    ? [
        .binaryTarget(
            name: "llama",
            path: "../../ios-app/MedicationAdherenceApp/Frameworks/llama.xcframework"
        )
    ]
    : [
        .target(
            name: "LlamaFrameworkStub",
            path: "Sources/LlamaFrameworkStub"
        )
    ]

let package = Package(
    name: "LlamaFramework",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "LlamaFramework",
            targets: llamaProductTargets
        )
    ],
    targets: llamaTargets
)
