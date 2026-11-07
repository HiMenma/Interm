import XCTest
@testable import IntermCore

final class TerminalCatalogTests: XCTestCase {
    func testDefaultPresetIsTerminal() {
        XCTAssertEqual(Preferences(store: MemoryStore()).terminalPresetID, "terminal")
        XCTAssertEqual(TerminalCatalog.preset(withID: "terminal")?.strategy, .openFolderDocument)
    }

    func testUnknownPresetLookupReturnsNil() {
        XCTAssertNil(TerminalCatalog.preset(withID: "nope"))
    }

    func testInstalledFiltersByPresence() {
        let probe = FakeProbe(directories: ["/System/Applications/Utilities/Terminal.app"])
        let installed = TerminalCatalog.installed(probe: probe).map(\.id)
        XCTAssertEqual(installed, ["terminal", "custom"])
    }

    func testApplicationURLPrefersFirstExistingCandidate() {
        let probe = FakeProbe(directories: ["/Applications/Utilities/Terminal.app"])
        let url = TerminalCatalog.applicationURL(for: TerminalCatalog.terminal, probe: probe)
        XCTAssertEqual(url?.path, "/Applications/Utilities/Terminal.app")
    }

    func testArgumentsPresetsHavePlaceholder() {
        for preset in TerminalCatalog.all {
            guard case .arguments(let arguments) = preset.strategy else { continue }
            XCTAssertTrue(
                arguments.contains { $0.contains("{dir}") },
                "\(preset.id) 的参数里必须有 {dir}"
            )
        }
    }
}

final class TerminalLauncherTests: XCTestCase {
    private let directory = URL(fileURLWithPath: "/Users/example/project", isDirectory: true)

    private func makeProbe(extra: [String] = []) -> FakeProbe {
        FakeProbe(
            directories: ["/Users/example/project", "/System/Applications/Utilities/Terminal.app"] + extra,
            files: ["/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"]
        )
    }

    func testResolveFolderDocumentUsesApplicationPath() throws {
        let launcher = TerminalLauncher(probe: makeProbe())
        let launch = try launcher.resolve(preset: TerminalCatalog.terminal, directory: directory)
        XCTAssertEqual(launch.kind, .folderDocument)
        XCTAssertEqual(launch.applicationPath, "/System/Applications/Utilities/Terminal.app")
        XCTAssertTrue(launch.displayCommand.contains("Terminal.app"))
    }

    func testResolveRejectsMissingDirectory() {
        let launcher = TerminalLauncher(probe: makeProbe())
        XCTAssertThrowsError(
            try launcher.resolve(preset: TerminalCatalog.terminal, directory: URL(fileURLWithPath: "/nope"))
        ) { error in
            XCTAssertEqual(error as? TerminalLaunchError, .directoryUnavailable("/nope"))
        }
    }

    func testResolveArgumentsPresetSubstitutesDirectory() throws {
        let probe = FakeProbe(
            directories: ["/Users/example/project", "/Applications/kitty.app"],
            files: ["/Applications/kitty.app/Contents/MacOS/kitty"]
        )
        let launcher = TerminalLauncher(probe: probe)
        let launch = try launcher.resolve(preset: TerminalCatalog.kitty, directory: directory)
        XCTAssertEqual(launch.kind, .executable)
        XCTAssertEqual(launch.executablePath, "/Applications/kitty.app/Contents/MacOS/kitty")
        XCTAssertEqual(launch.arguments, ["--directory", "/Users/example/project"])
    }

    func testResolveArgumentsPresetRequiresExecutable() {
        let probe = FakeProbe(directories: ["/Users/example/project", "/Applications/kitty.app"])
        let launcher = TerminalLauncher(probe: probe)
        XCTAssertThrowsError(try launcher.resolve(preset: TerminalCatalog.kitty, directory: directory)) { error in
            guard case .executableNotFound = (error as? TerminalLaunchError) else {
                return XCTFail("expected executableNotFound, got \(error)")
            }
        }
    }

    func testCustomPresetWithoutArgumentsFallsBackToFolderDocument() throws {
        let probe = FakeProbe(
            directories: ["/Users/example/project", "/Applications/Ghostty.app"]
        )
        let launcher = TerminalLauncher(probe: probe)
        let launch = try launcher.resolve(
            preset: TerminalCatalog.custom,
            customApplicationPath: "/Applications/Ghostty.app",
            customArguments: "",
            directory: directory
        )
        XCTAssertEqual(launch.kind, .folderDocument)
        XCTAssertEqual(launch.applicationPath, "/Applications/Ghostty.app")
    }

