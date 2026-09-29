// swift-tools-version: 6.3

import Foundation
import PackageDescription

let frameworkPath = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("../../ios-app/MedicationAdherenceApp/Frameworks/llama.xcframework")
    .standardizedFileURL
let localLlamaDisabled = ProcessInfo.processInfo.environment["MEDCUE_DISABLE_LOCAL_LLAMA"] == "1"
    || !FileManager.default.fileExists(atPath: frameworkPath.appendingPathComponent("Info.plist").path)
let llamaProductTargets = localLlamaDisabled ? ["LlamaFrameworkStub"] : ["llama"]
let llamaTargets: [Target] = localLlamaDisabled
    ? [
        .target(
            name: "LlamaFrameworkStub",
            path: "Sources/LlamaFrameworkStub"
        )
    ]
    : [
        .binaryTarget(
            name: "llama",
            path: "../../ios-app/MedicationAdherenceApp/Frameworks/llama.xcframework"
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
