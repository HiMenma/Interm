import AppKit
import Foundation

/// `WorkspaceOpening` 的生产实现。
///
/// 用 `NSWorkspace` 把文件夹当作文档交给终端 App；
/// LaunchServices 会拉起 App（已在运行则新建窗口），不需要 AppleScript 权限。
public final class NSWorkspaceOpener: WorkspaceOpening {
    /// 等 LaunchServices 回调的上限，避免主线程无限等待。
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 5) {
        self.timeout = timeout
    }

    public func openFolderDocument(_ directory: URL, using application: URL) throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false

        var launchError: Error?
        var finished = false

        NSWorkspace.shared.open([directory], withApplicationAt: application, configuration: configuration) { _, error in
            launchError = error
            finished = true
        }

        // 回调线程不确定，这里用 run loop 泵等待，保证主线程不死锁。
        let deadline = Date().addingTimeInterval(timeout)
        while !finished, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }

        if let launchError {
            throw TerminalLaunchError.launchFailed(launchError.localizedDescription)
        }
        if !finished {
            throw TerminalLaunchError.launchFailed(
                L10n.tr("等待终端响应超时", "Timed out waiting for the terminal application")
            )
        }
    }

    public func launchExecutable(_ executable: URL, arguments: [String], workingDirectory: URL) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        do {
            try process.run()
        } catch {
            throw TerminalLaunchError.launchFailed(error.localizedDescription)
        }
    }
}
