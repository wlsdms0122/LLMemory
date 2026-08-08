// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LLMemory",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "LLMemory", targets: ["LLMemory"]),
        .executable(name: "llmemory", targets: ["LLMemoryCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.1.0"),
        .package(url: "https://github.com/wlsdms0122/Storage", from: "1.2.1")
    ],
    targets: [
        .target(
            name: "LLMemory",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "Storage", package: "Storage")
            ],
            linkerSettings: [
                // PPMI + truncated SVD (note_vectors) - LAPACK dgesvd via Accelerate.
                .linkedFramework("Accelerate")
            ]
        ),
        .executableTarget(
            name: "LLMemoryCLI",
            dependencies: [
                "LLMemory",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "LLMemoryTests",
            dependencies: [
                "LLMemory",
                // Force the executable to build before tests run so the CLI integration suite can invoke the real binary end-to-end.
                "LLMemoryCLI"
            ]
        )
    ]
)
