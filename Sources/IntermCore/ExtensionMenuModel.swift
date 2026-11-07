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
    public let title: String
    public let directory: URL

    public init(title: String, directory: URL) {
        self.title = title
        self.directory = directory
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
            return [ExtensionMenuEntry(title: currentFolderTitle, directory: directory)]

        case .contextualForItems:
            let directory: URL
            if selectedURLs.count == 1, let selected = selectedURLs.first {
                directory = isDirectory(selected) ? selected : selected.deletingLastPathComponent()
            } else {
                directory = targetedURL ?? fallbackDirectory
            }
            return [ExtensionMenuEntry(title: selectedItemTitle, directory: directory)]
        }
    }

    public static var currentFolderTitle: String {
        L10n.tr("在终端中打开当前文件夹", "Open Current Folder in Terminal")
    }

    public static var selectedItemTitle: String {
        L10n.tr("在终端中打开", "Open in Terminal")
    }
}
