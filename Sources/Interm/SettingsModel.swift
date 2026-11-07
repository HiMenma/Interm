import AppKit
import Combine
import UniformTypeIdentifiers
import FinderSync
import Foundation
import IntermCore

/// 设置窗口的视图模型。
///
/// 每次修改立刻写入 UserDefaults：App 没有「确定/取消」语义，
/// 关了窗口再打开必须看到刚才的选择。
@MainActor
final class SettingsModel: ObservableObject {
    @Published var presetID: String
    @Published var customApplicationPath: String
    @Published var customArguments: String
    @Published var keepRunning: Bool

    @Published private(set) var extensionState: ExtensionRegistration = .unknown
    @Published private(set) var systemExtensionEnabled = false
    @Published private(set) var lastUsedDirectory = "—"
    @Published private(set) var selftestReport = ""

    private let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
        self.presetID = preferences.terminalPresetID
        self.customApplicationPath = preferences.customApplicationPath
        self.customArguments = preferences.customArguments
        self.keepRunning = preferences.keepRunning
        refresh()
    }

    // MARK: - Derived

    var installedPresets: [TerminalPreset] {
        TerminalCatalog.installed()
    }

    var isCustomPreset: Bool {
        presetID == TerminalCatalog.custom.id
    }

    var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? IntermIdentity.fallbackVersion
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) (\(build))"
    }

    var extensionStatusText: String {
        if systemExtensionEnabled { return L10n.tr("已启用", "Enabled") }
        return ExtensionStatusChecker.describe(extensionState)
    }

    var extensionStatusIsGood: Bool {
        systemExtensionEnabled || extensionState == .enabled
    }

    // MARK: - Actions

    func save() {
        preferences.terminalPresetID = presetID
        preferences.customApplicationPath = customApplicationPath
        preferences.customArguments = customArguments
        preferences.keepRunning = keepRunning
    }

    func refresh() {
        extensionState = ExtensionStatusChecker().currentState()
        systemExtensionEnabled = FIFinderSyncController.isExtensionEnabled
        lastUsedDirectory = preferences.lastUsedDirectory ?? "—"
    }

    func openExtensionSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
        NSApp.activate(ignoringOtherApps: true)
    }

    func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = L10n.tr("选择终端 App", "Choose a terminal application")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        customApplicationPath = url.path
        presetID = TerminalCatalog.custom.id
        save()
    }

    func copyToolbarHint() {
        ToolbarHint.copyToPasteboard()
    }

    func openAutomationSettings() {
        if let url = FinderDirectoryProbe.automationSettingsURL {
            NSWorkspace.shared.open(url)
        }
    }

    func runSelftest() {
        let checks = Diagnostics.collect()
        let lines = checks.map { check -> String in
            let mark = check.passed ? "✓" : "✗"
            return "\(mark) \(check.name)：\(check.detail)"
        }
        let failures = checks.filter { !$0.passed }.count
        let summary = failures == 0
            ? L10n.tr("全部通过（\(checks.count) 项）", "All passed (\(checks.count) checks)")
            : L10n.tr("有 \(failures) 项失败", "\(failures) check(s) failed")
        selftestReport = ([summary] + lines).joined(separator: "\n")
    }
}
