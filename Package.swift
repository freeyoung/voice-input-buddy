// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoiceInputBuddy",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "VoiceInputBuddy",
            targets: ["VoiceInputBuddy"]
        ),
    ],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4")],
    targets: [
        .target(name: "BuddyRemoteCore", path: "Sources/PublicRemoteCompatibility/Core"),
        .target(name: "BuddyRemoteUI", dependencies: ["BuddyRemoteCore"], path: "Sources/PublicRemoteCompatibility/UI"),
        .executableTarget(
            name: "VoiceInputBuddy",
            dependencies: ["AudioExceptionGuard", "BuddyRemoteCore", "BuddyRemoteUI", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/VoiceInputBuddy",

            linkerSettings: [
                .linkedFramework("Network"),
            ]
        ),
        .target(
            name: "AudioExceptionGuard",
            path: "Sources/AudioExceptionGuard",
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(["-fobjc-arc", "-fobjc-arc-exceptions"])]
        ),
        .testTarget(name: "VoiceInputBuddyTests", dependencies: ["VoiceInputBuddy"], path: "Tests/VoiceInputBuddyTests"),
    ],
    swiftLanguageModes: [.v5]
)
