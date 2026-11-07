import XCTest
@testable import IntermCore

final class FinderDirectoryProbeTests: XCTestCase {
    private func makeProbe(_ runner: MockAppleScriptRunner, attempts: Int = 3) -> FinderDirectoryProbe {
        FinderDirectoryProbe(runner: runner, attempts: attempts, retryDelay: 0, sleep: { _ in })
    }

    func testReturnsDirectoryOnFirstSuccess() {
        let runner = MockAppleScriptRunner(responses: [.success("/Users/example/project\n")])
        let result = makeProbe(runner).frontWindowDirectory()
        XCTAssertEqual(try? result.get().path, "/Users/example/project")
        XCTAssertEqual(runner.invokedCount, 1)
    }

    func testRetriesWhenFinderHasNoWindowYet() {
        let runner = MockAppleScriptRunner(responses: [
            .failure(code: -1728, message: "no window"),
            .success("/Users/example/Desktop")
        ])
        let result = makeProbe(runner).frontWindowDirectory()
        XCTAssertEqual(try? result.get().path, "/Users/example/Desktop")
        XCTAssertEqual(runner.invokedCount, 2)
    }

    func testEmptyPathIsTreatedAsNoWindow() {
        let runner = MockAppleScriptRunner(responses: [.success(""), .success("")])
        guard case .failure(.noWindow) = makeProbe(runner).frontWindowDirectory() else {
            return XCTFail("expected noWindow")
        }
    }

    func testAutomationDeniedReturnsImmediately() {
        let runner = MockAppleScriptRunner(responses: [
            .failure(code: -1743, message: "not authorized"),
            .success("/Users/example/should-not-be-used")
        ])
        guard case .failure(.automationDenied) = makeProbe(runner).frontWindowDirectory() else {
            return XCTFail("expected automationDenied")
        }
        XCTAssertEqual(runner.invokedCount, 1)
    }

    func testFinderNotRunningIsTreatedAsNoWindow() {
        let runner = MockAppleScriptRunner(responses: [.failure(code: -600, message: "not running")])
        guard case .failure(.noWindow) = makeProbe(runner).frontWindowDirectory() else {
            return XCTFail("expected noWindow")
        }
    }

    func testUnexpectedErrorSurfacesMessage() {
        let runner = MockAppleScriptRunner(responses: [.failure(code: -1, message: "boom")])
        guard case .failure(.scriptFailed(let message)) = makeProbe(runner, attempts: 1).frontWindowDirectory() else {
            return XCTFail("expected scriptFailed")
        }
        XCTAssertTrue(message.contains("boom"))
    }

    func testFallbackDirectoryPrefersDesktop() {
        let fallback = FinderDirectoryProbe.fallbackDirectory(fileExists: { _ in true })
        XCTAssertEqual(fallback.lastPathComponent, "Desktop")
    }

    func testFallbackDirectoryFallsBackToHome() {
        let fallback = FinderDirectoryProbe.fallbackDirectory(fileExists: { _ in false })
        XCTAssertEqual(fallback.path, FileManager.default.homeDirectoryForCurrentUser.path)
    }
}

final class ExtensionStatusTests: XCTestCase {
    private let bundleID = "com.menmapro.Interm.Finder"

    func testParsesEnabledLine() {
        let output = """
        +    com.aone.keka.KekaFinderIntegration(1.6.5)  ABC 2026-11-01 /Applications/Keka.app
        +    com.menmapro.Interm.Finder(1.0.0)  DEF 2026-11-07 /Users/x/Applications/Interm.app
        """
        XCTAssertEqual(ExtensionStatusChecker.parse(output, bundleID: bundleID), .enabled)
    }

    func testParsesDisabledLine() {
        let output = "-    com.menmapro.Interm.Finder(1.0.0)  DEF 2026-11-07 /Users/x/Applications/Interm.app"
        XCTAssertEqual(ExtensionStatusChecker.parse(output, bundleID: bundleID), .disabled)
    }

    func testMissingBundleMeansNotRegistered() {
        let output = "+    com.aone.keka.KekaFinderIntegration(1.6.5)  ABC"
        XCTAssertEqual(ExtensionStatusChecker.parse(output, bundleID: bundleID), .notRegistered)
    }

    func testEmptyOutputMeansNotRegistered() {
        XCTAssertEqual(ExtensionStatusChecker.parse("", bundleID: bundleID), .notRegistered)
    }

