// swift-tools-version:5.10
//
//  Package.swift
//  Interm —— 在 Finder 中一键打开终端
//
//  目前的分工：
//    IntermCore —— 与 UI 无关的逻辑（URL 协议、路径归一、终端预设、启动器、偏好），可单测
//    Interm     —— 宿主 App（AppKit + SwiftUI），不沙箱，负责 AppleScript 探测与真正启动终端
//

import PackageDescription

let package = Package(
    name: "Interm",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Interm", targets: ["Interm"])
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
        .testTarget(
            name: "IntermCoreTests",
            dependencies: ["IntermCore"],
            path: "Tests/IntermCoreTests"
        )
    ]
)
