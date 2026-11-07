import AppKit
import Foundation
import IntermCore

/// 报警窗口。LSUIElement App 默认不激活，弹窗前必须主动抢焦点，否则窗口会躲在后面。
@MainActor
enum Dialogs {
    static func showError(title: String, message: String, settingsHint: Bool = false, onOpenSettings: (() -> Void)? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L10n.tr("好", "OK"))
        if settingsHint {
            alert.addButton(withTitle: L10n.tr("打开设置…", "Open Settings…"))
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                onOpenSettings?()
            }
        } else {
            alert.runModal()
        }
    }

    static func showAutomationDenied() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("需要「自动化」权限", "Automation permission required")
        alert.informativeText = L10n.tr(
            "Interm 需要读取访达当前窗口的目录，才能在这个目录打开终端。\n请到「系统设置 › 隐私与安全性 › 自动化」里允许 Interm 控制「访达」。\n\n本次会退回到桌面目录。",
            "Interm needs to read the front Finder window to know which folder to open.\nAllow Interm to control Finder in System Settings › Privacy & Security › Automation.\n\nFalling back to the Desktop this time."
        )
        alert.addButton(withTitle: L10n.tr("打开系统设置", "Open System Settings"))
        alert.addButton(withTitle: L10n.tr("好", "OK"))
        if alert.runModal() == .alertFirstButtonReturn, let url = FinderDirectoryProbe.automationSettingsURL {
            NSWorkspace.shared.open(url)
        }
    }
}
