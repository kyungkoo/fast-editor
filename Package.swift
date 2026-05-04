// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FastEditor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FastEditor", targets: ["FastEditorApp"])
    ],
    targets: [
        .executableTarget(
            name: "FastEditorApp",
            linkerSettings: [
                .unsafeFlags([
                    "-L", "target/debug",
                    "-leditor_core",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "target/debug"
                ])
            ]
        )
    ]
)

