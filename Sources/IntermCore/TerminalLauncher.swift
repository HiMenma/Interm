import Foundation

/// 真正「执行打开动作」的抽象。
///
/// 生产实现用 `NSWorkspace` / `Process`，单测用 mock，
/// 这样参数拼装逻辑可以完全脱离 GUI 测试。
public protocol WorkspaceOpening {
    func openFolderDocument(_ directory: URL, using application: URL) throws
    func launchExecutable(_ executable: URL, arguments: [String], workingDirectory: URL) throws
}

public enum TerminalLaunchError: Error, Equatable, CustomStringConvertible {
    case directoryUnavailable(String)
    case applicationNotFound(String)
    case executableNotFound(String)
    case emptyCustomApplication
    case customTemplateMissingDirectory
    case launchFailed(String)

    public var description: String {
        switch self {
        case .directoryUnavailable(let path):
            return L10n.tr("目录不可用：\(path)", "Directory is not available: \(path)")
        case .applicationNotFound(let name):
            return L10n.tr("找不到终端 App：\(name)", "Terminal application not found: \(name)")
        case .executableNotFound(let path):
            return L10n.tr("找不到可执行文件：\(path)", "Executable not found: \(path)")
        case .emptyCustomApplication:
            return L10n.tr("自定义模式还没有填写 App 路径", "Custom mode has no application path")
        case .customTemplateMissingDirectory:
            return L10n.tr("自定义参数里缺少 {dir} 占位符，终端不会知道要打开哪个目录",
                           "The custom arguments are missing the {dir} placeholder")
        case .launchFailed(let message):
            return L10n.tr("启动失败：\(message)", "Failed to launch: \(message)")
        }
    }
}

/// 解析完成的启动方案：知道要调用什么、带什么参数。
public struct ResolvedLaunch: Equatable {
    public enum Kind: Equatable {
        case folderDocument
        case executable
    }

    public let kind: Kind
    public let applicationPath: String
    public let executablePath: String?
    public let arguments: [String]

    public init(kind: Kind, applicationPath: String, executablePath: String? = nil, arguments: [String] = []) {
        self.kind = kind
        self.applicationPath = applicationPath
        self.executablePath = executablePath
        self.arguments = arguments
    }

    /// 供 `--dry-run` 与日志使用的一行描述。
    public var displayCommand: String {
        switch kind {
        case .folderDocument:
            return L10n.tr("用 \(applicationPath) 打开文件夹（文档方式）",
                           "Open folder with \(applicationPath) as a document")
        case .executable:
            return Shell.commandLine(executable: executablePath ?? applicationPath, arguments: arguments)
        }
    }
}

/// 把「终端预设 + 用户设置 + 目录」编译成一个可执行的启动方案，然后执行它。
public struct TerminalLauncher {
    private let probe: FileSystemProbing

    public init(probe: FileSystemProbing = DefaultFileSystemProbe()) {
        self.probe = probe
    }

    public func resolve(
        preset: TerminalPreset,
        customApplicationPath: String = "",
        customArguments: String = "",
        directory: URL
    ) throws -> ResolvedLaunch {
        var isDirectory: ObjCBool = false
        let exists = probe.fileExists(atPath: directory.path, isDirectory: &isDirectory)
        guard exists, isDirectory.boolValue else {
            throw TerminalLaunchError.directoryUnavailable(directory.path)
        }

        switch preset.strategy {
        case .openFolderDocument:
            let application = try requireApplication(for: preset)
            return ResolvedLaunch(kind: .folderDocument, applicationPath: application.path)

        case .arguments(let template):
            let application = try requireApplication(for: preset)
            guard let executableName = preset.cliExecutableName else {
                throw TerminalLaunchError.executableNotFound(application.path)
            }
            let executable = application
                .appendingPathComponent("Contents/MacOS/\(executableName)")
                .standardizedFileURL
            guard probe.fileExists(atPath: executable.path, isDirectory: nil) else {
                throw TerminalLaunchError.executableNotFound(executable.path)
            }
            let arguments = template.map { $0.replacingOccurrences(of: Self.directoryPlaceholder, with: directory.path) }
            return ResolvedLaunch(
                kind: .executable,
                applicationPath: application.path,
                executablePath: executable.path,
                arguments: arguments
            )

        case .custom:
            return try resolveCustom(
                applicationPath: customApplicationPath,
                argumentsTemplate: customArguments,
                directory: directory
            )
        }
    }

