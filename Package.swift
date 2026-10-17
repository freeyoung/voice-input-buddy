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
        .executableTarget(
            name: "VoiceInputBuddy",
            dependencies: ["AudioExceptionGuard", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/VoiceInputBuddy"
        ),
        .target(
            name: "AudioExceptionGuard",
            path: "Sources/AudioExceptionGuard",
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(["-fobjc-arc", "-fobjc-arc-exceptions"])]
        ),
        .target(name: "AudioExceptionFixtures", dependencies: ["AudioExceptionGuard"],
            path: "Tests/AudioExceptionFixtures", publicHeadersPath: "include"),
        .testTarget(name: "VoiceInputBuddyTests", dependencies: ["VoiceInputBuddy", "AudioExceptionFixtures"], path: "Tests/VoiceInputBuddyTests"),
    ],
    swiftLanguageModes: [.v5]
)
