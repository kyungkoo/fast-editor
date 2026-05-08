// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FastEditor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "FastEditorModels", targets: ["FastEditorModels"]),
        .executable(name: "FastEditor", targets: ["FastEditorApp"])
    ],
    targets: [
        .target(name: "FastEditorTextEditing"),
        .target(
            name: "FastEditorModels",
            dependencies: ["FastEditorTextEditing"]
        ),
        .executableTarget(
            name: "FastEditorApp",
            dependencies: ["FastEditorModels", "FastEditorTextEditing"],
            linkerSettings: [
                .unsafeFlags([
                    "-L", "target/debug",
                    "-leditor_core",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "target/debug"
                ])
            ]
        ),
        .testTarget(
            name: "FastEditorTextEditingTests",
            dependencies: ["FastEditorTextEditing"]
        ),
        .testTarget(
            name: "FastEditorModelsTests",
            dependencies: ["FastEditorModels"]
        ),
        .testTarget(
            name: "FastEditorAppTests",
            dependencies: ["FastEditorApp", "FastEditorModels"]
        )
    ]
)
