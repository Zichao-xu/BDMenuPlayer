// swift-tools-version: 6.2

import PackageDescription
import Foundation

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let vlcRoot = packageRoot + "/Dependencies/VLC"

let package = Package(
    name: "BDMenuPlayer",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "BDMenuPlayer", targets: ["BDMenuPlayer"])
    ],
    targets: [
        .target(
            name: "CBlurayBridge",
            path: "Sources/CBlurayBridge",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-I/opt/homebrew/opt/libbluray/include"])
            ],
            linkerSettings: [
                .unsafeFlags(["-L/opt/homebrew/opt/libbluray/lib"]),
                .linkedLibrary("bluray")
            ]
        ),
        .target(
            name: "CVLCBridge",
            path: "Sources/CVLCBridge",
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-I\(vlcRoot)/include"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L\(vlcRoot)/lib",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Resources/VLC/lib",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "\(vlcRoot)/lib"
                ]),
                .linkedLibrary("vlc")
            ]
        ),
        .executableTarget(
            name: "BDMenuPlayer",
            dependencies: ["CBlurayBridge", "CVLCBridge"],
            path: "Sources/BDMenuPlayer"
        ),
        .testTarget(
            name: "BDMenuPlayerTests",
            dependencies: ["BDMenuPlayer", "CBlurayBridge", "CVLCBridge"],
            path: "Tests/BDMenuPlayerTests"
        )
    ]
)
