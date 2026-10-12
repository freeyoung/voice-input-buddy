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
        .executable(
            name: "AppleRemoteHCIService",
            targets: ["AppleRemoteHCIService"]
        ),
    ],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4")],
    targets: [
        .target(name: "BuddyRemoteCore", path: "Sources/PublicRemoteCompatibility/Core"),
        .target(name: "BuddyRemoteUI", dependencies: ["BuddyRemoteCore"], path: "Sources/PublicRemoteCompatibility/UI"),
        .executableTarget(
            name: "VoiceInputBuddy",
            dependencies: ["AudioExceptionGuard", "AppleRemoteSupport", "AppleRemoteAudioCore", "AppleRemoteHCIProtocol", "AppleRemotePacketLogger", "BuddyRemoteCore", "BuddyRemoteUI", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/VoiceInputBuddy",

            linkerSettings: [
                .linkedFramework("Network"),
            ]
        ),
        .target(
            name: "AudioExceptionGuard",
            path: "Sources/AudioExceptionGuard",
            publicHeadersPath: "include"
        ),
        .target(
            name: "AppleRemoteSupport",
            path: "Sources/AppleRemoteSupport",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("CoreFoundation"),
                .linkedFramework("IOKit"),
            ]
        ),
        .target(
            name: "AppleRemoteAudioCore",
            path: "Sources/AppleRemoteAudioCore"
        ),
        .target(
            name: "AppleRemoteHCIProtocol",
            path: "Sources/AppleRemoteHCIProtocol"
        ),
        .target(
            name: "AppleRemotePacketLogger",
            dependencies: ["AppleRemoteAudioCore", "AppleRemoteHCIProtocol"],
            path: "Sources/AppleRemotePacketLogger",
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "AppleRemoteAudioCapture",
            dependencies: ["AppleRemoteAudioCore", "AppleRemotePacketLogger"],
            path: "Sources/AppleRemoteAudioCapture",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Network"),
                .linkedFramework("Security"),
            ]
        ),
        .executableTarget(
            name: "AppleRemoteHCIService",
            dependencies: ["AppleRemoteHCIProtocol"],
            path: "Sources/AppleRemoteHCIService",
            linkerSettings: [
                .linkedFramework("Security"),
            ]
        ),
        .testTarget(name: "VoiceInputBuddyTests", dependencies: ["VoiceInputBuddy", "AppleRemoteAudioCore", "AppleRemotePacketLogger"], path: "Tests/VoiceInputBuddyTests"),
    ],
    swiftLanguageModes: [.v5]
)
