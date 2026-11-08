import XCTest
@testable import IntermCore

final class IntermURLTests: XCTestCase {
    func testRoundTripKeepsAwkwardCharacters() throws {
        let directory = URL(fileURLWithPath: "/tmp/Interm 自检/引号 'it' & 100%/子目录", isDirectory: true)
        let request = IntermOpenRequest(directory: directory, terminalID: "iterm2")

        let url = try XCTUnwrap(IntermURL.make(from: request))
        XCTAssertEqual(url.scheme, "interm")
        XCTAssertEqual(url.host, "open")

        let parsed = try IntermURL.parse(url)
        XCTAssertEqual(parsed.directory.path, directory.path)
        XCTAssertEqual(parsed.terminalID, "iterm2")
    }

    func testRoundTripWithoutTerminal() throws {
        let directory = URL(fileURLWithPath: "/Users/example/项目", isDirectory: true)
        let url = try XCTUnwrap(IntermURL.make(from: IntermOpenRequest(directory: directory)))
        let parsed = try IntermURL.parse(url)
        XCTAssertEqual(parsed.directory.path, directory.path)
        XCTAssertNil(parsed.terminalID)
    }

    func testParseAcceptsFileURLPayload() throws {
        let url = try XCTUnwrap(URL(string: "interm://open?path=file%3A%2F%2F%2Ftmp%2Fabc"))
        let parsed = try IntermURL.parse(url)
        XCTAssertEqual(parsed.directory.path, "/tmp/abc")
    }

    func testParseRejectsForeignScheme() {
        let url = URL(string: "https://example.com/open?path=/tmp")!
        XCTAssertThrowsError(try IntermURL.parse(url)) { error in
            XCTAssertEqual(error as? IntermURL.ParseFailure, .notIntermScheme("https"))
        }
    }

    func testParseRejectsUnknownAction() {
        let url = URL(string: "interm://settings?path=/tmp")!
        XCTAssertThrowsError(try IntermURL.parse(url)) { error in
            XCTAssertEqual(error as? IntermURL.ParseFailure, .unsupportedAction("settings"))
        }
    }

    func testParseRejectsMissingPath() {
        let url = URL(string: "interm://open?terminal=iterm2")!
        XCTAssertThrowsError(try IntermURL.parse(url)) { error in
            XCTAssertEqual(error as? IntermURL.ParseFailure, .missingPath)
        }
    }

    func testParseRejectsRelativePath() {
        let url = URL(string: "interm://open?path=relative%2Fdir")!
        XCTAssertThrowsError(try IntermURL.parse(url)) { error in
            XCTAssertEqual(error as? IntermURL.ParseFailure, .invalidPath("relative/dir"))
        }
    }

    func testParseRejectsNulByte() {
        let url = URL(string: "interm://open?path=%2Ftmp%00evil")!
        XCTAssertThrowsError(try IntermURL.parse(url)) { error in
            guard case .invalidPath = (error as? IntermURL.ParseFailure) else {
                return XCTFail("expected invalidPath, got \(error)")
            }
        }
    }

    func testParseAcceptsSchemeWithoutHostAndLeadingSlash() throws {
        let url = URL(string: "interm:/open?path=%2Ftmp")!
        let parsed = try IntermURL.parse(url)
        XCTAssertEqual(parsed.directory.path, "/tmp")
    }

    func testParseAcceptsSchemeWithoutHost() throws {
        let url = URL(string: "interm:open?path=%2Ftmp")!
        let parsed = try IntermURL.parse(url)
        XCTAssertEqual(parsed.directory.path, "/tmp")
    }
}
