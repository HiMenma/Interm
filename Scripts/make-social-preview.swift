#!/usr/bin/env swift
//
//  make-social-preview.swift
//  Interm
//
//  生成 GitHub 仓库的社交预览图（1280×640，< 1 MB）。
//  GitHub 没有 API 可以上传，只能网页上传：Settings › Social preview。
//
//  用法：swift Scripts/make-social-preview.swift

import AppKit
import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = repoRoot.appendingPathComponent("docs/images/social-preview.png")
let iconPath = repoRoot.appendingPathComponent("Bundle/Interm.iconset/icon_256x256@2x.png")

let size = NSSize(width: 1280, height: 640)
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
rep.size = size

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

// 背景：与图标同一套深蓝渐变
let background = NSGradient(colors: [
    NSColor(srgbRed: 0.10, green: 0.14, blue: 0.23, alpha: 1),
    NSColor(srgbRed: 0.05, green: 0.07, blue: 0.13, alpha: 1)
])!
background.draw(in: NSRect(origin: .zero, size: size), angle: -75)

// 右上角一块很淡的薄荷光
let glow = NSGradient(colors: [
    NSColor(srgbRed: 0.36, green: 0.92, blue: 0.62, alpha: 0.16),
    NSColor(srgbRed: 0.36, green: 0.92, blue: 0.62, alpha: 0.0)
])!
glow.draw(in: NSRect(origin: .zero, size: size), relativeCenterPosition: NSPoint(x: 0.55, y: 0.1))

// 图标
if let icon = NSImage(contentsOf: iconPath) {
    let side: CGFloat = 188
    icon.draw(in: NSRect(x: 92, y: 226, width: side, height: side))
}

// 文案
let white = NSColor.white
let dim = NSColor(white: 1, alpha: 0.62)
let mint = NSColor(srgbRed: 0.36, green: 0.92, blue: 0.62, alpha: 1)

func draw(_ text: String, at point: NSPoint, font: NSFont, color: NSColor, tracking: CGFloat = 0) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .kern: tracking
    ]
    (text as NSString).draw(at: point, withAttributes: attributes)
}

draw("Interm", at: NSPoint(x: 322, y: 352), font: .systemFont(ofSize: 84, weight: .bold), color: white, tracking: -1.5)
draw("Open a terminal in the current Finder folder.", at: NSPoint(x: 328, y: 300),
     font: .systemFont(ofSize: 30, weight: .regular), color: dim)
draw("macOS 14+  ·  native Swift  ·  FinderSync  ·  MIT", at: NSPoint(x: 328, y: 232),
     font: .monospacedSystemFont(ofSize: 19, weight: .regular), color: mint, tracking: 0.4)

// 左下角：一小段工具栏提示
draw("⌘-drag into the Finder toolbar, then one click.", at: NSPoint(x: 96, y: 120),
     font: .systemFont(ofSize: 22, weight: .medium), color: NSColor(white: 1, alpha: 0.82))

NSGraphicsContext.restoreGraphicsState()

try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
guard let data = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("PNG 编码失败\n".utf8))
    exit(1)
}
try data.write(to: output)

let kb = Double(data.count) / 1024
print("写出 \(output.path)（\(Int(size.width))×\(Int(size.height))，\(String(format: "%.0f", kb)) KB）")
if data.count > 1_000_000 {
    print("警告：超过 1 MB，GitHub 可能拒绝")
}
