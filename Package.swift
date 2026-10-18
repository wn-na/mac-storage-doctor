// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "MacStorageDoctor", platforms: [.macOS(.v14)],
    products: [.executable(name: "MacStorageDoctor", targets: ["MacStorageDoctor"]), .library(name: "StorageCore", targets: ["StorageCore"])],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "StorageCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "MacStorageDoctor", dependencies: ["StorageCore"]),
        .testTarget(name: "StorageCoreTests", dependencies: ["StorageCore"])
    ])
