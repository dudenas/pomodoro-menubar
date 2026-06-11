// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pomodoro",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Pomodoro",
            path: "Sources/Pomodoro"
        )
    ]
)
