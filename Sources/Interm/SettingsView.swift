import SwiftUI
import IntermCore

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            terminalSection
            behaviorSection
            finderSection
            diagnosticsSection
            aboutSection
        }
        .formStyle(.grouped)
        .frame(width: 580, height: 660)
        .onAppear { model.refresh() }
        .onChange(of: model.presetID) { _, _ in model.save() }
        .onChange(of: model.customApplicationPath) { _, _ in model.save() }
        .onChange(of: model.customArguments) { _, _ in model.save() }
        .onChange(of: model.keepRunning) { _, _ in model.save() }
    }

    // MARK: - 终端

    private var terminalSection: some View {
        Section {
            Picker(L10n.tr("终端应用", "Terminal"), selection: $model.presetID) {
                ForEach(model.installedPresets) { preset in
                    Text(label(for: preset)).tag(preset.id)
                }
            }

            if model.isCustomPreset {
                LabeledContent(L10n.tr("App 路径", "Application")) {
                    HStack(spacing: 8) {
                        TextField("", text: $model.customApplicationPath, prompt: Text("/Applications/Ghostty.app"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                        Button(L10n.tr("选择…", "Choose…")) { model.chooseApplication() }
                    }
                }
                LabeledContent(L10n.tr("参数模板", "Arguments")) {
                    TextField("", text: $model.customArguments, prompt: Text("--working-directory={dir}"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                }
                Text(L10n.tr(
                    "留空表示用「把文件夹当文档打开」的方式；填了参数就必须包含 {dir}，Interm 会把目录替换进去后直接运行该 App 的可执行文件。",
                    "Leave empty to open the folder as a document. If you provide arguments they must contain {dir}; Interm replaces it and runs the app's executable directly."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if let preset = TerminalCatalog.preset(withID: model.presetID) {
                Text(description(for: preset))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(L10n.tr("终端", "Terminal"))
        }
    }

    private func label(for preset: TerminalPreset) -> String {
        preset.verified
            ? preset.displayName
            : "\(preset.displayName) · \(L10n.tr("尽力支持", "best effort"))"
    }

    private func description(for preset: TerminalPreset) -> String {
        switch preset.strategy {
        case .openFolderDocument:
            return L10n.tr("用 LaunchServices 把文件夹当文档打开，终端会在该目录新建窗口。",
                           "Opens the folder as a document via LaunchServices; the terminal opens a new window there.")
        case .arguments:
            return L10n.tr("直接运行 App 自带的命令行工具并传入目录参数。",
                           "Runs the app's bundled command line tool with the directory argument.")
        case .custom:
            return ""
        }
    }

    // MARK: - 行为

    private var behaviorSection: some View {
        Section {
            Toggle(isOn: $model.keepRunning) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.tr("常驻菜单栏", "Keep running in the menu bar"))
                    Text(L10n.tr("关闭后每次打开终端都会退出 App；常驻则点击秒开，还能从菜单栏进入设置。",
                                 "When off, Interm quits after each launch. Keeping it running makes clicks instant and keeps settings reachable."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(L10n.tr("行为", "Behavior"))
        }
    }

    // MARK: - Finder 集成

    private var finderSection: some View {
        Section {
            LabeledContent(L10n.tr("Finder 扩展", "Finder extension")) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.extensionStatusIsGood ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(model.extensionStatusText)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button(L10n.tr("启用 / 管理扩展…", "Enable / Manage Extension…")) {
                    model.openExtensionSettings()
                }
                Button(L10n.tr("复制「拖到工具栏」说明", "Copy toolbar instructions")) {
                    model.copyToolbarHint()
                }
            }

            Text(L10n.tr(
                "两条路都能用：① 扩展启用后，右键窗口或选中项有「在终端中打开」，Finder 工具栏也会多一个下拉按钮；② 按住 ⌘ 把 Interm.app 拖到 Finder 工具栏，单击即可直接打开终端（推荐，少一次点击）。",
                "Two ways: (1) with the extension enabled, right-click a window or selection for “Open in Terminal”, and a toolbar popup appears; (2) hold ⌘ and drag Interm.app onto the Finder toolbar — one click opens the terminal (recommended)."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(L10n.tr("另外：Finder 右键 › 服务 › 在终端中打开（默认快捷键 ⌃⌥T），以及 `open \"interm://open?path=/tmp\"` 也能直接调用。",
                         "Also available: Finder › Services › Open in Terminal (default ⌃⌥T) and `open \"interm://open?path=/tmp\"`."))
            .font(.caption)
            .foregroundStyle(.secondary)
        } header: {
            Text(L10n.tr("与访达集成", "Finder integration"))
        }
    }

    // MARK: - 诊断

    private var diagnosticsSection: some View {
        Section {
            LabeledContent(L10n.tr("上次打开", "Last opened")) {
                Text(model.lastUsedDirectory)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                Button(L10n.tr("运行自检", "Run self-test")) { model.runSelftest() }
                Button(L10n.tr("自动化权限设置…", "Automation settings…")) { model.openAutomationSettings() }
            }

            if !model.selftestReport.isEmpty {
                ScrollView {
                    Text(model.selftestReport)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 130)
            }

            Text(L10n.tr("排查日志：log show --last 5m --info --predicate 'subsystem == \"com.menmapro.Interm\"'",
                         "Logs: log show --last 5m --info --predicate 'subsystem == \"com.menmapro.Interm\"'"))
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        } header: {
            Text(L10n.tr("诊断", "Diagnostics"))
        }
    }

    private var aboutSection: some View {
        Section {
            Text(L10n.tr("Interm 版本 \(model.versionText) · 纯 Swift 原生实现",
                         "Interm \(model.versionText) · built natively in Swift"))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
