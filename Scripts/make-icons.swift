#!/usr/bin/env swift
//
//  make-icons.swift
//  Interm
//
//  生成两样东西：
//    Bundle/Interm.icns                  App 图标（由 iconset 经 iconutil 打包）
//    Bundle/IntermToolbarTemplate.png    Finder 工具栏用的模板图（单色、透明底）
//
//  纯 CoreGraphics 绘制，不依赖任何外部素材，保证仓库里不出现二进制源文件。

import AppKit
import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let bundleDir = repoRoot.appendingPathComponent("Bundle", isDirectory: true)
let iconsetDir = bundleDir.appendingPathComponent("Interm.iconset", isDirectory: true)

// MARK: - 绘制基础

func makeBitmap(size: Int) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("cannot allocate bitmap of size \(size)")
    }
    rep.size = NSSize(width: size, height: size)
    return rep
}

func render(size: Int, draw: (CGContext, CGFloat) -> Void) -> NSBitmapImageRep {
    let rep = makeBitmap(size: size)
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fatalError("cannot create graphics context")
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.setShouldAntialias(true)
    context.cgContext.interpolationQuality = .high
    draw(context.cgContext, CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IntermIcons", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
    }
    try data.write(to: url)
}

/// Lucide `terminal` 图标的矢量实现。
///
/// 原始素材：docs/icons/svg/lucide-terminal.svg（lucide-static，ISC 许可）
///   viewBox 24×24，stroke-width 2，圆头端点、圆角连接，无填充：
///     M12 19h8          下划线
///     m4 17 6-6-6-6     提示符箭头（4,17 → 10,11 → 4,5）
///
/// 这里按「图形宽度」等比缩放并居中，保证不同尺寸下笔画比例与 Lucide 一致，
/// 因此 16px 的小图标也能保持清晰，不需要单独准备小尺寸位图。
func drawTerminalGlyph(in cg: CGContext, center: CGPoint, glyphWidth: CGFloat, color: CGColor, strokeUnits: CGFloat = 2) {
    let unit = glyphWidth / 16          // 图形在 viewBox 里宽 16 个单位（x: 4…20）
    let half = 12 * unit                // viewBox 中心到边缘

    // SVG 的 y 轴朝下，CoreGraphics 朝上，这里顺手翻转
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: center.x - half + x * unit, y: center.y - half + (24 - y) * unit)
    }

    cg.saveGState()
    cg.setStrokeColor(color)
    cg.setLineWidth(strokeUnits * unit)
    cg.setLineCap(.round)
    cg.setLineJoin(.round)

    let chevron = CGMutablePath()
    chevron.move(to: point(4, 17))
    chevron.addLine(to: point(10, 11))
    chevron.addLine(to: point(4, 5))
    cg.addPath(chevron)
    cg.strokePath()

    let underscore = CGMutablePath()
    underscore.move(to: point(12, 19))
    underscore.addLine(to: point(20, 19))
    cg.addPath(underscore)
    cg.strokePath()

    cg.restoreGState()
}

func squircleIcon(_ cg: CGContext, size: CGFloat, insetFraction: CGFloat, glyphFraction: CGFloat, strokeUnits: CGFloat = 2) {
    let inset = size * insetFraction
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.225
    let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    cg.saveGState()
    cg.addPath(shape)
    cg.clip()

    let colors = [
        CGColor(red: 0.15, green: 0.20, blue: 0.32, alpha: 1.0),
        CGColor(red: 0.05, green: 0.07, blue: 0.13, alpha: 1.0)
    ] as CFArray
    if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors,
        locations: [0.0, 1.0]
    ) {
        cg.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }

    // 顶部一层很淡的光泽，让图标不至于死板
    let highlight = CGRect(x: rect.minX, y: rect.maxY - rect.height * 0.45, width: rect.width, height: rect.height * 0.45)
    if let gloss = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.10),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)
        ] as CFArray,
        locations: [0.0, 1.0]
    ) {
        cg.drawLinearGradient(
            gloss,
            start: CGPoint(x: highlight.midX, y: highlight.maxY),
            end: CGPoint(x: highlight.midX, y: highlight.minY),
            options: []
        )
    }
    cg.restoreGState()

    cg.addPath(shape)
    cg.setStrokeColor(CGColor(gray: 1, alpha: 0.14))
    cg.setLineWidth(max(1, size * 0.006))
    cg.strokePath()

    drawTerminalGlyph(
        in: cg,
        center: CGPoint(x: rect.midX, y: rect.midY),
        glyphWidth: size * glyphFraction,
        color: CGColor(red: 0.36, green: 0.92, blue: 0.62, alpha: 1.0),
        strokeUnits: strokeUnits
    )
}

func toolbarTemplate(_ cg: CGContext, size: CGFloat) {
    cg.clear(CGRect(x: 0, y: 0, width: size, height: size))
    drawTerminalGlyph(
        in: cg,
        center: CGPoint(x: size / 2, y: size / 2),
        glyphWidth: size * 0.74,
        color: CGColor(gray: 0, alpha: 1)
    )
}

// MARK: - 输出

try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024)
]

for variant in variants {
    let rep = render(size: variant.pixels) { cg, size in
        squircleIcon(cg, size: size, insetFraction: 0.055, glyphFraction: 0.52)
    }
    try writePNG(rep, to: iconsetDir.appendingPathComponent("\(variant.name).png"))
}

// Finder 工具栏用：彩色版（和 App 图标同款，但留白更小、字形更大，18pt 下才看得清）
for (name, pixels, inset, glyph, stroke) in [
    // 18pt 下字形要占满、笔画要比 Lucide 原始 2 更粗，否则缩到工具栏里会糊成一团
    ("IntermToolbarIcon", 36, 0.01, 0.70, 2.8),
    ("IntermToolbarIcon@2x", 72, 0.01, 0.70, 2.8)
] {
    let rep = render(size: pixels) { cg, size in
        squircleIcon(cg, size: size, insetFraction: inset, glyphFraction: glyph, strokeUnits: stroke)
    }
    try writePNG(rep, to: bundleDir.appendingPathComponent("\(name).png"))
}

// 单色模板版留着备用：某些系统外观下模板图更协调
let toolbar = render(size: 36, draw: toolbarTemplate)
try writePNG(toolbar, to: bundleDir.appendingPathComponent("IntermToolbarTemplate.png"))

// iconutil 只认 iconset 目录，直接调系统工具最省事
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "-c", "icns",
    iconsetDir.path,
    "-o", bundleDir.appendingPathComponent("Interm.icns").path
]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed with status \(iconutil.terminationStatus)\n".utf8))
    exit(1)
}

print("icons written to \(bundleDir.path)")
