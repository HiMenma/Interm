import Foundation

/// 打开终端的方式。
public enum LaunchStrategy: Equatable, Sendable {
    /// 把文件夹当作「文档」交给终端 App（Terminal / iTerm2 / Warp 都支持），
    /// 由 LaunchServices 拉起，不需要 AppleScript，也不需要 shell。
    case openFolderDocument
    /// 直接运行终端自带的命令行工具并传参（kitty / WezTerm / Alacritty）。
    /// 参数里的 `{dir}` 会被替换为实际路径。
    case arguments([String])
    /// 由用户在设置里填写 App 路径与参数模板。
    case custom
}

/// 一个终端 App 的画像。
public struct TerminalPreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let bundleIdentifier: String
    /// 可能的应用安装位置，按优先级排列。
    public let applicationPaths: [String]
    /// 需要直接执行时，App 包内 `Contents/MacOS/` 下的可执行文件名。
    public let cliExecutableName: String?
    public let strategy: LaunchStrategy
    /// 是否在本机实测过（未实测的预设会标注「尽力支持」）。
    public let verified: Bool

    public init(
        id: String,
        displayName: String,
        bundleIdentifier: String,
        applicationPaths: [String],
        cliExecutableName: String? = nil,
        strategy: LaunchStrategy,
        verified: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.applicationPaths = applicationPaths
        self.cliExecutableName = cliExecutableName
        self.strategy = strategy
        self.verified = verified
    }
}

/// 内置的终端预设。
///
/// 说明：只有 `verified == true` 的预设在本机（macOS 27.2 + Terminal.app）实测通过；
/// 其它预设按各自官方文档的命令行参数实现，装了对应 App 才会出现在设置里。
public enum TerminalCatalog {
    public static let terminal = TerminalPreset(
        id: "terminal",
        displayName: "Terminal",
        bundleIdentifier: "com.apple.Terminal",
        applicationPaths: [
            "/System/Applications/Utilities/Terminal.app",
            "/Applications/Utilities/Terminal.app"
        ],
        strategy: .openFolderDocument,
        verified: true
    )

    public static let iterm2 = TerminalPreset(
        id: "iterm2",
        displayName: "iTerm2",
        bundleIdentifier: "com.googlecode.iterm2",
        applicationPaths: ["/Applications/iTerm.app"],
        strategy: .openFolderDocument
    )

    public static let warp = TerminalPreset(
        id: "warp",
        displayName: "Warp",
        bundleIdentifier: "dev.warp.Warp-Stable",
        applicationPaths: ["/Applications/Warp.app"],
        strategy: .openFolderDocument
    )

    public static let kitty = TerminalPreset(
        id: "kitty",
        displayName: "kitty",
        bundleIdentifier: "net.kovidgoyal.kitty",
        applicationPaths: ["/Applications/kitty.app"],
        cliExecutableName: "kitty",
        strategy: .arguments(["--directory", "{dir}"])
    )

    public static let wezterm = TerminalPreset(
        id: "wezterm",
        displayName: "WezTerm",
        bundleIdentifier: "com.github.wez.wezterm",
        applicationPaths: ["/Applications/WezTerm.app"],
        cliExecutableName: "wezterm",
        strategy: .arguments(["start", "--cwd", "{dir}"])
    )

    public static let alacritty = TerminalPreset(
        id: "alacritty",
        displayName: "Alacritty",
        bundleIdentifier: "org.alacritty",
        applicationPaths: ["/Applications/Alacritty.app"],
        cliExecutableName: "alacritty",
        strategy: .arguments(["--working-directory", "{dir}"])
    )

    public static let custom = TerminalPreset(
        id: "custom",
        displayName: L10n.tr("自定义…", "Custom…"),
        bundleIdentifier: "",
        applicationPaths: [],
        strategy: .custom
    )

    public static let all: [TerminalPreset] = [
        terminal, iterm2, warp, kitty, wezterm, alacritty, custom
    ]

    public static let defaultID = terminal.id

    public static func preset(withID id: String) -> TerminalPreset? {
        all.first { $0.id == id }
    }

    /// 解析某个预设实际可用的应用路径（第一个存在的）。
    public static func applicationURL(for preset: TerminalPreset, probe: FileSystemProbing = DefaultFileSystemProbe()) -> URL? {
        for path in preset.applicationPaths {
            var isDirectory: ObjCBool = false
            if probe.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return nil
    }

    /// 本机已安装的预设（自定义项始终可用）。
    public static func installed(probe: FileSystemProbing = DefaultFileSystemProbe()) -> [TerminalPreset] {
        all.filter { preset in
            guard preset.strategy != .custom else { return true }
            return applicationURL(for: preset, probe: probe) != nil
        }
    }
}
