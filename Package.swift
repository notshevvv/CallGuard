// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "CallGuard",
    platforms: [.macOS("14.4")],
    targets: [
        .executableTarget(
            name: "CallGuard",
            path: "Sources/CallGuard",
            swiftSettings: [.unsafeFlags(["-Ounchecked"])],
            linkerSettings: [
                .linkedFramework("CoreAudio"), .linkedFramework("AppKit"), .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement"), .linkedFramework("Carbon"),
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