    func testCheckerUsesPluginkitAndParsesResult() {
        let runner = FakeCommandRunner(result: CommandResult(
            status: 0,
            stdout: "+    com.menmapro.Interm.Finder(1.0.0)  DEF  /Applications/Interm.app\n",
            stderr: ""
        ))
        let checker = ExtensionStatusChecker(runner: runner, bundleID: bundleID)
        XCTAssertEqual(checker.currentState(), .enabled)
        XCTAssertEqual(runner.invocations.first?.0, "/usr/bin/pluginkit")
        XCTAssertEqual(runner.invocations.first?.1, ["-m", "-A", "-v", "-p", "com.apple.FinderSync"])
    }

    func testCheckerReportsUnknownWhenPluginkitFails() {
        let runner = FakeCommandRunner(result: CommandResult(status: 1, stdout: "", stderr: "nope"))
        XCTAssertEqual(ExtensionStatusChecker(runner: runner, bundleID: bundleID).currentState(), .unknown)
    }
}

final class ExtensionMenuModelTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
    private let project = URL(fileURLWithPath: "/Users/example/project", isDirectory: true)
    private let file = URL(fileURLWithPath: "/Users/example/project/README.md")

    private var isDirectory: (URL) -> Bool {
        { url in url.path != self.file.path }
    }

    func testContainerMenuUsesTargetedURL() {
        let entries = ExtensionMenuModel.entries(
            kind: .contextualForContainer,
            targetedURL: project,
            selectedURLs: [],
            isDirectory: isDirectory,
            fallbackDirectory: home
        )
        XCTAssertEqual(entries, [ExtensionMenuEntry(tag: 0, title: ExtensionMenuModel.currentFolderTitle, directory: project)])
    }

    func testContainerMenuFallsBackWhenTargetedIsNil() {
        let entries = ExtensionMenuModel.entries(
            kind: .contextualForContainer,
            targetedURL: nil,
            selectedURLs: [],
            isDirectory: isDirectory,
            fallbackDirectory: home
        )
        XCTAssertEqual(entries.first?.directory, home)
    }

    func testItemsMenuWithSingleFileUsesParentDirectory() {
        let entries = ExtensionMenuModel.entries(
            kind: .contextualForItems,
            targetedURL: project,
            selectedURLs: [file],
            isDirectory: isDirectory,
            fallbackDirectory: home
        )
        XCTAssertEqual(entries.first?.directory, project)
        XCTAssertEqual(entries.first?.title, ExtensionMenuModel.selectedItemTitle)
    }

    func testItemsMenuWithSingleDirectoryUsesItDirectly() {
        let sub = URL(fileURLWithPath: "/Users/example/project/sub", isDirectory: true)
        let entries = ExtensionMenuModel.entries(
            kind: .contextualForItems,
            targetedURL: project,
            selectedURLs: [sub],
            isDirectory: isDirectory,
            fallbackDirectory: home
        )
        XCTAssertEqual(entries.first?.directory, sub)
    }

    func testItemsMenuWithMultipleSelectionUsesContainer() {
        let other = URL(fileURLWithPath: "/Users/example/project/other.md")
        let entries = ExtensionMenuModel.entries(
            kind: .contextualForItems,
            targetedURL: project,
            selectedURLs: [file, other],
            isDirectory: isDirectory,
            fallbackDirectory: home
        )
        XCTAssertEqual(entries.first?.directory, project)
    }

    func testToolbarMenuUsesTargetedURLEvenWithoutSelection() {
        let entries = ExtensionMenuModel.entries(
            kind: .toolbar,
            targetedURL: project,
            selectedURLs: [],
            isDirectory: isDirectory,
            fallbackDirectory: home
        )
        XCTAssertEqual(entries.first?.directory, project)
        XCTAssertEqual(entries.first?.title, ExtensionMenuModel.currentFolderTitle)
    }

    // MARK: - 动作解析

    func testResolvePrefersMenuCache() {
        let targeted = URL(fileURLWithPath: "/Users/example/other", isDirectory: true)
        let resolution = ExtensionMenuModel.resolve(
            tag: 0,
            cache: [0: project],
            representedObject: "/Users/example/stale",
            targetedURL: targeted,
            selectedURLs: [],
            isDirectory: isDirectory,
            fallbackDirectory: home
        )
        XCTAssertEqual(resolution.directory, project)
        XCTAssertEqual(resolution.source, "cache")
    }

    func testResolvePrefersTargetedURLWhenCacheOnlyHoldsFallback() {
        let resolution = ExtensionMenuModel.resolve(
            tag: 0,
            cache: [0: home],
            representedObject: nil,
            targetedURL: project,
            selectedURLs: [],
            isDirectory: isDirectory,
            fallbackDirectory: home
        )
        XCTAssertEqual(resolution.directory, project)
        XCTAssertEqual(resolution.source, "targeted")
    }

    func testResolveFallsBackToRepresentedObjectString() {
        let resolution = ExtensionMenuModel.resolve(
            tag: 7,
            cache: [:],
            representedObject: project.path,
            targetedURL: nil,
            selectedURLs: [],
            isDirectory: isDirectory,
            fallbackDirectory: home
        )
        XCTAssertEqual(resolution.directory.path, project.path)
        XCTAssertEqual(resolution.source, "representedObject")
    }

    func testResolveFallsBackToRepresentedObjectURL() {
        let resolution = ExtensionMenuModel.resolve(
            tag: 7,
            cache: [:],
            representedObject: project as NSURL,
            targetedURL: nil,
            selectedURLs: [],
            isDirectory: isDirectory,
            fallbackDirectory: home
        )
        XCTAssertEqual(resolution.directory.path, project.path)
        XCTAssertEqual(resolution.source, "representedObject")
    }

    func testResolveFallsBackToTargetedURL() {
        let resolution = ExtensionMenuModel.resolve(
            tag: -1,
            cache: [:],
            representedObject: nil,
            targetedURL: project,
            selectedURLs: [file],
            isDirectory: isDirectory,
            fallbackDirectory: home
        )
        XCTAssertEqual(resolution.directory, project)
        XCTAssertEqual(resolution.source, "targeted")
    }

    func testResolveFallsBackToSelection() {
        let resolution = ExtensionMenuModel.resolve(
            tag: -1,
            cache: [:],
            representedObject: nil,
            targetedURL: nil,
            selectedURLs: [file],
            isDirectory: isDirectory,
            fallbackDirectory: home
        )
        XCTAssertEqual(resolution.directory, project)
        XCTAssertEqual(resolution.source, "selection")
    }

    func testResolveFallsBackToHome() {
        let resolution = ExtensionMenuModel.resolve(
            tag: -1,
            cache: [:],
            representedObject: nil,
            targetedURL: nil,
            selectedURLs: [],
            isDirectory: isDirectory,
            fallbackDirectory: home
        )
        XCTAssertEqual(resolution.directory, home)
        XCTAssertEqual(resolution.source, "fallback")
    }

    func testSidebarMenuIsEmpty() {
        let entries = ExtensionMenuModel.entries(
            kind: .contextualForSidebar,
            targetedURL: project,
            selectedURLs: [project],
            isDirectory: isDirectory,
            fallbackDirectory: home
        )
        XCTAssertTrue(entries.isEmpty)
    }
}

