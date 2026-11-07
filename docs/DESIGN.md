# 设计说明

本文记录 Interm 的架构与关键决策，尤其是那些「看起来可以更简单、但实测不行」的地方。
证据来源要么是 SDK 头文件，要么是本机实测（macOS 27.2 / Xcode 27.2）。

## 1. 目标

在 Finder 上放一个按钮，单击后在**当前目录**打开终端；用 Swift 原生实现，不装第三方运行时。

「当前目录」= 当前 Finder 窗口所在的目录。这个信息只有 Finder 自己知道，因此所有设计的核心问题变成：
**如何以最小代价、最少权限，把「Finder 当前窗口的目录」拿给终端。**

## 2. 三条入口、一条管线

```
① 工具栏图标（⌘ 拖入的 App 图标）
     单击 → LaunchServices 打开 App → applicationShouldHandleReopen / didFinishLaunching
          → AppleScript 问 Finder：target of front window
                                    │
② FinderSync 扩展（沙盒）           │
     右键菜单 / 工具栏下拉 → interm://open?path=… → 宿主 application(_:open:)
                                    │
③ 服务 / CLI / URL                   │
     Finder › 服务 › 在终端中打开 / Interm --open-at … / open interm://…
                                    ▼
                         OpenRequest(directory, terminal?)
                                    ▼
                         PathNormalizer（文件→父目录、去尾斜杠、解析符号链接）
                                    ▼
                         Preferences.terminal（预设 / 自定义）
                                    ▼
                         TerminalLauncher.resolve → ResolvedLaunch
                                    ▼
            NSWorkspace 文档方式 / Process 直接执行 / 自定义模板
```

进程与权限边界：

| 进程 | 沙盒 | 职责 | 权限 |
| --- | --- | --- | --- |
| `Interm`（宿主，LSUIElement） | 否 | 读 Finder 目录、启动终端、设置界面、状态栏 | 自动化（控制访达） |
| `IntermFinder`（appex） | 是（pkd 要求） | 只把 Finder 上下文折算成菜单项，再拼 URL 交给宿主 | 无 |
| 终端 App | 否 | 在指定目录开窗口 | 无 |

