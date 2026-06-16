// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StabilizerEventAnalyzer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "StabilizerEventAnalyzer", targets: ["StabilizerEventAnalyzer"])
    ],
    targets: [
        .executableTarget(
            name: "StabilizerEventAnalyzer",
            path: "Sources/StabilizerEventAnalyzer"
        )
    ]
)
