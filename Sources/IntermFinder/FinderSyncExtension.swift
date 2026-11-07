import AppKit
import FinderSync
import Foundation
import IntermCore

/// FinderSync 扩展的 principal class。
///
/// 它跑在沙箱里，因此只做两件事：
/// 1. 把 Finder 的上下文（窗口目录 / 选中项）折算成菜单项；
/// 2. 拼一个 `interm://open?path=...` 交给宿主 App，由沙箱外的宿主去真正启动终端。
///
/// 沙箱内不允许 spawn 子进程，也不该读取用户设置——所有策略都留在宿主。
@objc(IntermFinderExtension)
public final class IntermFinderExtension: FIFinderSync {
    private let toolbarImage: NSImage
    /// 本次菜单里每个 tag 对应的目录。Finder 回调动作时可能丢失 representedObject，
    /// 这份缓存是首选线索，tag 是 NSMenuItem 自带的整型属性，能跨过菜单序列化。
    private var menuDirectoryCache: [Int: URL] = [:]

    public override init() {
        self.toolbarImage = Self.loadToolbarImage()
        super.init()

        // 监视整个文件系统：这样任何本地目录下的窗口都能拿到菜单与工具栏按钮。
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/", isDirectory: true)]
        Log.finder.notice("extension ready, directoryURLs=/, toolbar=\(self.toolbarImage.size.width, privacy: .public)pt")
    }

    // MARK: - Toolbar

    public override var toolbarItemName: String {
        IntermIdentity.displayName
    }

    public override var toolbarItemToolTip: String {
        L10n.tr("在当前目录打开终端", "Open a terminal in the current folder")
    }

    public override var toolbarItemImage: NSImage {
        toolbarImage
    }

    // MARK: - Menus

    public override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let controller = FIFinderSyncController.default()
        let kind = FinderMenuKind(rawValue: Int(menuKind.rawValue)) ?? .contextualForContainer
        let entries = ExtensionMenuModel.entries(
            kind: kind,
            targetedURL: controller.targetedURL(),
            selectedURLs: controller.selectedItemURLs() ?? [],
            isDirectory: Self.isDirectory,
            fallbackDirectory: FinderDirectoryProbe.fallbackDirectory()
        )

        menuDirectoryCache = Dictionary(uniqueKeysWithValues: entries.map { ($0.tag, $0.directory) })
        Log.finder.notice("menu kind=\(menuKind.rawValue) entries=\(entries.count)")

        let menu = NSMenu(title: IntermIdentity.displayName)
        for entry in entries {
            let item = NSMenuItem(title: entry.title, action: #selector(openInTerminal(_:)), keyEquivalent: "")
            item.target = self
            item.tag = entry.tag
            // 双重保险：万一 cache 对不上，字符串形式的路径还有机会活下来。
            item.representedObject = entry.directory.path
            menu.addItem(item)
        }
        return menu
    }

    @objc private func openInTerminal(_ sender: Any?) {
        let controller = FIFinderSyncController.default()
        let item = sender as? NSMenuItem
        let resolution = ExtensionMenuModel.resolve(
            tag: item?.tag ?? -1,
            cache: menuDirectoryCache,
            representedObject: item?.representedObject,
            targetedURL: controller.targetedURL(),
            selectedURLs: controller.selectedItemURLs() ?? [],
            isDirectory: Self.isDirectory,
            fallbackDirectory: FinderDirectoryProbe.fallbackDirectory()
        )

        guard let url = IntermURL.make(from: IntermOpenRequest(directory: resolution.directory)) else {
            Log.finder.error("cannot build interm:// URL")
            return
        }
        let opened = NSWorkspace.shared.open(url)
        Log.finder.notice(
            "handing off \(resolution.directory.path, privacy: .public) via \(resolution.source, privacy: .public) opened=\(opened, privacy: .public)"
        )
    }

    // MARK: - Helpers

    /// 沙箱里判断目录要小心：`fileExists` 可能因为权限返回 false，
    /// 此时退回 `URLResourceValues`，最后才看 URL 是否自带目录尾斜杠。
    static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            return isDirectory.boolValue
        }
        if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]), let value = values.isDirectory {
            return value
        }
        return url.hasDirectoryPath
    }

    static func loadToolbarImage() -> NSImage {
        let bundle = Bundle(for: IntermFinderExtension.self)
        if let url = bundle.url(forResource: "IntermToolbarTemplate", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        let fallback = NSImage(systemSymbolName: "terminal", accessibilityDescription: IntermIdentity.displayName) ?? NSImage()
        fallback.isTemplate = true
        fallback.size = NSSize(width: 18, height: 18)
        return fallback
    }
}
