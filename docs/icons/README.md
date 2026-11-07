# 图标素材

## 采用

**`lucide-terminal.svg`** —— [Lucide](https://lucide.dev/icons/terminal) `terminal`，lucide-static v1.70.0，ISC 许可。

几何形状（viewBox 24×24、`stroke-width=2`、圆头端点、圆角连接）：

```
M12 19h8          下划线
m4 17 6-6-6-6     提示符箭头：(4,17) → (10,11) → (4,5)
```

Interm 的 App 图标与 Finder 工具栏模板图都在 [`Scripts/make-icons.swift`](../../Scripts/make-icons.swift)
里按上述路径以 `CGPath` 重绘（`drawTerminalGlyph`），仓库里不放位图素材；
`make icons` 会一次生成 16→1024 全套 `.icns` 和 18pt 工具栏模板图。

## 候选（未采用，仅作比对）

| 文件 | 来源 | 许可 |
| --- | --- | --- |
| `tabler-terminal-2.svg`、`tabler-folder-code.svg` | [Tabler Icons](https://tabler.io/icons) | MIT |
| `bootstrap-terminal.svg` | [Bootstrap Icons](https://icons.getbootstrap.com) | MIT |
| `phosphor-terminal.svg`、`phosphor-terminal-window.svg` | [Phosphor Icons](https://phosphoricons.com) | MIT |
| `lucide-folder-code.svg` | Lucide | ISC |

对照图：

- [1-候选总览.png](1-候选总览.png) —— 7 个候选 + 旧版，底部是真实 18pt 放大 5× 的观感
- [2-套上背景的效果.png](2-套上背景的效果.png) —— 前 5 个候选套进深色渐变底
- [3-文件夹方向备选.png](3-文件夹方向备选.png) —— 「文件夹 + 代码」方向
- [4-采用后预览.png](4-采用后预览.png) —— 最终采用方案在各尺寸、Finder 工具栏、Dock 中的效果

## Lucide 许可

```
ISC License

Copyright (c) for portions of Lucide are held by Cole Bemis 2013-2022 as part of
Feather (MIT). All other copyright (c) for Lucide are held by Lucide Contributors
2022.

Permission to use, copy, modify, and/or distribute this software for any purpose
with or without fee is hereby granted, provided that the above copyright notice
and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS
OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF
THIS SOFTWARE.
```
