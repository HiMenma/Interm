import Foundation
import os

/// 统一日志入口。
///
/// 扩展跑在独立进程里，`print` 不会出现在任何控制台，必须用 os_log；
/// 排查时：
///   log show --last 5m --info --predicate 'subsystem == "com.menmapro.Interm"'
public enum Log {
    public static let core = Logger(subsystem: IntermIdentity.logSubsystem, category: "core")
    public static let app = Logger(subsystem: IntermIdentity.logSubsystem, category: "app")
    public static let finder = Logger(subsystem: IntermIdentity.logSubsystem, category: "finder")
}
