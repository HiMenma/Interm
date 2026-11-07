import Foundation
import IntermCore

/// 自检：把「装好了没有」这件事变成可编程判断，方便构建脚本和用户一键排查。
///
/// 注意：自检**不会**触发自动化授权（不执行 AppleScript），
/// 想验证访达探测请显式跑 `--probe-finder`。
enum Diagnostics {
    struct Check {
        let name: String
        let passed: Bool
        let detail: String
    }

    static func run(verbose: Bool) -> Int32 {
        let checks = collect()
        for check in checks {
            let mark = check.passed ? "ok  " : "FAIL"
            print("[\(mark)] \(check.name)：\(check.detail)")
        }
        let failures = checks.filter { !$0.passed }
        if failures.isEmpty {
            print("自检通过：\(checks.count) 项")
            return 0
        }
        print("自检失败：\(failures.count)/\(checks.count) 项")
        return 1
    }

    static func collect() -> [Check] {
        var checks: [Check] = []
        let bundle = Bundle.main

        let bundleID = bundle.bundleIdentifier ?? ""
        checks.append(Check(
            name: "Bundle Identifier",
            passed: bundleID == IntermIdentity.appBundleID,
            detail: bundleID.isEmpty ? "（空）" : bundleID
        ))

        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        checks.append(Check(name: "版本", passed: version != "?", detail: "\(version) (\(build))"))

        checks.append(urlRoundTripCheck())
        checks.append(contentsOf: terminalChecks())
        checks.append(extensionCheck())
        checks.append(plistDeclarationsCheck(bundle: bundle))
        return checks
    }

    private static func urlRoundTripCheck() -> Check {
        let tricky = URL(fileURLWithPath: "/tmp/Interm 自检/目录 with 'quote' & 100%", isDirectory: true)
        guard let url = IntermURL.make(from: IntermOpenRequest(directory: tricky, terminalID: "terminal")) else {
            return Check(name: "URL 往返", passed: false, detail: "无法生成 interm:// URL")
        }
        do {
            let parsed = try IntermURL.parse(url)
            let ok = parsed.directory.path == tricky.path && parsed.terminalID == "terminal"
            return Check(name: "URL 往返", passed: ok, detail: ok ? url.absoluteString : "解析结果不一致：\(parsed.directory.path)")
        } catch {
            return Check(name: "URL 往返", passed: false, detail: "\(error)")
        }
    }

    private static func terminalChecks() -> [Check] {
        let installed = TerminalCatalog.installed()
        let names = installed.map(\.displayName).joined(separator: "、")
        var checks = [Check(
            name: "已安装终端",
            passed: !installed.isEmpty,
            detail: names.isEmpty ? "一个都没找到" : names
        )]

        let preferences = Preferences()
        let preset = preferences.preset
        do {
            let directory = FileManager.default.homeDirectoryForCurrentUser
            let launch = try TerminalLauncher().resolve(
                preset: preset,
                customApplicationPath: preferences.customApplicationPath,
                customArguments: preferences.customArguments,
                directory: directory
            )
            checks.append(Check(name: "默认终端可解析", passed: true, detail: "\(preset.displayName)：\(launch.displayCommand)"))
        } catch {
            checks.append(Check(
                name: "默认终端可解析",
                passed: false,
                detail: (error as? CustomStringConvertible)?.description ?? "\(error)"
            ))
        }
        return checks
    }

    private static func extensionCheck() -> Check {
        let state = ExtensionStatusChecker().currentState()
        return Check(
            name: "Finder 扩展",
            passed: state == .enabled,
            detail: ExtensionStatusChecker.describe(state)
        )
    }

    private static func plistDeclarationsCheck(bundle: Bundle) -> Check {
        let urlTypes = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let hasScheme = urlTypes.contains { ($0["CFBundleURLSchemes"] as? [String])?.contains(IntermIdentity.urlScheme) == true }
        let services = bundle.object(forInfoDictionaryKey: "NSServices") as? [[String: Any]] ?? []
        let hasService = services.contains { ($0["NSMessage"] as? String) == IntermIdentity.serviceMessage }
        return Check(
            name: "URL scheme / 服务注册",
            passed: hasScheme && hasService,
            detail: "scheme=\(hasScheme ? "有" : "缺失")，服务=\(hasService ? "有" : "缺失")"
        )
    }
}
