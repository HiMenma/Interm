import Foundation

/// 全项目共用的一组标识符与常量。
///
/// 这些值同时出现在 Info.plist、构建脚本和运行时代码里，改动时必须一起改，
/// 因此集中放在这里，避免字符串散落。
public enum IntermIdentity {
    /// 宿主 App 的 bundle identifier。
    public static let appBundleID = "com.menmapro.Interm"
    /// FinderSync 扩展的 bundle identifier。
    public static let extensionBundleID = "com.menmapro.Interm.Finder"
    /// 自定义 URL scheme，扩展用它把目录交给宿主。
    public static let urlScheme = "interm"
    /// `NSServices` 里声明的方法名。
    public static let serviceMessage = "openInTerminalHere"
    /// 统一日志子系统。
    public static let logSubsystem = "com.menmapro.Interm"
    /// 展示名。
    public static let displayName = "Interm"
    /// 版本号（构建脚本会用 MARKETING_VERSION 覆盖 Info.plist 中的值）。
    public static let fallbackVersion = "0.0.0-dev"
}
