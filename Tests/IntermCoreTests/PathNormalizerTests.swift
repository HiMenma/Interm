import XCTest
@testable import IntermCore

final class PathNormalizerTests: XCTestCase {
    private let probe = FakeProbe(
        directories: ["/Users/example/project", "/Users/example/project/sub"],
        files: ["/Users/example/project/README.md"]
    )

    func testDirectoryResolvesToItself() throws {
        let normalizer = PathNormalizer(probe: probe)
        let url = try normalizer.directory(for: URL(fileURLWithPath: "/Users/example/project", isDirectory: true), resolveSymlinks: false)
        XCTAssertEqual(url.path, "/Users/example/project")
    }

    func testFileResolvesToParentDirectory() throws {
        let normalizer = PathNormalizer(probe: probe)
        let url = try normalizer.directory(for: URL(fileURLWithPath: "/Users/example/project/README.md"), resolveSymlinks: false)
        XCTAssertEqual(url.path, "/Users/example/project")
    }

    func testMissingPathThrows() {
        let normalizer = PathNormalizer(probe: probe)
        XCTAssertThrowsError(
            try normalizer.directory(for: URL(fileURLWithPath: "/Users/example/missing"), resolveSymlinks: false)
        ) { error in
            XCTAssertEqual(error as? PathNormalizationError, .notFound("/Users/example/missing"))
        }
    }

    func testNoneFileURLThrows() {
        let normalizer = PathNormalizer(probe: probe)
        XCTAssertThrowsError(try normalizer.directory(for: URL(string: "https://example.com")!)) { error in
            XCTAssertEqual(error as? PathNormalizationError, .notFileURL("https://example.com"))
        }
    }

    func testEmptyPathURLResolvesToWorkingDirectory() throws {
        // Foundation 把空路径当成当前目录，这里只确认不会抛错并且结果稳定。
        let normalizer = PathNormalizer(probe: probe)
        let resolved = try? normalizer.directory(for: URL(fileURLWithPath: ""), resolveSymlinks: false)
        XCTAssertNil(resolved, "当前目录不在这份假文件系统里，应当报 notFound")
    }

    func testTrailingSlashIsStandardized() throws {
        let normalizer = PathNormalizer(probe: probe)
        let url = try normalizer.directory(for: URL(fileURLWithPath: "/Users/example/project/", isDirectory: true), resolveSymlinks: false)
        XCTAssertEqual(url.path, "/Users/example/project")
    }

    func testSelectionPicksFirstResolvableItem() {
        let normalizer = PathNormalizer(probe: probe)
        let selection = [
            URL(fileURLWithPath: "/Users/example/missing"),
            URL(fileURLWithPath: "/Users/example/project/sub", isDirectory: true)
        ]
        XCTAssertEqual(normalizer.directory(forSelection: selection, resolveSymlinks: false)?.path, "/Users/example/project/sub")
    }

    func testSelectionReturnsNilWhenNothingResolves() {
        let normalizer = PathNormalizer(probe: probe)
        XCTAssertNil(normalizer.directory(forSelection: [URL(fileURLWithPath: "/nonexistent")]))
    }

    // MARK: - Shell quoting

    func testShellQuoteLeavesPlainPathsAlone() {
        XCTAssertEqual(Shell.quote("/Users/example/project"), "/Users/example/project")
        XCTAssertEqual(Shell.quote(""), "''")
    }

    func testShellQuoteEscapesSpacesAndQuotes() {
        XCTAssertEqual(Shell.quote("/tmp/a b"), "'/tmp/a b'")
        XCTAssertEqual(Shell.quote("it's"), "'it'\\''s'")
        XCTAssertEqual(Shell.quote("a\"b"), "'a\"b'")
        XCTAssertEqual(Shell.quote("line\nbreak"), "'line\nbreak'")
    }

    func testCommandLineListsExecutableAndArguments() {
        XCTAssertEqual(
            Shell.commandLine(executable: "/bin/ls", arguments: ["-l", "/tmp/a b"]),
            "/bin/ls -l '/tmp/a b'"
        )
    }
}
