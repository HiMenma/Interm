import Foundation

/// 抽象 UserDefaults，便于单测。
public protocol KeyValueStoring: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func string(forKey defaultName: String) -> String?
    func bool(forKey defaultName: String) -> Bool
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: KeyValueStoring {}

/// 用户偏好。
///
/// 只存在宿主 App 里；FinderSync 扩展不读设置——它只负责把路径转交给宿主，
/// 由宿主统一决定用哪个终端，避免两份配置漂移。
public struct Preferences {
    public enum Key {
        public static let terminalPreset = "terminal.preset"
        public static let customApplicationPath = "terminal.custom.applicationPath"
        public static let customArguments = "terminal.custom.arguments"
        public static let keepRunning = "app.keepRunning"
        public static let hasCompletedOnboarding = "app.hasCompletedOnboarding"
        public static let lastUsedDirectory = "app.lastUsedDirectory"
    }

    private let store: KeyValueStoring

    public init(store: KeyValueStoring = UserDefaults.standard) {
        self.store = store
    }

    public var terminalPresetID: String {
        get {
            let stored = store.string(forKey: Key.terminalPreset)
            guard let stored, TerminalCatalog.preset(withID: stored) != nil else {
                return TerminalCatalog.defaultID
            }
            return stored
        }
        nonmutating set { store.set(newValue, forKey: Key.terminalPreset) }
    }

    public var customApplicationPath: String {
        get { store.string(forKey: Key.customApplicationPath) ?? "" }
        nonmutating set { store.set(newValue, forKey: Key.customApplicationPath) }
    }

    public var customArguments: String {
        get { store.string(forKey: Key.customArguments) ?? "" }
        nonmutating set { store.set(newValue, forKey: Key.customArguments) }
    }

    public var keepRunning: Bool {
        get {
            guard store.object(forKey: Key.keepRunning) != nil else { return true }
            return store.bool(forKey: Key.keepRunning)
        }
        nonmutating set { store.set(newValue, forKey: Key.keepRunning) }
    }

    public var hasCompletedOnboarding: Bool {
        get { store.bool(forKey: Key.hasCompletedOnboarding) }
        nonmutating set { store.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    public var lastUsedDirectory: String? {
        get { store.string(forKey: Key.lastUsedDirectory) }
        nonmutating set { store.set(newValue, forKey: Key.lastUsedDirectory) }
    }

    /// 当前选择的预设对象。
    public var preset: TerminalPreset {
        TerminalCatalog.preset(withID: terminalPresetID) ?? TerminalCatalog.terminal
    }
}
