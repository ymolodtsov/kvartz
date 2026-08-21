// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kvartz",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KvartzUI", targets: ["KvartzUI"]),
        .executable(name: "Kvartz", targets: ["Kvartz"])
    ],
    targets: [
        .target(
            name: "KvartzUI",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Kvartz",
            dependencies: ["KvartzUI"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "KvartzTests",
            dependencies: ["Kvartz"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
