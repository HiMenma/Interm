// swift-tools-version:5.10
//
//  Package.swift
//  Interm —— 在 Finder 中一键打开终端
//
//  三个 target 的分工：
//    IntermCore   —— 与 UI 无关的逻辑（URL 协议、路径归一、终端预设、启动器、偏好），可单测
//    Interm       —— 宿主 App（AppKit + SwiftUI），不沙箱，负责 AppleScript 探测与真正启动终端
//    IntermFinder —— FinderSync 扩展（沙箱），只负责把路径拼成 interm:// URL 交给宿主
//

import PackageDescription

let package = Package(
    name: "Interm",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Interm", targets: ["Interm"]),
        .executable(name: "IntermFinder", targets: ["IntermFinder"])
    ],
    targets: [
        .target(
            name: "IntermCore",
            path: "Sources/IntermCore"
        ),
        .executableTarget(
            name: "Interm",
            dependencies: ["IntermCore"],
            path: "Sources/Interm"
        ),
        // 关键：FinderSync 扩展的入口点必须是 Foundation 的 NSExtensionMain，
        // 与 Xcode 的 LD_ENTRY_POINT = _NSExtensionMain 等价。
        // 若改用 Swift 的 main() 去调 NSExtensionMain，ExtensionFoundation 会在
        // EXExtensionMain 里直接 brk（已实测），所以这里必须用 link flag 指定入口。
        .executableTarget(
            name: "IntermFinder",
            dependencies: ["IntermCore"],
            path: "Sources/IntermFinder",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])
            ]
        ),
        .testTarget(
            name: "IntermCoreTests",
            dependencies: ["IntermCore"],
            path: "Tests/IntermCoreTests"
        )
    ]
)
