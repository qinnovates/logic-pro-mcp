// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LogicProMCP",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.0"),
    ],
    targets: [
        // Library target: all source files except main.swift
        .target(
            name: "LogicProMCPLib",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources/LogicProMCPLib",
            resources: [
                .copy("Config/keybindings.json"),
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreMIDI"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
                .linkedFramework("Network"),
            ]
        ),
        // Executable target: only main.swift, depends on the library
        .executableTarget(
            name: "LogicProMCP",
            dependencies: ["LogicProMCPLib"],
            path: "Sources/LogicProMCP"
        ),
        .testTarget(
            name: "LogicProMCPTests",
            dependencies: ["LogicProMCPLib"],
            path: "Tests/LogicProMCPTests"
        ),
    ]
)
