import AppKit
import Foundation
import IntermCore

/// 把「入口事件」统一翻译成「在某个目录打开终端」。
///
/// 三条入口最终都走 `open(directory:source:terminalID:)`：
/// * Finder 工具栏图标点击 / 再次激活 → 问访达要目录
/// * FinderSync 扩展 / `interm://` 链接 → 直接给目录
/// * 服务菜单 / 把文件夹拖到 App 图标 → 给选中的路径
@MainActor
final class LaunchRouter {
    enum Source: String {
        case toolbarClick
        case urlScheme
        case service
        case dragAndDrop
        case statusItem
    }

    private let preferences: Preferences
    private let normalizer: PathNormalizer
    private let launcher: TerminalLauncher
    private let opener: WorkspaceOpening
    private let probe: FinderDirectoryProbe

    /// 弹出错误框时，如果需要「打开设置」，由 AppDelegate 注入回调。
    var onOpenSettings: (() -> Void)?

    /// 300ms 内的相同请求只执行一次：工具栏连点、reopen 与 URL 双触发都能被吃掉。
    private var lastRequest: (path: String, date: Date)?

    init(
        preferences: Preferences,
        normalizer: PathNormalizer = PathNormalizer(),
        launcher: TerminalLauncher = TerminalLauncher(),
        opener: WorkspaceOpening = NSWorkspaceOpener(),
        probe: FinderDirectoryProbe = FinderDirectoryProbe()
    ) {
        self.preferences = preferences
        self.normalizer = normalizer
        self.launcher = launcher
        self.opener = opener
        self.probe = probe
    }

    // MARK: - Entries

    func handle(urls: [URL]) {
        for url in urls {
            if url.isFileURL {
                open(directory: url, source: .dragAndDrop, terminalID: nil)
                continue
            }
            guard url.scheme?.caseInsensitiveCompare(IntermIdentity.urlScheme) == .orderedSame else {
                Log.app.error("ignored URL \(url.absoluteString, privacy: .public)")
                continue
            }
            do {
                let request = try IntermURL.parse(url)
                open(directory: request.directory, source: .urlScheme, terminalID: request.terminalID)
            } catch {
                Dialogs.showError(
                    title: L10n.tr("无法识别的链接", "Unrecognized link"),
                    message: "\(error)"
                )
            }
        }
    }

    func openFinderFrontWindow() {
        switch probe.frontWindowDirectory() {
        case .success(let directory):
            open(directory: directory, source: .toolbarClick, terminalID: nil)

        case .failure(.automationDenied):
            Log.app.error("automation denied; falling back")
            Dialogs.showAutomationDenied()
            open(directory: FinderDirectoryProbe.fallbackDirectory(), source: .toolbarClick, terminalID: nil)

        case .failure(let error):
            // 没有窗口（例如只开着「最近使用」）不算错误，静默退到桌面。
            Log.app.notice("finder probe failed: \(error.description, privacy: .public)")
            open(directory: FinderDirectoryProbe.fallbackDirectory(), source: .toolbarClick, terminalID: nil)
        }
    }

    func open(selection: [URL]) {
        guard let directory = normalizer.directory(forSelection: selection) else {
            Dialogs.showError(
                title: L10n.tr("没有可用的目录", "No usable directory"),
                message: L10n.tr("选中的项目里没有能打开的文件夹。", "None of the selected items is a folder.")
            )
            return
        }
        open(directory: directory, source: .service, terminalID: nil)
    }

    // MARK: - Core

    private func open(directory rawURL: URL, source: Source, terminalID: String?) {
        let directory: URL
        do {
            directory = try normalizer.directory(for: rawURL)
        } catch {
            Dialogs.showError(
                title: L10n.tr("无法打开这个位置", "Cannot open this location"),
                message: (error as? CustomStringConvertible)?.description ?? "\(error)"
            )
            return
        }

        if let lastRequest, lastRequest.path == directory.path, Date().timeIntervalSince(lastRequest.date) < 0.4 {
            Log.app.notice("deduplicated request for \(directory.path, privacy: .public)")
            return
        }
        lastRequest = (directory.path, Date())

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
            Dialogs.showError(
                title: L10n.tr("终端配置不可用", "Terminal configuration problem"),
                message: (error as? CustomStringConvertible)?.description ?? "\(error)",
                settingsHint: true,
                onOpenSettings: onOpenSettings
            )
            return
        }

        do {
            try launcher.perform(launch, directory: directory, using: opener)
            preferences.lastUsedDirectory = directory.path
            Log.app.notice(
                "opened \(directory.path, privacy: .public) with \(preset.id, privacy: .public) source=\(source.rawValue, privacy: .public)"
            )
            if !preferences.keepRunning {
                NSApp.terminate(nil)
            }
        } catch {
            Dialogs.showError(
                title: L10n.tr("启动终端失败", "Failed to launch the terminal"),
                message: (error as? CustomStringConvertible)?.description ?? "\(error)",
                settingsHint: true,
                onOpenSettings: onOpenSettings
            )
        }
    }
}
