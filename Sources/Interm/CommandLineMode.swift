import AppKit
import Foundation
import IntermCore

/// 无 UI 命令行入口。
///
/// 用途有三个：
/// 1. 脚本/快捷键调用：`Interm --open-at <dir>`；
/// 2. 排障：`--selftest`、`--probe-finder`、`--dry-run`；
/// 3. 构建脚本冒烟测试，不需要人工点 Finder。
enum CommandLineMode {
    /// 是否要求启动后直接打开设置窗口（`--settings`）。
    private(set) static var wantsSettingsOnLaunch = false

    static func runIfRequested(arguments: [String]) -> Int32? {
        let arguments = Array(arguments.dropFirst())
        guard !arguments.isEmpty else { return nil }

        var index = 0
        var openAt: String?
        var terminalID: String?
        var dryRun = false
        var json = false

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--version", "-v":
                print(versionString())
                return 0
            case "--help", "-h":
                print(usage)
                return 0
            case "--selftest":
                return Diagnostics.run(verbose: true)
            case "--probe-finder":
                return probeFinder()
            case "--settings":
                wantsSettingsOnLaunch = true
                return nil
            case "--dry-run":
                dryRun = true
            case "--json":
                json = true
            case "--open-at":
                index += 1
                guard index < arguments.count else {
                    FileHandle.standardError.write(Data("--open-at 需要一个路径参数\n".utf8))
                    return 2
                }
                openAt = arguments[index]
            case "--terminal":
                index += 1
                guard index < arguments.count else {
                    FileHandle.standardError.write(Data("--terminal 需要一个预设 id\n".utf8))
                    return 2
                }
                terminalID = arguments[index]
            default:
                if argument.hasPrefix("-") {
                    FileHandle.standardError.write(Data("未知参数：\(argument)\n\(usage)\n".utf8))
                    return 2
                }
                openAt = argument
            }
            index += 1
        }

        if let openAt {
            return open(directoryPath: openAt, terminalID: terminalID, dryRun: dryRun, json: json)
        }
        return nil
    }

    static var usage: String {
        """
        \(IntermIdentity.displayName) —— 在 Finder 中一键打开终端

        用法：
          Interm                     启动状态栏 App（等同于点击 Finder 工具栏图标）
          Interm --settings          启动并打开设置窗口
          Interm --open-at <路径>     在指定目录打开终端
          Interm --open-at <路径> --terminal <id>   指定终端预设
          Interm --open-at <路径> --dry-run         只打印将要执行的命令
          Interm --open-at <路径> --json            以 JSON 输出结果
          Interm --probe-finder      打印访达当前窗口目录（会触发自动化授权）
          Interm --selftest          运行自检并返回退出码
          Interm --version           打印版本
        """
    }

    static func versionString() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? IntermIdentity.fallbackVersion
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(IntermIdentity.displayName) \(version) (\(build))"
    }

    // MARK: - Actions

    private static func open(directoryPath: String, terminalID: String?, dryRun: Bool, json: Bool) -> Int32 {
        let preferences = Preferences()
        let normalizer = PathNormalizer()
        let launcher = TerminalLauncher()

        let rawURL = directoryPath.hasPrefix("/")
            ? URL(fileURLWithPath: directoryPath, isDirectory: true)
            : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(directoryPath)

        let directory: URL
        do {
            directory = try normalizer.directory(for: rawURL)
        } catch {
            return fail(message: (error as? CustomStringConvertible)?.description ?? "\(error)", json: json, code: 3)
        }

        let preset = terminalID.flatMap(TerminalCatalog.preset(withID:)) ?? preferences.preset
        let launch: ResolvedLaunch
        do {
            launch = try launcher.resolve(
                preset: preset,
                customApplicationPath: preferences.customApplicationPath,
                customArguments: preferences.customArguments,
                directory: directory
            )
        } catch {
            return fail(message: (error as? CustomStringConvertible)?.description ?? "\(error)", json: json, code: 4)
        }

        if dryRun {
            if json {
                let payload: [String: Any] = [
                    "directory": directory.path,
                    "preset": preset.id,
                    "command": launch.displayCommand,
                    "dryRun": true
                ]
                print(jsonString(payload))
            } else {
                print("目录：\(directory.path)")
                print("终端：\(preset.displayName) (\(preset.id))")
                print("执行：\(launch.displayCommand)")
            }
            return 0
        }

        do {
            try launcher.perform(launch, directory: directory)
        } catch {
            return fail(message: (error as? CustomStringConvertible)?.description ?? "\(error)", json: json, code: 4)
        }

        var preferencesToUpdate = preferences
        preferencesToUpdate.lastUsedDirectory = directory.path
        Log.app.notice("CLI opened \(directory.path, privacy: .public) with \(preset.id, privacy: .public)")

        if json {
            print(jsonString([
                "directory": directory.path,
                "preset": preset.id,
                "command": launch.displayCommand,
                "ok": true
            ]))
        }
        return 0
    }

    private static func probeFinder() -> Int32 {
        switch FinderDirectoryProbe().frontWindowDirectory() {
        case .success(let url):
            print(url.path)
            return 0
        case .failure(let error):
            FileHandle.standardError.write(Data("\(error.description)\n".utf8))
            return 3
        }
    }

    private static func fail(message: String, json: Bool, code: Int32) -> Int32 {
        if json {
            print(jsonString(["ok": false, "error": message]))
        } else {
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }
        return code
    }

    private static func jsonString(_ payload: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .prettyPrinted]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}
