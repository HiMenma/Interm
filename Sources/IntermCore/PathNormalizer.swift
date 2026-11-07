import Foundation

/// 判断路径是否存在、是否是目录。
///
/// 抽成协议是为了让单测不依赖真实文件系统。
public protocol FileSystemProbing {
    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool
}

public struct DefaultFileSystemProbe: FileSystemProbing {
    public init() {}

    public func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        FileManager.default.fileExists(atPath: path, isDirectory: isDirectory)
    }
}

public enum PathNormalizationError: Error, Equatable, CustomStringConvertible {
    case emptyPath
    case notFileURL(String)
    case notFound(String)
    case notADirectory(String)

    public var description: String {
        switch self {
        case .emptyPath:
            return L10n.tr("路径为空", "The path is empty")
        case .notFileURL(let path):
            return L10n.tr("不是本地文件路径：\(path)", "Not a local file path: \(path)")
        case .notFound(let path):
            return L10n.tr("目录不存在：\(path)", "Directory does not exist: \(path)")
        case .notADirectory(let path):
            return L10n.tr("这是一个文件，而不是目录：\(path)", "This is a file, not a directory: \(path)")
        }
    }
}

/// 把「用户点击的东西」统一折算成一个可以 `cd` 进去的目录。
///
/// 规则：
/// * 目录 → 自身
/// * 文件 → 所在目录
/// * 多选 → 第一个能解析出来的
/// * 默认解析符号链接，避免终端里的 `pwd` 与 Finder 显示不一致
public struct PathNormalizer {
    private let probe: FileSystemProbing

    public init(probe: FileSystemProbing = DefaultFileSystemProbe()) {
        self.probe = probe
    }

    public func directory(for rawURL: URL, resolveSymlinks: Bool = true) throws -> URL {
        guard rawURL.isFileURL else {
            throw PathNormalizationError.notFileURL(rawURL.absoluteString)
        }
        guard !rawURL.path.isEmpty else { throw PathNormalizationError.emptyPath }

        let standardized = rawURL.standardizedFileURL
        var isDirectory: ObjCBool = false
        let exists = probe.fileExists(atPath: standardized.path, isDirectory: &isDirectory)

        guard exists else {
            throw PathNormalizationError.notFound(standardized.path)
        }

        let candidate: URL
        if isDirectory.boolValue {
            candidate = standardized
        } else {
            // 选中文件时用父目录；父目录本身不再做存在性检查（文件存在即说明父目录存在）。
            candidate = standardized.deletingLastPathComponent()
        }

        return resolveSymlinks ? candidate.resolvingSymlinksInPath() : candidate
    }

    /// 处理 Finder 多选：逐个尝试，返回第一个成功解析的目录。
    public func directory(forSelection urls: [URL], resolveSymlinks: Bool = true) -> URL? {
        for url in urls {
            if let directory = try? directory(for: url, resolveSymlinks: resolveSymlinks) {
                return directory
            }
        }
        return nil
    }
}

/// shell 单引号引用，供命令行展示与自定义参数使用。
public enum Shell {
    /// 用单引号包裹；字符串内的单引号写成 `'\''`。
    public static func quote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        let plain = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+=:,@%")
        if value.unicodeScalars.allSatisfy({ plain.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// 展示用：把可执行文件和参数拼成一行可复制的命令。
    public static func commandLine(executable: String, arguments: [String]) -> String {
        ([executable] + arguments).map(quote).joined(separator: " ")
    }
}
