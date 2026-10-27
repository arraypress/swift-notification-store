// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-notification-store",
    // macOS only: the store it reads (usernoted's db2) is the Mac's own.
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "NotificationStore", targets: ["NotificationStore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/arraypress/swift-sqlite-reader.git", from: "0.1.0"),
    ],
    targets: [
        // Synchronous and local: no transport, nothing to await, so the
        // nonisolated-nonsending feature is left off.
        .target(name: "NotificationStore", dependencies: [
            .product(name: "SQLiteReader", package: "swift-sqlite-reader"),
        ]),
        .testTarget(name: "NotificationStoreTests", dependencies: ["NotificationStore"]),
    ]
)

// Swift 7's import rule, today: a file must import every module whose members
// it uses, rather than leaning on another file's imports.
for target in package.targets where target.type != .system && target.type != .binary && target.type != .plugin {
    target.swiftSettings = (target.swiftSettings ?? []) + [.enableUpcomingFeature("MemberImportVisibility")]
}
