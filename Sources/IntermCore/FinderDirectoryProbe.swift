import AppKit
import Foundation

/// AppleScript 执行结果。
public enum AppleScriptFailure: Error, Equatable {
    /// 脚本执行失败，附带 `NSAppleScript.errorNumber` 与描述。
    case executionFailed(code: Int, message: String)
}

public protocol AppleScriptRunning {
    func run(_ source: String) -> Result<String, AppleScriptFailure>
}

/// 进程内执行 AppleScript。
///
/// 必须在主线程调用；首次执行会弹出「想控制访达」的自动化授权。
public struct NSAppleScriptRunner: AppleScriptRunning {
    public init() {}

    public func run(_ source: String) -> Result<String, AppleScriptFailure> {
        guard let script = NSAppleScript(source: source) else {
            return .failure(.executionFailed(code: 0, message: "NSAppleScript init failed"))
        }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "AppleScript error"
            return .failure(.executionFailed(code: code, message: message))
        }
        return .success(descriptor.stringValue ?? "")
    }
}

public enum FinderProbeError: Error, Equatable, CustomStringConvertible {
    /// 用户拒绝了自动化授权（-1743）。
    case automationDenied
    /// 没有打开的 Finder 窗口，或窗口停在「最近使用」这类虚拟位置。
    case noWindow
    case scriptFailed(String)

    public var description: String {
        switch self {
        case .automationDenied:
            return L10n.tr("没有自动化权限，无法读取访达当前窗口",
                           "No automation permission to read the front Finder window")
        case .noWindow:
            return L10n.tr("访达没有打开任何窗口", "Finder has no open window")
        case .scriptFailed(let message):
            return L10n.tr("读取访达窗口失败：\(message)", "Failed to read the Finder window: \(message)")
        }
    }
}

/// 问访达要「当前窗口所在目录」。
///
/// FinderSync 扩展在沙箱里拿不到这个信息，只有宿主 App（非沙箱 + 自动化授权）
/// 才能通过 AppleScript 问出来——这也是「拖到工具栏的图标」路线唯一需要的权限。
public struct FinderDirectoryProbe {
    /// AppleScript 错误码：没有自动化权限。
    static let notAuthorizedCode = -1743
    /// AppleScript 错误码：对象不存在（没有窗口、窗口没有 target）。
    static let objectNotFoundCode = -1728
    /// AppleScript 错误码：目标进程未运行。
    static let appNotRunningCode = -600

    static let script = """
    tell application "Finder"
        if (count of Finder windows) is 0 then return ""
        try
            return POSIX path of (target of front Finder window as alias)
        on error
            return ""
        end try
    end tell
    """

    private let runner: AppleScriptRunning
    private let attempts: Int
    private let retryDelay: TimeInterval
    private let sleep: (TimeInterval) -> Void

    public init(
        runner: AppleScriptRunning = NSAppleScriptRunner(),
        attempts: Int = 3,
        retryDelay: TimeInterval = 0.15,
        sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.runner = runner
        self.attempts = max(1, attempts)
        self.retryDelay = retryDelay
        self.sleep = sleep
    }

    public func frontWindowDirectory() -> Result<URL, FinderProbeError> {
        var lastFailure: FinderProbeError = .noWindow

        for attempt in 1...attempts {
            switch runner.run(Self.script) {
            case .success(let path):
                let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return .success(URL(fileURLWithPath: trimmed, isDirectory: true))
                }
                lastFailure = .noWindow
            case .failure(let failure):
                guard case .executionFailed(let code, let message) = failure else {
                    lastFailure = .scriptFailed("unknown")
                    continue
                }
                switch code {
                case Self.notAuthorizedCode:
                    // 权限问题重试没有意义，直接返回。
                    return .failure(.automationDenied)
                case Self.objectNotFoundCode, Self.appNotRunningCode:
                    lastFailure = .noWindow
                default:
                    lastFailure = .scriptFailed("\(message) (\(code))")
                }
            }

            if attempt < attempts {
                sleep(retryDelay)
            }
        }

        return .failure(lastFailure)
    }

    /// 拿不到访达窗口时的兜底目录：桌面（存在的话），否则用户主目录。
    public static func fallbackDirectory(fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> URL {
        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
        if fileExists(desktop.path) { return desktop }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// 打开「隐私与安全性 › 自动化」设置的深链。
    public static let automationSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
    )
}
