import AppKit
import Foundation
import IntermCore

@MainActor
protocol StatusItemActionTarget: AnyObject {
    func statusOpenFinderFrontWindow()
    func statusShowSettings()
    func statusOpenExtensionSettings()
    func statusCopyToolbarHint()
    func statusQuit()
}

/// 菜单栏图标。App 是 `LSUIElement`，没有 Dock 图标，这是它的常驻入口。
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private weak var target: StatusItemActionTarget?

    init(target: StatusItemActionTarget) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.target = target
        super.init()
        configure()
    }

    private func configure() {
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "terminal", accessibilityDescription: IntermIdentity.displayName)
            image?.isTemplate = true
            button.image = image
            button.toolTip = L10n.tr("Interm —— 在当前目录打开终端", "Interm — open a terminal in the current folder")
        }

        let menu = NSMenu()
        menu.addItem(menuItem(L10n.tr("在终端中打开当前目录", "Open Current Folder in Terminal"), #selector(openHere)))
        menu.addItem(.separator())
        menu.addItem(menuItem(L10n.tr("设置…", "Settings…"), #selector(showSettings), key: ","))
        menu.addItem(menuItem(L10n.tr("启用 Finder 扩展…", "Enable Finder Extension…"), #selector(openExtensionSettings)))
        menu.addItem(menuItem(L10n.tr("复制「拖到工具栏」说明", "Copy “Drag to Toolbar” Instructions"), #selector(copyHint)))
        menu.addItem(.separator())
        menu.addItem(menuItem(L10n.tr("退出 Interm", "Quit Interm"), #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openHere() { target?.statusOpenFinderFrontWindow() }
    @objc private func showSettings() { target?.statusShowSettings() }
    @objc private func openExtensionSettings() { target?.statusOpenExtensionSettings() }
    @objc private func copyHint() { target?.statusCopyToolbarHint() }
    @objc private func quit() { target?.statusQuit() }
}

/// 「把图标拖进 Finder 工具栏」的操作说明，多处复用。
enum ToolbarHint {
    static var text: String {
        L10n.tr(
            """
            把 Interm 放到 Finder 工具栏（两种方法任选）：
            1. 打开「应用程序」文件夹，按住 ⌘ 把 Interm.app 拖到 Finder 窗口的工具栏上，松手即可；
            2. 或在 Finder 里右键工具栏空白处 → 自定义工具栏…，把 Interm 拖进去。
            之后每单击一次这个图标，就会在「当前 Finder 窗口所在的目录」打开终端。
            """,
            """
            Put Interm into the Finder toolbar:
            1. Open Applications, hold ⌘ and drag Interm.app onto the toolbar of a Finder window.
            2. Or right-click the toolbar → Customize Toolbar… and drag Interm in.
            After that, one click opens a terminal at the folder shown in the front Finder window.
            """
        )
    }

    static func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
