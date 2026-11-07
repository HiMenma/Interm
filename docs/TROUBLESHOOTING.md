# 排错手册

先看日志，大部分问题一眼就能定位：

```bash
log show --last 5m --info --predicate 'subsystem == "com.menmapro.Interm"' --style compact
```

## 1. 工具栏里点图标没反应

1. 确认 App 在跑：`pgrep -fl "Interm.app/Contents/MacOS/Interm"`；没有就 `open ~/Applications/Interm.app` 看设置窗口是否正常。
2. 看日志里有没有 `opened … source=toolbarClick`：
   - 有 → 终端启动逻辑执行了，问题在终端那边（见第 4 节）。
   - 没有 `automation denied`、也没有 `finder probe failed` → 可能 App 没收到点击（`reopen` 事件）。
     手动验证探测逻辑：`~/Applications/Interm.app/Contents/MacOS/Interm --probe-finder`。
3. 第一次点击会弹「Interm 想要控制访达」。若误点了拒绝：
   系统设置 › 隐私与安全性 › 自动化 › Interm → 勾上「访达」；
   或先退出 App 再 `tccutil reset AppleEvents com.menmapro.Interm` 触发重新询问。

## 2. 右键菜单 / 工具栏下拉按钮不出现

```bash
pluginkit -m -A -v -p com.apple.FinderSync | grep -i menmapro
```

- **没有任何输出** → 扩展没注册：
  ```bash
  pluginkit -a ~/Applications/Interm.app/Contents/PlugIns/IntermFinder.appex
  pluginkit -e use -i com.menmapro.Interm.Finder
  killall pkd; killall Finder
  ```
- **前面是 `-`** → 已注册但被关掉：系统设置 › 通用 › 登录项与扩展 › 扩展 › 访达扩展，勾选 Interm。
- **前面是 `+` 但菜单仍不出现** → Finder 没重新加载，`killall Finder` 后再开一个窗口。
  还是不行就看扩展进程是否在跑：`pgrep -fl IntermFinder`。

## 3. 扩展进程反复崩溃（spawn 循环）

特征：`pgrep` 能看到进程但马上消失，`~/Library/Logs/DiagnosticReports/IntermFinder-*.ips` 里堆了一串。

```bash
ls -t ~/Library/Logs/DiagnosticReports | grep IntermFinder | head
```

打开 `.ips`，如果调用栈是：

```
ExtensionFoundation  EXExtensionMain(_:_:) + 3900
Foundation           NSExtensionMain + 200
IntermFinder         main + …
```

说明扩展是**用 Swift `main()` 调 `NSExtensionMain()`** 的旧构建（会在 `brk` 处崩溃）。
正确构建的二进制里 `_main` 只是一句 `return 0`，入口点是 `_NSExtensionMain`：

```bash
otool -tvV ~/Applications/Interm.app/Contents/PlugIns/IntermFinder.appex/Contents/MacOS/IntermFinder | sed -n '/^_main:/,+2p'
# 期望：
# _main:
#   mov  w0, #0x0
#   ret
```

修复：重新 `make build && make install`（`Scripts/build.sh` 有守卫，这种二进制现在根本构建不出来）。

## 4. 终端打开了，但不在目标目录

- 看 `--dry-run` 输出，确认解析出来的目录与启动方式：
  ```bash
  ~/Applications/Interm.app/Contents/MacOS/Interm --open-at "/要/检查/的目录" --dry-run
  ```
- Terminal / iTerm2 / Warp 走的是「文件夹当文档」：它们在 `Info.plist` 里必须声明 `public.directory`。
  终端自身版本太老可能不支持，换 Terminal 试一次即可区分。
- kitty / WezTerm / Alacritty 走命令行参数，检查 App 内可执行文件存在：
  ```bash
  ls /Applications/kitty.app/Contents/MacOS/kitty
  ```
- 自定义模板必须包含 `{dir}`，否则会直接报错而不是打开错误目录。

## 5. 服务菜单里没有「在终端中打开」

```bash
/System/Library/CoreServices/pbs -flush
killall Finder
```

仍不显示：系统设置 › 键盘 › 键盘快捷键 › 服务，找到「在终端中打开」勾选。
服务列表是登录时缓存的，必要时注销重登。

## 6. 完全卸载 / 清理幽灵扩展

```bash
make uninstall
# 或手动
pluginkit -e ignore -i com.menmapro.Interm.Finder
pluginkit -r ~/Applications/Interm.app/Contents/PlugIns/IntermFinder.appex
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u ~/Applications/Interm.app
rm -rf ~/Applications/Interm.app
killall pkd
```

如果系统设置里还残留旧条目（例如你在多个目录构建过同一个 App）：

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump \
  | grep -B2 -A2 -i interm | grep "path:" | sort -u
# 对每个不再存在的路径：
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u <那个路径>
killall pkd; killall Finder
```

## 7. 从源码重新构建失败

| 现象 | 处理 |
| --- | --- |
| `Source files for target … should be located under …` | 不要在 `Package.swift` 里给 target 乱加 `path`，保持默认目录结构 |
| `error: IntermFinder 的 Swift main() 里出现了函数调用` | 有人把顶层代码加回了 `Sources/IntermFinder`；入口点必须交给 `-e _NSExtensionMain` |
| `codesign` 报 `resource fork, Finder information, or similar detritus not allowed` | `xattr -cr dist/Interm.app` 后重跑构建脚本（脚本里已自动处理） |
| 改了代码但行为没变 | 旧 App 还在跑：`pkill -x Interm`，然后 `make install` 会用 `ditto` 覆盖 |

## 8. 有用的诊断命令

```bash
# 版本 / 自检
~/Applications/Interm.app/Contents/MacOS/Interm --version
~/Applications/Interm.app/Contents/MacOS/Interm --selftest

# 直接问 Finder 当前目录（会触发自动化授权）
~/Applications/Interm.app/Contents/MacOS/Interm --probe-finder

# 扩展注册与状态
pluginkit -m -A -v -p com.apple.FinderSync

# Finder 是否自动加过工具栏按钮
plutil -extract FXSyncExtensionToolbarItemsAutomaticallyAdded json -o - ~/Library/Preferences/com.apple.finder.plist

# 统一日志
log stream --info --predicate 'subsystem == "com.menmapro.Interm"'
```
