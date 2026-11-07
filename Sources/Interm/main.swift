import AppKit
import IntermCore

// 命令行模式要先于 NSApplication 处理：
// `Interm --selftest`、`Interm --open-at /tmp` 这类调用不应该弹出任何 UI。
if let exitCode = CommandLineMode.runIfRequested(arguments: CommandLine.arguments) {
    exit(exitCode)
}

@MainActor
func runApplication() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}

// main.swift 的顶层代码本身不是 main actor 隔离的，但此刻确实在主线程上跑。
MainActor.assumeIsolated {
    runApplication()
}
