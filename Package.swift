// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GPXOrganizer",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "BCCore", path: "Sources/BCCore"),
        .executableTarget(name: "GPXOrganizer", dependencies: ["BCCore"], path: "Sources/GPXOrganizer",
                          // records the current SDK, so macOS draws the app with its current look (grouped toolbar buttons like the Finder);
                          // the app still runs on macOS 14
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-platform_version", "-Xlinker", "macos", "-Xlinker", "14.0", "-Xlinker", "26.0"])]),
        .executableTarget(name: "bcprobe", dependencies: ["BCCore"], path: "Sources/bcprobe"),
    ]
)
