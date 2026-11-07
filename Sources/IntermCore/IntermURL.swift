import Foundation

/// 一次「在某目录打开终端」的请求。
public struct IntermOpenRequest: Equatable, Sendable {
    /// 目标目录（绝对路径）。
    public let directory: URL
    /// 指定终端预设 id；nil 表示使用用户在设置里的选择。
    public let terminalID: String?

    public init(directory: URL, terminalID: String? = nil) {
        self.directory = directory
        self.terminalID = terminalID
    }
}

/// `interm://open?path=...&terminal=...` 的生成与解析。
///
/// 这个 URL 有两个用途：
/// 1. FinderSync 扩展（沙箱）把它交给宿主 App，这是沙箱内唯一需要的跨进程通道；
/// 2. 允许用户/脚本从命令行直接调用：`open "interm://open?path=/tmp"`。
public enum IntermURL {
    public enum ParseFailure: Error, Equatable, CustomStringConvertible {
        case notIntermScheme(String)
        case unsupportedAction(String)
        case missingPath
        case invalidPath(String)

        public var description: String {
            switch self {
            case .notIntermScheme(let scheme):
                return L10n.tr("不是 interm:// 链接（scheme 为 \(scheme)）",
                               "Not an interm:// URL (scheme is \(scheme))")
            case .unsupportedAction(let host):
                return L10n.tr("不支持的 interm:// 动作：\(host)",
                               "Unsupported interm:// action: \(host)")
            case .missingPath:
                return L10n.tr("链接里缺少 path 参数", "The URL has no path parameter")
            case .invalidPath(let value):
                return L10n.tr("链接里的路径无效：\(value)", "Invalid path in URL: \(value)")
            }
        }
    }

    /// 动作部分，目前只有 `open`。
    public static let action = "open"

    public static func make(from request: IntermOpenRequest) -> URL? {
        var components = URLComponents()
        components.scheme = IntermIdentity.urlScheme
        components.host = action

        var items = [URLQueryItem(name: "path", value: request.directory.path)]
        if let terminalID = request.terminalID, !terminalID.isEmpty {
            items.append(URLQueryItem(name: "terminal", value: terminalID))
        }
        components.queryItems = items
        return components.url
    }

    public static func parse(_ url: URL) throws -> IntermOpenRequest {
        guard let scheme = url.scheme, scheme.caseInsensitiveCompare(IntermIdentity.urlScheme) == .orderedSame else {
            throw ParseFailure.notIntermScheme(url.scheme ?? "")
        }

        let host = (url.host ?? "").lowercased()
        // `interm://open` 是标准形态；`interm:open`（无 host）也接受，避免脚本手写时踩坑。
        let actionPart = host.isEmpty ? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) : host
        guard actionPart.caseInsensitiveCompare(action) == .orderedSame else {
            throw ParseFailure.unsupportedAction(actionPart)
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let rawPath = components?.queryItems?.first(where: { $0.name == "path" })?.value
        guard let rawPath, !rawPath.isEmpty else {
            throw ParseFailure.missingPath
        }
        guard !rawPath.contains("\0") else {
            throw ParseFailure.invalidPath(rawPath)
        }

        let directory: URL
        if rawPath.hasPrefix("file://") {
            guard let fileURL = URL(string: rawPath), fileURL.isFileURL else {
                throw ParseFailure.invalidPath(rawPath)
            }
            directory = fileURL
        } else if rawPath.hasPrefix("/") {
            directory = URL(fileURLWithPath: rawPath, isDirectory: true)
        } else {
            throw ParseFailure.invalidPath(rawPath)
        }

        let terminal = components?.queryItems?.first(where: { $0.name == "terminal" })?.value
        return IntermOpenRequest(
            directory: directory,
            terminalID: (terminal?.isEmpty ?? true) ? nil : terminal
        )
    }
}