**为什么扩展不自己启动终端**：沙盒内 fork 出来的进程会继承 seatbelt，终端/子进程会被静默拒绝
（同类实现踩坑记录见 [mac-finder-menu](https://github.com/sherman-yang/mac-finder-menu)）。
宿主 App 不沙盒，由它执行真实的启动动作最稳。

**为什么用 URL scheme 而不是 App Group / spool 文件**：`NSWorkspace.open(URL)` 在沙盒里允许，
不需要任何额外 entitlement；App Group 需要真实 Team ID，spool 文件需要
`temporary-exception.files.home-relative-path` 例外。URL 方案零配置、可被用户/脚本复用。

## 3. 关键事实与决策

### 3.1 FinderSync 的「按钮」其实是菜单按钮

`FinderSync.framework/Headers/FinderSync.h`（macOS SDK 27.2）里 `FIFinderSync` 只有：

```objc
@property (copy, readonly) NSString *toolbarItemName;
@property (copy, readonly) NSImage  *toolbarItemImage;
@property (copy, readonly) NSString *toolbarItemToolTip;
```

**没有 `toolbarItemClicked:`**（SDK 与框架二进制里都搜不到）。工具栏项只能通过
`menuForMenuKind:` 返回菜单，点击时弹出下拉菜单（`FIMenuKindToolbarItemMenu`）。

决策：
* 单键路径 = **⌘ 把 `.app` 图标拖进 Finder 工具栏**，点击即启动 App；
* 扩展的工具栏项作为「原生一点的补充」，是「按钮 → 菜单项」两步。

### 3.2 `targetedURL` 只在菜单回调里可靠

头文件注释原文：这些值只在 `menuForMenuKind:` 或其菜单动作里有效；托管目录之外（例如点工具栏按钮）返回 `nil`。

决策：`directoryURLs = ["/"]`（监视整个文件系统），让所有本地路径都落在托管范围内；
仍然对 `nil` 做三级兜底：`targetedURL` → `selectedItemURLs.first` → `$HOME`。

### 3.3 扩展的入口点必须是 `_NSExtensionMain`

Xcode 的 app extension 用 `LD_ENTRY_POINT = _NSExtensionMain` 链接，二进制里**没有** Swift 的 `main`。
如果改用 Swift `main()` 去调 `NSExtensionMain()`（看起来等价），进程会在
`ExtensionFoundation.EXExtensionMain + 3900` 处 `brk #0x1`（EXC_BREAKPOINT），Finder 里表现为
「扩展已启用但反复崩溃」。

实测对照：

| 做法 | 结果 |
| --- | --- |
| `main.swift` 里 `exit(NSExtensionMain())` | `brk #0x1`，扩展进程秒崩 |
| `-Xlinker -e -Xlinker _NSExtensionMain`，无顶层代码 | 正常运行，类被实例化，菜单/工具栏可用 |

因此 `Package.swift` 里给 `IntermFinder` 加了 linkerSettings，`Scripts/build.sh` 会反汇编
`_main` 做守卫：一旦发现 `_main` 里有函数调用（意味着退回 Swift main），构建直接失败。

### 3.4 菜单动作拿不到 `representedObject`

Finder 会先序列化扩展返回的 `NSMenu`，再回调动作。实测结果：动作确实被调用到扩展进程，
但 `sender.representedObject` 已经是 `nil`（日志里表现为「点了没反应」）。

做法：
* 把目录写进**进程内缓存**，键是 `NSMenuItem.tag`（tag 是 NSMenuItem 自己的整型属性，能活过序列化）；
* 同时把路径字符串再塞一份到 `representedObject`（双重保险）；
* 都拿不到时依次回退 `targetedURL()`（官方文档支持在菜单动作里调用）→ 选中项 → 桌面。
* 如果构建菜单时 `targetedURL` 就是 nil（工具栏按钮偶尔如此），缓存里只剩兜底目录，
  此时**优先**再问一次 `targetedURL()`，避免把「上次的兜底」当成用户眼前的文件夹。

### 3.5 URL 唤起时 `application(_:open:)` 先于 `applicationDidFinishLaunching`

macOS 27 实测：通过 `interm://` 启动 App 时，URL 事件在 `applicationDidFinishLaunching` **之前**到达。
早期实现里后者会再排一个「工具栏点击」定时器，结果每次扩展菜单点击都会多开一个前台目录的窗口。
现在用 `didReceiveOpenEvent` 标记：URL 唤起过的启动不再探测 Finder。

### 3.6 打开终端用「文件夹当文档」而不是 AppleScript

`Terminal.app/Contents/Info.plist` 声明了 `public.directory` 文档类型，因此：

```swift
NSWorkspace.shared.open([directory], withApplicationAt: terminalApp, configuration: config)
```

就会让终端新建窗口并 `cd` 到该目录——不需要向终端发 Apple Events，也就不需要第二份自动化授权。
只有「读 Finder 当前目录」这一步必须用 AppleScript。

### 3.7 ad-hoc 签名能满足本地 FinderSync

本机没有代码签名身份（`security find-identity` 为 0），扩展用 `codesign -s -` 签名，
entitlements 为 `app-sandbox` + `get-task-allow`（等价于 Xcode 的 “Sign to Run Locally”）。
实测 pkd 接受：`pluginkit` 显示 `+`、Finder 正常拉起扩展、`toolbarItemImage` 被读取、
`com.apple.finder.plist` 的 `FXSyncExtensionToolbarItemsAutomaticallyAdded` 里出现我们的 bundle id。

注意：要分发给别人必须换真实证书并去掉 `get-task-allow`。

### 3.8 构建方式：SwiftPM + 手工组装

Xcode 工程不是必需的：SwiftPM 产出两个 Mach-O，`Scripts/build.sh` 组装 `.app`/`.appex`、
写 Info.plist、装图标、由内向外签名、再 `codesign --verify --deep --strict`。
好处是 CI/命令行可复现，仓库里没有 `.xcodeproj` 的合并冲突。

### 3.9 图标用矢量重绘，不放位图

App 图标与工具栏模板图由 `Scripts/make-icons.swift` 现场绘制：底色是 CoreGraphics 渐变 + 圆角矩形，
字形取自 Lucide `terminal` 的路径（viewBox 24×24、stroke 2、圆头端点），按「图形宽度」等比缩放，
所以 16px 到 1024px 共用一套几何，不需要为小尺寸单独准备位图。
`iconutil` 只负责把 iconset 打包成 `.icns`。

## 4. 失败处理矩阵

| 情况 | 行为 |
| --- | --- |
| 自动化被拒（-1743） | 弹窗说明 + 深链到「隐私与安全性 › 自动化」，本次退回桌面目录 |
| Finder 没有窗口 / 停在「最近使用」 | 静默退回 `~/Desktop` |
| 选中的是文件 | 取其父目录 |
| 多选 | 取第一个能解析的 |
| 目录不存在 | 明确报错，不静默开空目录 |
| 终端未安装 | 报错并提示打开设置 |
| 自定义模板缺少 `{dir}` | 报错（否则终端不知道该去哪） |
| 300ms 内重复请求 | 去重（连点、reopen 与 URL 双触发） |
| URL 唤起后又触发「工具栏点击」 | 用 `didReceiveOpenEvent` 跳过探测，避免多开一个窗口 |
| 菜单动作丢失 `representedObject` | tag 缓存 → 路径字符串 → `targetedURL()` → 选中项 → 桌面 |
| 扩展未注册/未启用 | 设置窗口显示状态 + 一键打开扩展管理界面 |

## 5. 测试策略

* **单元测试**（63 个）：URL 生成/解析（空格、中文、引号、`%`、`&`、`file://`、非法 scheme、NUL）、
  路径归一（文件/目录/不存在/多选）、shell 引用、预设解析与参数替换、参数分词、
  AppleScript 结果映射（含重试与权限拒绝）、`pluginkit` 输出解析、菜单规则、偏好读写。
* **构建期守卫**：入口点反汇编检查、`codesign --verify --deep --strict`、Info.plist 关键键。
* **`Scripts/selftest.sh`**：产物结构、plist、签名、entitlement、无 quarantine、运行时自检、注册状态。
* **手工验收**（需要人点一下）：拖到工具栏单击、右键菜单、服务菜单、首次自动化授权。

## 6. 没走的路

| 方案 | 为什么不选 |
| --- | --- |
| Finder Quick Action（Automator `.workflow`） | 只能进右键「快速操作」，做不出工具栏按钮；`.workflow` 需要手写 Automator 文档格式 |
| 纯 AppleScript + 拖到工具栏的脚本 App | 可做，但没有右键菜单、没有设置界面，且脚本 App 仍然需要自动化授权 |
| SMAppService / 登录项常驻 | 与「点一下就走」的产品形态不符，且增加授权面 |
| App Group 共享配置 | 需要真实 Team ID；扩展本来就不需要读设置 |
| 在扩展里直接 `Process` 启动终端 | 沙盒内子进程继承 seatbelt，会被静默拒绝 |

## 7. 已知限制

- 不公证、不上架，ad-hoc 签名只适合本机；换机器需重新构建。
- 只构建当前架构。
- FinderSync 扩展的工具栏项是菜单按钮（系统限制）。
- 首次点击依赖一次「自动化」授权；拒绝后每次都要走退回逻辑。
