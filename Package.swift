// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GPXOrganizer",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "BCCore", path: "Sources/BCCore"),
        .executableTarget(name: "GPXOrganizer", dependencies: ["BCCore"], path: "Sources/GPXOrganizer"),
        .executableTarget(name: "bcprobe", dependencies: ["BCCore"], path: "Sources/bcprobe"),
    ]
)
