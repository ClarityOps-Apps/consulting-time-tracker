// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Time",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Time", targets: ["Time"])
    ],
    targets: [
        .executableTarget(
            name: "Time",
            path: "Time",
            exclude: [
                "Info.plist",
                "Time.entitlements",
                "Assets.xcassets"
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit")
            ]
        )
    ]
)
