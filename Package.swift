// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FileTransferStation",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FileTransferStation",
            path: "Sources/FileTransferStation"
        )
    ]
)
