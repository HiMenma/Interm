import Foundation

/// Finder 要求的菜单类型，取值与 `FIMenuKind` 一致。
///
/// 这里刻意不 `import FinderSync`，好让菜单规则能在单元测试里跑。
public enum FinderMenuKind: Int, Sendable {
    case contextualForItems = 0
    case contextualForContainer = 1
    case contextualForSidebar = 2
    case toolbar = 3
}

public struct ExtensionMenuEntry: Equatable, Sendable {
    /// 菜单项在本次菜单里的序号，写进 `NSMenuItem.tag`。
    ///
    /// Finder 会把扩展返回的菜单序列化后再回调动作，`representedObject` 可能在
    /// 这一趟里丢掉（实测：动作被调用时 `representedObject` 为 nil），
    /// 而 `tag` 是 NSMenuItem 自己的整型属性，能活下来。
    public let tag: Int
    public let title: String
    public let directory: URL

    public init(tag: Int, title: String, directory: URL) {
        self.tag = tag
        self.title = title
        self.directory = directory
    }
}

/// 菜单动作最终解析出来的目录，以及它是从哪条线索拿到的（用于日志排查）。
public struct ExtensionMenuResolution: Equatable, Sendable {
    public let directory: URL
    public let source: String

    public init(directory: URL, source: String) {
        self.directory = directory
        self.source = source
    }
}

/// FinderSync 菜单的纯逻辑部分。
///
/// 扩展进程（沙箱）里能拿到的只有 `targetedURL()` 和 `selectedItemURLs()`，
/// 且这两个值在工具栏点击时可能是 `nil`；这里的规则把它们折算成确定的菜单项，
/// 剩下的部分（创建 NSMenu）留给扩展。
public enum ExtensionMenuModel {
    public static func entries(
        kind: FinderMenuKind,
        targetedURL: URL?,
        selectedURLs: [URL],
        isDirectory: (URL) -> Bool,
        fallbackDirectory: URL
    ) -> [ExtensionMenuEntry] {
        switch kind {
        case .contextualForSidebar:
            return []

        case .contextualForContainer, .toolbar:
            let directory = targetedURL ?? fallbackDirectory
            return [ExtensionMenuEntry(tag: 0, title: currentFolderTitle, directory: directory)]

        case .contextualForItems:
            let directory: URL
            if selectedURLs.count == 1, let selected = selectedURLs.first {
                directory = isDirectory(selected) ? selected : selected.deletingLastPathComponent()
            } else {
                directory = targetedURL ?? fallbackDirectory
            }
            return [ExtensionMenuEntry(tag: 0, title: selectedItemTitle, directory: directory)]
        }
    }

    /// 菜单项被点击时，按可靠性从高到低找目录。
    ///
    /// 顺序：本次菜单的缓存 → `representedObject` → `targetedURL()` → 选中项 → 桌面。
    /// `targetedURL()` 在「菜单动作」里是官方支持的用法，作为兜底足够可靠。
    public static func resolve(
        tag: Int,
        cache: [Int: URL],
        representedObject: Any?,
        targetedURL: URL?,
        selectedURLs: [URL],
        isDirectory: (URL) -> Bool,
        fallbackDirectory: URL
    ) -> ExtensionMenuResolution {
        // 若构建菜单时就没拿到 targetedURL（工具栏按钮偶尔如此），缓存里存的是兜底目录；
        // 这种情况宁可再问一次 targetedURL()，它比「上次的兜底」更可能指向用户眼前的文件夹。
        if let cached = cache[tag], cached != fallbackDirectory {
            return ExtensionMenuResolution(directory: cached, source: "cache")
        }
        if let path = representedObject as? String, !path.isEmpty {
            return ExtensionMenuResolution(directory: URL(fileURLWithPath: path, isDirectory: true), source: "representedObject")
        }
        if let url = representedObject as? URL {
            return ExtensionMenuResolution(directory: url, source: "representedObject")
        }
        if let targetedURL {
            return ExtensionMenuResolution(directory: targetedURL, source: "targeted")
        }
        if let first = selectedURLs.first {
            let directory = isDirectory(first) ? first : first.deletingLastPathComponent()
            return ExtensionMenuResolution(directory: directory, source: "selection")
        }
        return ExtensionMenuResolution(directory: fallbackDirectory, source: "fallback")
    }

    public static var currentFolderTitle: String {
        L10n.tr("在终端中打开当前文件夹", "Open Current Folder in Terminal")
    }

    public static var selectedItemTitle: String {
        L10n.tr("在终端中打开", "Open in Terminal")
    }
}
