// swift-tools-version: 5.9
import PackageDescription

// Foundation-only persistence tests on a Mac. The iPhone app is the Xcode project.
let package = Package(
    name: "ExperimentModel",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "ExperimentModel", targets: ["ExperimentModel"])],
    targets: [
        .target(name: "ExperimentModel", path: "Sources",
                exclude: ["Camera.swift", "ExperimentApp.swift", "ExperimentModel.swift",
                          "MediaEngine.swift", "Probe.swift"], sources: ["Project.swift"]),
        .testTarget(name: "ExperimentModelTests", dependencies: ["ExperimentModel"], path: "Tests")
    ]
)
