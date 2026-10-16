// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FileTransferStation",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FileTransferStation", targets: ["FileTransferStation"])
    ],
    targets: [
        // Core logic + UI live in a library so they can be unit-tested.
        .target(
            name: "FileTransferStationKit",
            path: "Sources/FileTransferStationKit"
        ),
        // Thin executable entry point.
        .executableTarget(
            name: "FileTransferStation",
            dependencies: ["FileTransferStationKit"],
            path: "Sources/FileTransferStation"
        ),
        .testTarget(
            name: "FileTransferStationKitTests",
            dependencies: ["FileTransferStationKit"],
            path: "Tests/FileTransferStationKitTests"
        )
    ]
)
