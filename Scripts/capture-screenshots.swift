#!/usr/bin/env swift
//
//  capture-screenshots.swift
//  Interm
//
//  按 bundle id 找到窗口 → `screencapture -l` 抓窗口 → 合成带阴影的展示图。
//  需要「屏幕录制」权限；没有权限时 screencapture 会失败，这里会给出提示并退出 2。
//
//  由 Scripts/capture-screenshots.sh 负责准备场景（Finder / 终端 / 设置窗口）。

import AppKit
import CoreGraphics
import Foundation

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputDir = repoRoot.appendingPathComponent("docs/images", isDirectory: true)
let workDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("interm-shots", isDirectory: true)

try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

// MARK: - 找窗口

struct WindowInfo {
    let number: Int
    let bundleID: String
    let size: CGSize
}

func onScreenWindows() -> [WindowInfo] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    var result: [WindowInfo] = []
    for window in list {
        guard (window[kCGWindowLayer as String] as? Int) == 0 else { continue }
        guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
              let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
              let number = window[kCGWindowNumber as String] as? Int,
              let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
              let width = bounds["Width"], let height = bounds["Height"],
              width >= 300, height >= 200
        else { continue }
        result.append(WindowInfo(number: number, bundleID: bundleID, size: CGSize(width: width, height: height)))
    }
    return result
}

func pickWindow(bundleID: String, newest: Bool) -> WindowInfo? {
    let matches = onScreenWindows().filter { $0.bundleID == bundleID }
    if newest {
        return matches.max { $0.number < $1.number }
    }
    return matches.max { ($0.size.width * $0.size.height) < ($1.size.width * $1.size.height) }
}

func capture(_ window: WindowInfo, named name: String) -> NSImage? {
    let path = workDir.appendingPathComponent("\(name).png")
    try? FileManager.default.removeItem(at: path)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-o", "-l", String(window.number), path.path]
    process.standardError = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0,
          let image = NSImage(contentsOf: path),
          image.size.width > 0
    else { return nil }
    return image
}

// MARK: - 合成

func rounded(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

/// 把一张窗口截图按给定矩形画到画布上，带阴影和描边。
func drawWindow(_ image: NSImage, in rect: NSRect, radius: CGFloat = 12) {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.22)
    shadow.shadowBlurRadius = 26
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.white.setFill()
    rounded(rect, radius: radius).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    rounded(rect, radius: radius).addClip()
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    NSColor(white: 0, alpha: 0.10).setStroke()
    let border = rounded(rect.insetBy(dx: 0.5, dy: 0.5), radius: radius)
    border.lineWidth = 1
    border.stroke()
}

func canvas(size: NSSize, draw: () -> Void) -> NSBitmapImageRep {
    let scale: CGFloat = 2
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width * scale),
        pixelsHigh: Int(size.height * scale),
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
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// 从窗口截图里裁出顶部一条（Finder 工具栏），避免把侧边栏里的个人收藏拍进去。
func cropTop(_ image: NSImage, points: CGFloat) -> NSImage? {
    guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
    let scale = CGFloat(cg.width) / image.size.width
    let height = Int(points * scale)
    guard height > 0, height <= cg.height else { return nil }
    // CGImage 的坐标原点在左上角，正好对应窗口顶部
    guard let cropped = cg.cropping(to: CGRect(x: 0, y: 0, width: cg.width, height: height)) else { return nil }
    return NSImage(cgImage: cropped, size: NSSize(width: CGFloat(cg.width) / scale, height: points))
}

func backdrop(_ size: NSSize) {
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.98, green: 0.98, blue: 0.99, alpha: 1),
        NSColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 1)
    ])
    gradient?.draw(in: NSRect(origin: .zero, size: size), angle: -90)
}

func write(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IntermScreenshots", code: 1)
    }
    try data.write(to: url)
}

// MARK: - 主流程

let composeOnly = CommandLine.arguments.contains("--compose-only")

print(composeOnly ? "只合成（复用上次抓到的窗口图）…" : "查找窗口…")
let finder = pickWindow(bundleID: "com.apple.finder", newest: false)
let terminal = pickWindow(bundleID: "com.apple.Terminal", newest: true)
let settings = pickWindow(bundleID: "com.menmapro.Interm", newest: false)

var shots: [String: NSImage] = [:]

if composeOnly {
    for name in ["finder", "terminal", "settings"] {
        if let image = NSImage(contentsOf: workDir.appendingPathComponent("\(name).png")) {
            shots[name] = image
        }
    }
}

for (name, window) in composeOnly ? [] : [("finder", finder), ("terminal", terminal), ("settings", settings)] {
    guard let window else {
        print("找不到窗口：\(name)（对应 app 没开？）")
        continue
    }
    if let image = capture(window, named: name) {
        shots[name] = image
        print("  抓到 \(name)：\(window.number) \(Int(window.size.width))x\(Int(window.size.height))")
    } else {
        print("  抓取失败：\(name)（多半是没有「屏幕录制」权限）")
    }
}

guard !shots.isEmpty else {
    FileHandle.standardError.write(Data("""
    没有任何窗口抓成功。请到 系统设置 › 隐私与安全性 › 屏幕录制 里给当前终端/DSH 授权后重试，
    或者手动 ⌘⇧4 截图并放进 docs/images/。

    """.utf8))
    exit(2)
}

// 图 1：Finder 工具栏条 + 终端
if let finderImage = shots["finder"], let terminalImage = shots["terminal"] {
    let size = NSSize(width: 1080, height: 560)
    let strip = cropTop(finderImage, points: 66)
    let rep = canvas(size: size) {
        backdrop(size)

        if let strip {
            let stripWidth: CGFloat = 880
            let stripRect = NSRect(
                x: (size.width - stripWidth) / 2,
                y: size.height - stripWidth * strip.size.height / strip.size.width - 34,
                width: stripWidth,
                height: stripWidth * strip.size.height / strip.size.width
            )
            drawWindow(strip, in: stripRect, radius: 10)
        }

        let terminalWidth: CGFloat = 560
        let terminalRect = NSRect(
            x: (size.width - terminalWidth) / 2,
            y: 44,
            width: terminalWidth,
            height: terminalWidth * terminalImage.size.height / terminalImage.size.width
        )
        drawWindow(terminalImage, in: terminalRect, radius: 10)
    }
    try write(rep, to: outputDir.appendingPathComponent("screenshot-toolbar-terminal.png"))
    print("写出 screenshot-toolbar-terminal.png")
}

// 图 2：设置窗口
if let settingsImage = shots["settings"] {
    let size = NSSize(width: 900, height: 700)
    let rep = canvas(size: size) {
        backdrop(size)
        // 按画布留白等比缩放，别把窗口裁掉
        let maxWidth = size.width - 160
        let maxHeight = size.height - 120
        let scale = min(maxWidth / settingsImage.size.width, maxHeight / settingsImage.size.height)
        let width = settingsImage.size.width * scale
        let height = settingsImage.size.height * scale
        let rect = NSRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
        drawWindow(settingsImage, in: rect, radius: 14)
    }
    try write(rep, to: outputDir.appendingPathComponent("screenshot-settings.png"))
    print("写出 screenshot-settings.png")
}
