// swift-tools-version:5.9
// Package.swift is Swift's go.mod: it names the package, the minimum OS,
// and what to build. "executableTarget" = produce a runnable app binary.
import PackageDescription

let package = Package(
    name: "GlassClip",
    platforms: [
        // Minimum macOS 14 — everything we use (MenuBarExtra, modern
        // SwiftUI) exists from here on, and it runs fine on macOS 26.
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "GlassClip",
            path: "Sources/GlassClip"
        )
    ]
)