    public func perform(_ launch: ResolvedLaunch, directory: URL, using opener: WorkspaceOpening = NSWorkspaceOpener()) throws {
        switch launch.kind {
        case .folderDocument:
            let application = URL(fileURLWithPath: launch.applicationPath, isDirectory: true)
            try opener.openFolderDocument(directory, using: application)
        case .executable:
            guard let executablePath = launch.executablePath else {
                throw TerminalLaunchError.executableNotFound(launch.applicationPath)
            }
            try opener.launchExecutable(
                URL(fileURLWithPath: executablePath),
                arguments: launch.arguments,
                workingDirectory: directory
            )
        }
    }

    // MARK: - Custom preset

    static let directoryPlaceholder = "{dir}"

    private func resolveCustom(applicationPath: String, argumentsTemplate: String, directory: URL) throws -> ResolvedLaunch {
        let trimmedApplication = applicationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedApplication.isEmpty else { throw TerminalLaunchError.emptyCustomApplication }

        let application = URL(fileURLWithPath: trimmedApplication).standardizedFileURL
        guard probe.fileExists(atPath: application.path, isDirectory: nil) else {
            throw TerminalLaunchError.applicationNotFound(trimmedApplication)
        }

        let rawArguments = argumentsTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawArguments.isEmpty else {
            return ResolvedLaunch(kind: .folderDocument, applicationPath: application.path)
        }

        guard rawArguments.contains(Self.directoryPlaceholder) else {
            throw TerminalLaunchError.customTemplateMissingDirectory
        }

        let tokens = Self.tokenize(argumentsTemplate).map {
            $0.replacingOccurrences(of: Self.directoryPlaceholder, with: directory.path)
        }
        let executable: URL
        if application.pathExtension.lowercased() == "app" {
            let name = Self.bundleExecutableName(ofApplicationAt: application) ?? application.deletingPathExtension().lastPathComponent
            executable = application.appendingPathComponent("Contents/MacOS/\(name)")
        } else {
            executable = application
        }
        guard probe.fileExists(atPath: executable.path, isDirectory: nil) else {
            throw TerminalLaunchError.executableNotFound(executable.path)
        }
        return ResolvedLaunch(
            kind: .executable,
            applicationPath: application.path,
            executablePath: executable.path,
            arguments: tokens
        )
    }

    private func requireApplication(for preset: TerminalPreset) throws -> URL {
        guard let application = TerminalCatalog.applicationURL(for: preset, probe: probe) else {
            throw TerminalLaunchError.applicationNotFound(preset.displayName)
        }
        return application
    }

    /// 读 `.app` 的 `CFBundleExecutable`，避免猜名字猜错。
    static func bundleExecutableName(ofApplicationAt application: URL) -> String? {
        let infoPlist = application.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoPlist),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let name = plist["CFBundleExecutable"] as? String,
              !name.isEmpty
        else { return nil }
        return name
    }

    /// 参数模板分词：支持单引号、双引号和反斜杠转义，行为与 shell 足够接近。
    public static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var hasToken = false
        var quote: Character?
        var escaped = false

        for character in input {
            if escaped {
                current.append(character)
                hasToken = true
                escaped = false
                continue
            }
            switch character {
            case "\\" where quote != "'":
                escaped = true
                hasToken = true
            case "'", "\"":
                if quote == nil {
                    quote = character
                    hasToken = true
                } else if quote == character {
                    quote = nil
                } else {
                    current.append(character)
                    hasToken = true
                }
            case " ", "\t", "\n":
                if quote == nil {
                    if hasToken {
                        tokens.append(current)
                        current = ""
                        hasToken = false
                    }
                } else {
                    current.append(character)
                }
            default:
                current.append(character)
                hasToken = true
            }
        }
        if hasToken || !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}
