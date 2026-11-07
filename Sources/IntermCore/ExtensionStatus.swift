import Foundation

public struct CommandResult: Equatable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol CommandRunning {
    func run(_ executable: String, arguments: [String]) -> CommandResult
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(_ executable: String, arguments: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, stdout: "", stderr: error.localizedDescription)
        }
        let output = out.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return CommandResult(
            status: process.terminationStatus,
            stdout: String(decoding: output, as: UTF8.self),
            stderr: String(decoding: errorOutput, as: UTF8.self)
        )
    }
}

public enum ExtensionRegistration: String, Equatable, Sendable {
    /// `pluginkit` 里带 `+`，用户已启用。
    case enabled
    /// 带 `-`，已注册但被用户关闭。
    case disabled
    /// 完全没注册（App 没装好，或扩展被系统拒绝）。
    case notRegistered
    case unknown
}

/// 查询 FinderSync 扩展在本机的注册/启用状态。
///
/// 宿主 App 可以直接用 `FIFinderSyncController.isExtensionEnabled`，
/// 但那个 API 只能给出布尔值；这里额外跑一次 `pluginkit` 来区分
/// 「没注册」和「注册了但被关闭」，设置界面需要这个区别。
public struct ExtensionStatusChecker {
    public static let pluginkitPath = "/usr/bin/pluginkit"

    private let runner: CommandRunning
    private let bundleID: String

    public init(runner: CommandRunning = ProcessCommandRunner(), bundleID: String = IntermIdentity.extensionBundleID) {
        self.runner = runner
        self.bundleID = bundleID
    }

    public func currentState() -> ExtensionRegistration {
        let result = runner.run(Self.pluginkitPath, arguments: ["-m", "-A", "-v", "-p", "com.apple.FinderSync"])
        guard result.status == 0 else { return .unknown }
        return Self.parse(result.stdout, bundleID: bundleID)
    }

    /// `pluginkit -m -A -v` 每行形如：
    /// `+    com.aone.keka.KekaFinderIntegration(1.6.5)  <uuid>  <date>  <path>`
    public static func parse(_ output: String, bundleID: String) -> ExtensionRegistration {
        for line in output.split(whereSeparator: \.isNewline) {
            let text = String(line)
            guard text.contains(bundleID) else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("+") { return .enabled }
            if trimmed.hasPrefix("-") { return .disabled }
            return .unknown
        }
        return .notRegistered
    }

    public static func describe(_ state: ExtensionRegistration) -> String {
        switch state {
        case .enabled:
            return L10n.tr("已启用", "Enabled")
        case .disabled:
            return L10n.tr("已注册但未启用", "Registered but disabled")
        case .notRegistered:
            return L10n.tr("未注册（可能未安装，或被系统拒绝）", "Not registered (not installed, or rejected by the system)")
        case .unknown:
            return L10n.tr("未知", "Unknown")
        }
    }
}