    func testCustomPresetWithArgumentsNeedsPlaceholder() {
        let probe = FakeProbe(directories: ["/Users/example/project", "/Applications/Ghostty.app"])
        let launcher = TerminalLauncher(probe: probe)
        XCTAssertThrowsError(
            try launcher.resolve(
                preset: TerminalCatalog.custom,
                customApplicationPath: "/Applications/Ghostty.app",
                customArguments: "--working-directory",
                directory: directory
            )
        ) { error in
            XCTAssertEqual(error as? TerminalLaunchError, .customTemplateMissingDirectory)
        }
    }

    func testCustomPresetRunsBundleExecutable() throws {
        // 没有 Info.plist 可读时退回用 App 名当可执行文件名。
        let probe = FakeProbe(
            directories: ["/Users/example/project", "/Applications/kitty.app"],
            files: ["/Applications/kitty.app/Contents/MacOS/kitty"]
        )
        let launch = try TerminalLauncher(probe: probe).resolve(
            preset: TerminalCatalog.custom,
            customApplicationPath: "/Applications/kitty.app",
            customArguments: "--working-directory={dir}",
            directory: directory
        )
        XCTAssertEqual(launch.kind, .executable)
        XCTAssertEqual(launch.executablePath, "/Applications/kitty.app/Contents/MacOS/kitty")
        XCTAssertEqual(launch.arguments, ["--working-directory=/Users/example/project"])
    }

    func testBundleExecutableNameReadsRealInfoPlist() {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app", isDirectory: true)
        XCTAssertEqual(TerminalLauncher.bundleExecutableName(ofApplicationAt: terminal), "Terminal")
    }

    func testCustomPresetRequiresApplicationPath() {
        let launcher = TerminalLauncher(probe: makeProbe())
        XCTAssertThrowsError(
            try launcher.resolve(preset: TerminalCatalog.custom, customApplicationPath: "  ", directory: directory)
        ) { error in
            XCTAssertEqual(error as? TerminalLaunchError, .emptyCustomApplication)
        }
    }

    func testPerformCallsOpenerForFolderDocument() throws {
        let launcher = TerminalLauncher(probe: makeProbe())
        let launch = try launcher.resolve(preset: TerminalCatalog.terminal, directory: directory)
        let opener = MockOpener()
        try launcher.perform(launch, directory: directory, using: opener)
        XCTAssertEqual(
            opener.folderCalls,
            [MockOpener.FolderCall(directory: directory.path, application: "/System/Applications/Utilities/Terminal.app")]
        )
        XCTAssertTrue(opener.executableCalls.isEmpty)
    }

    func testPerformCallsOpenerForExecutable() throws {
        let probe = FakeProbe(
            directories: ["/Users/example/project", "/Applications/WezTerm.app"],
            files: ["/Applications/WezTerm.app/Contents/MacOS/wezterm"]
        )
        let launcher = TerminalLauncher(probe: probe)
        let launch = try launcher.resolve(preset: TerminalCatalog.wezterm, directory: directory)
        let opener = MockOpener()
        try launcher.perform(launch, directory: directory, using: opener)
        XCTAssertEqual(opener.executableCalls.first?.arguments, ["start", "--cwd", directory.path])
        XCTAssertEqual(opener.executableCalls.first?.workingDirectory, directory.path)
    }

    // MARK: - Argument tokenizer

    func testTokenizerHandlesQuotesAndEscapes() {
        XCTAssertEqual(
            TerminalLauncher.tokenize("--a \"b c\" 'd e' f\\ g"),
            ["--a", "b c", "d e", "f g"]
        )
        XCTAssertEqual(TerminalLauncher.tokenize(""), [])
        XCTAssertEqual(TerminalLauncher.tokenize("   "), [])
        XCTAssertEqual(TerminalLauncher.tokenize("--flag="), ["--flag="])
    }

    func testTokenizerKeepsEmptyQuotedArgument() {
        XCTAssertEqual(TerminalLauncher.tokenize("a \"\" b"), ["a", "", "b"])
    }
}
