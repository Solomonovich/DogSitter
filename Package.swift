// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "דוגסיטר",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .library(
            name: "App",
            targets: ["App"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk", "12.12.0"..<"13.0.0"),
        .package(url: "https://github.com/google/GoogleSignIn-iOS", "7.0.0"..<"8.0.0")
    ],
    targets: [
        .target(
            name: "App",
            dependencies: [
                .product(name: "FirebaseAnalytics", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
                .product(name: "GoogleSignInSwift", package: "GoogleSignIn-iOS")
            ],
            path: "Sources",
            resources: [
                .process("GoogleService-Info.plist")
            ]
        )
    ]
)
