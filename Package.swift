// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BetoDicta",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "BetoDicta",
            path: "Sources/BetoDicta"
        )
    ]
)
