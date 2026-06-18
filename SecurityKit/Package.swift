// swift-tools-version: 5.9
import PackageDescription

// SecurityKit — small, dependency-free security helpers shared by the app.
// Deliberately has NO Firebase/UIKit dependency so it builds and tests fast
// (`swift test`) without the iOS app's heavy dependency graph.
let package = Package(
    name: "SecurityKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v12)
    ],
    products: [
        .library(name: "SecurityKit", targets: ["SecurityKit"])
    ],
    targets: [
        .target(name: "SecurityKit"),
        .testTarget(name: "SecurityKitTests", dependencies: ["SecurityKit"])
    ]
)
