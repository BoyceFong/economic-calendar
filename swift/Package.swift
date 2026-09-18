// swift-tools-version: 6.2
// Economic Calendar — native macOS (SwiftUI + Liquid Glass) rewrite of the Python/PyQt widget.
import PackageDescription

let package = Package(
    name: "EconomicCalendar",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .executableTarget(
            name: "EconomicCalendar",
            path: "Sources/EconomicCalendar",
            resources: [
                .copy("Resources/ExtractCalendar.js")
            ]
        )
    ]
)
