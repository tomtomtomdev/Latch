// swift-tools-version: 6.0
import PackageDescription

// LatchKit — the Domain and Data layers of Latch as a local package so the
// dependency rule is enforced structurally: `LatchDomain` declares no dependencies
// (it imports nothing outward), `LatchData` depends only on `LatchDomain`. The App
// (Presentation) layer lives in the Xcode target and links both products. (SPEC §3)
//
// Module names are `LatchDomain` / `LatchData` rather than `Domain` / `Data` to avoid
// shadowing `Foundation.Data` at call sites that import both.
let package = Package(
    name: "LatchKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LatchDomain", targets: ["LatchDomain"]),
        .library(name: "LatchData", targets: ["LatchData"]),
    ],
    targets: [
        .target(name: "LatchDomain"),
        .target(name: "LatchData", dependencies: ["LatchDomain"]),
        .testTarget(name: "LatchDomainTests", dependencies: ["LatchDomain"]),
        .testTarget(name: "LatchDataTests", dependencies: ["LatchData"]),
    ]
)
