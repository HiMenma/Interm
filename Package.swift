// swift-tools-version:5.10
//
//  Package.swift
//  Interm —— 在 Finder 中一键打开终端
//
//  IntermCore 与 UI 无关：URL 协议、路径归一、终端预设、启动器、偏好、菜单规则。
//  宿主 App 与 FinderSync 扩展在后续提交里接入。
//

import PackageDescription

let package = Package(
    name: "Interm",
    platforms: [
        .macOS(.v14)
    ],
    products: [],
    targets: [
        .target(
            name: "IntermCore",
            path: "Sources/IntermCore"
        ),
        .testTarget(
            name: "IntermCoreTests",
            dependencies: ["IntermCore"],
            path: "Tests/IntermCoreTests"
        )
    ]
)
