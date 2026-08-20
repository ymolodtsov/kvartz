// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kvartz",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Kvartz", targets: ["Kvartz"])
    ],
    targets: [
        .executableTarget(
            name: "Kvartz",
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