final class PreferencesTests: XCTestCase {
    func testDefaults() {
        let preferences = Preferences(store: MemoryStore())
        XCTAssertEqual(preferences.terminalPresetID, "terminal")
        XCTAssertEqual(preferences.customApplicationPath, "")
        XCTAssertTrue(preferences.keepRunning)
        XCTAssertFalse(preferences.hasCompletedOnboarding)
        XCTAssertNil(preferences.lastUsedDirectory)
    }

    func testUnknownStoredPresetFallsBackToDefault() {
        let store = MemoryStore([Preferences.Key.terminalPreset: "gone"])
        XCTAssertEqual(Preferences(store: store).terminalPresetID, "terminal")
    }

    func testWritesAreReadable() {
        let store = MemoryStore()
        var preferences = Preferences(store: store)
        preferences.terminalPresetID = "iterm2"
        preferences.customArguments = "--x"
        preferences.keepRunning = false
        preferences.lastUsedDirectory = "/tmp"

        let reloaded = Preferences(store: store)
        XCTAssertEqual(reloaded.terminalPresetID, "iterm2")
        XCTAssertEqual(reloaded.customArguments, "--x")
        XCTAssertFalse(reloaded.keepRunning)
        XCTAssertEqual(reloaded.lastUsedDirectory, "/tmp")
    }

    func testPresetLookupMatchesStoredID() {
        let store = MemoryStore([Preferences.Key.terminalPreset: "kitty"])
        XCTAssertEqual(Preferences(store: store).preset.id, "kitty")
    }
}
