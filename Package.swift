// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Skillbook",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(
            name: "Skillbook",
            path: "Sources/Skillbook"
        )
    ]
)
