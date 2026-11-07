import AppKit
import FinderSync
import Foundation
import IntermCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, StatusItemActionTarget {
    private let preferences = Preferences()
    private lazy var router = LaunchRouter(preferences: preferences)

    private var statusItem: StatusItemController?
    private var settingsController: SettingsWindowController?
    private var pendingClickTimer: Timer?

    /// 本次启动是否已经处理过 `interm://` 事件。
    ///
    /// 实测（macOS 27）：URL 唤起时 `application(_:open:)` 会**先于**
    /// `applicationDidFinishLaunching` 到达。如果不在后者里检查这个标记，
    /// 就会在打开目标目录之后，又按「工具栏点击」把前台目录再开一次。
    private var didReceiveOpenEvent = false

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        router.onOpenSettings = { [weak self] in self?.showSettings() }
        statusItem = StatusItemController(target: self)
        Log.app.notice("launched, onboarding=\(!self.preferences.hasCompletedOnboarding, privacy: .public)")

        if CommandLineMode.wantsSettingsOnLaunch {
            showSettings()
            return
        }

        // 已经由 URL 唤起（扩展菜单 / open interm://…）：不要再当成工具栏点击。
        if didReceiveOpenEvent {
            Log.app.notice("launch finished after URL event; not probing Finder")
            return
        }

        if !preferences.hasCompletedOnboarding {
            // 第一次启动（通常是刚安装完双击 App）：先给设置窗口，避免用户莫名其妙被打开终端。
            preferences.hasCompletedOnboarding = true
            showSettings()
            return
        }

        scheduleToolbarClick()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        didReceiveOpenEvent = true
        cancelPendingClick()
        Log.app.notice("open event, urls=\(urls.count, privacy: .public)")
        router.handle(urls: urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 工具栏图标再次点击时 LaunchServices 发 reopen 事件，这里接住。
        Log.app.notice("reopen event, hasVisibleWindows=\(flag, privacy: .public)")
        cancelPendingClick()
        router.openFinderFrontWindow()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        cancelPendingClick()
    }

    // MARK: - Click handling

    /// 冷启动时无法立刻区分「点工具栏」和「被 URL 唤起」，
    /// 先用一个很短的定时器等 URL 事件；收到 URL 就取消。
    private func scheduleToolbarClick() {
        pendingClickTimer?.invalidate()
        let timer = Timer(timeInterval: 0.35, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pendingClickTimer = nil
                guard !self.didReceiveOpenEvent else { return }
                self.router.openFinderFrontWindow()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pendingClickTimer = timer
    }

    private func cancelPendingClick() {
        pendingClickTimer?.invalidate()
        pendingClickTimer = nil
    }

    // MARK: - Services

    /// 对应 Info.plist 里 `NSServices` 的 `NSMessage`。
    @objc(openInTerminalHere:userData:error:)
    func openInTerminalHere(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        cancelPendingClick()
        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        let paths = (pboard.propertyList(forType: filenamesType) as? [String]) ?? []
        Log.app.notice("service invoked with \(paths.count) item(s)")
        router.open(selection: paths.map { URL(fileURLWithPath: $0) })
    }

    // MARK: - StatusItemActionTarget

    func statusOpenFinderFrontWindow() {
        cancelPendingClick()
        router.openFinderFrontWindow()
    }

    func statusShowSettings() {
        showSettings()
    }

    func statusOpenExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
        NSApp.activate(ignoringOtherApps: true)
    }

    func statusCopyToolbarHint() {
        ToolbarHint.copyToPasteboard()
    }

    func statusQuit() {
        NSApp.terminate(nil)
    }

    // MARK: - Settings window

    private func showSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(model: SettingsModel(preferences: preferences))
        }
        settingsController?.show()
    }
}
