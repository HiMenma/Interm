import Foundation
@testable import IntermCore

/// 用内存里的路径集合冒充文件系统。
final class FakeProbe: FileSystemProbing {
    private(set) var directories: Set<String>
    private(set) var files: Set<String>

    init(directories: [String] = [], files: [String] = []) {
        self.directories = Set(directories)
        self.files = Set(files)
    }

    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        if directories.contains(path) {
            isDirectory?.pointee = true
            return true
        }
        if files.contains(path) {
            isDirectory?.pointee = false
            return true
        }
        isDirectory?.pointee = false
        return false
    }
}

/// 记录被调用的打开动作。
final class MockOpener: WorkspaceOpening {
    struct FolderCall: Equatable {
        let directory: String
        let application: String
    }

    struct ExecutableCall: Equatable {
        let executable: String
        let arguments: [String]
        let workingDirectory: String
    }

    private(set) var folderCalls: [FolderCall] = []
    private(set) var executableCalls: [ExecutableCall] = []
    var failure: TerminalLaunchError?

    func openFolderDocument(_ directory: URL, using application: URL) throws {
        if let failure { throw failure }
        folderCalls.append(FolderCall(directory: directory.path, application: application.path))
    }

    func launchExecutable(_ executable: URL, arguments: [String], workingDirectory: URL) throws {
        if let failure { throw failure }
        executableCalls.append(ExecutableCall(
            executable: executable.path,
            arguments: arguments,
            workingDirectory: workingDirectory.path
        ))
    }
}

final class MockAppleScriptRunner: AppleScriptRunning {
    enum Response {
        case success(String)
        case failure(code: Int, message: String)
    }

    var responses: [Response]
    private(set) var invokedCount = 0

    init(responses: [Response]) {
        self.responses = responses
    }

    func run(_ source: String) -> Result<String, AppleScriptFailure> {
        invokedCount += 1
        guard !responses.isEmpty else { return .success("") }
        let response = responses.removeFirst()
        switch response {
        case .success(let output):
            return .success(output)
        case .failure(let code, let message):
            return .failure(.executionFailed(code: code, message: message))
        }
    }
}

final class MemoryStore: KeyValueStoring {
    private var values: [String: Any] = [:]

    init(_ initial: [String: Any] = [:]) {
        values = initial
    }

    func object(forKey defaultName: String) -> Any? { values[defaultName] }
    func string(forKey defaultName: String) -> String? { values[defaultName] as? String }
    func bool(forKey defaultName: String) -> Bool { values[defaultName] as? Bool ?? false }
    func set(_ value: Any?, forKey defaultName: String) {
        if let value {
            values[defaultName] = value
        } else {
            values.removeValue(forKey: defaultName)
        }
    }
}

final class FakeCommandRunner: CommandRunning {
    var result: CommandResult
    private(set) var invocations: [(String, [String])] = []

    init(result: CommandResult) {
        self.result = result
    }

    func run(_ executable: String, arguments: [String]) -> CommandResult {
        invocations.append((executable, arguments))
        return result
    }
}
