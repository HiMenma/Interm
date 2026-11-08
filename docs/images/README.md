# 截图

`make screenshots` 调用 [Scripts/capture-screenshots.sh](../../Scripts/capture-screenshots.sh) 生成这里的图：

```bash
make screenshots
```

做法与注意事项：

- **需要「屏幕录制」权限**（系统设置 › 隐私与安全性 › 屏幕录制），否则 `screencapture` 会失败，脚本会提示并退出 2
- 会临时打开一个 Finder 窗口、一个 Terminal 窗口（强制用 Terminal.app，不改用户的默认终端）和 Interm 设置窗口，抓完自动关掉
- 合成时只取 Finder 窗口顶部的**工具栏那一条**，不把侧边栏（个人收藏目录）拍进公开截图
- 三张原始窗口图缓存在 `$TMPDIR/interm-shots/`，`swift Scripts/capture-screenshots.swift --compose-only` 可以在不重新抓图的情况下调整排版

| 文件 | 内容 |
| --- | --- |
| `screenshot-toolbar-terminal.png` | Finder 工具栏（真实截图裁出的工具栏条）+ 它在该目录打开的终端 |
| `screenshot-settings.png` | 设置窗口：终端选择、扩展状态、诊断入口 |
| `social-preview.png` | GitHub 社交预览图（1280×640），由 `make social` 生成 |

## 社交预览图

GitHub 没有上传 social preview 的 API（官方只提供 Settings 页面上传），所以这一步要手动：

1. `make social` 生成 `docs/images/social-preview.png`
2. 仓库页 › Settings › Social preview › **Upload an image**，选这个文件

图是 1280×640、不到 1 MB，满足 GitHub 的要求。
