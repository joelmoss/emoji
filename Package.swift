// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Emoji",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Emoji",
            dependencies: ["KeyboardShortcuts", "Sparkle"],
            resources: [.copy("emojis.json")]
        ),
        .testTarget(name: "EmojiTests", dependencies: ["Emoji"]),
    ]
)
