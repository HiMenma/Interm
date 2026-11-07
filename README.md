# Interm

One click in Finder opens a terminal **in the current folder**. Native Swift (AppKit + SwiftUI + FinderSync), no third-party dependencies.

**English** · [简体中文](README.zh-CN.md)

```
Finder toolbar icon  ──click──▶  terminal opens already cd'd into that window's folder
```

## Features

- **One click**: drag `Interm.app` into the Finder toolbar; a single click opens a terminal at the front Finder window's folder.
- **Native context menu**: the bundled FinderSync extension adds “Open in Terminal” to right-click menus (window background or selection).
- **Services menu**: Finder › Services › Open in Terminal (default `⌃⌥T`, rebindable).
- **Scriptable**: `open "interm://open?path=/tmp"`, `Interm --open-at <dir>`.
- **Multiple terminals**: Terminal (default), iTerm2, Warp, kitty, WezTerm, Alacritty, or a custom app + argument template.
- **Diagnosable**: `--selftest`, plus a settings window that shows extension state, the last opened folder, and a one-click self-test.

## Requirements

- macOS 14 or newer (developed and verified on macOS 27.2 / Xcode 27.2 / Swift 6.4)
- Builds for the **current architecture only** (arm64 here); not notarized, not distributed on the App Store

## Install

```bash
git clone <repo> Interm && cd Interm

make build       # compile and assemble dist/Interm.app
make selftest    # structure + self-test (optional)
make install     # install to ~/Applications and register the extension
```

Then do two things:

1. **Put the icon in the Finder toolbar** (recommended one-click entry)
   Open the Applications folder, hold `⌘` and drag `Interm.app` onto a Finder window's toolbar.
   After that, **one click** on that icon opens a terminal in the current folder.

2. **Enable the Finder extension** (context menu + toolbar popup)
   System Settings › General › Login Items & Extensions › Extensions › Finder Extensions, tick Interm;
   or open Interm's settings window and click “Enable / Manage Extension…”.

> The first click on the toolbar icon asks “Interm wants to control Finder”. That is the only way to read which folder the front window shows; allow it once.
> If you decline, that click falls back to the Desktop and shows a dialog telling you where to change it.

To install into `/Applications` instead: `make install-system` (may trigger the App Management prompt).

## Usage

| Entry point | Action | Notes |
| --- | --- | --- |
| Finder toolbar | Click the Interm icon | Opens a terminal in the front Finder window's folder |
| Context menu | Right-click a window background or selection › Open in Terminal | Provided by the FinderSync extension |
| Services | Finder › Services › Open in Terminal | `⌃⌥T` by default; rebindable in System Settings |
| URL | `open "interm://open?path=/tmp"` | Optionally add `&terminal=iterm2` |
| CLI | `Interm --open-at ~/code` | Add `--dry-run` to print the command instead of running it |
| Menu bar | Menu bar icon › Open Current Folder in Terminal | Same as a toolbar click |

The settings window (menu bar icon › Settings…) lets you switch terminals, fill in a custom argument template, inspect extension state and run the self-test.

## Supported terminals

| Terminal | How it is opened | Status |
| --- | --- | --- |
| Terminal | Folder handed to LaunchServices as a document | Verified locally |
| iTerm2 | Same | Not installed; implemented per its docs |
| Warp | Same | Not installed; implemented per its docs |
| kitty | `kitty --directory <dir>` | Not installed |
| WezTerm | `wezterm start --cwd <dir>` | Not installed |
| Alacritty | `alacritty --working-directory <dir>` | Not installed |
| Custom | App path + argument template (`{dir}` placeholder) | Verified locally with a test app |

Only installed terminals are listed; on another machine the setting falls back to Terminal.

## Permissions

| Permission | Why it is needed | Avoidable? |
| --- | --- | --- |
| Automation (control Finder) | Read the front window's folder on a toolbar click | No — this is the only system-provided route |
| Accessibility / Full Disk Access | Not needed | — |
| Extension sandbox | Hard requirement for FinderSync extensions | No — the extension only reads the path and forwards it; the host app launches the terminal |

Interm makes no network requests and never uploads paths. Everything happens locally.

## How it works (30-second version)

```
Toolbar click → host app (not sandboxed) ──AppleScript──▶ Finder: front window folder
                                          └──▶ NSWorkspace hands the folder to the terminal as a document
                                               (the new window starts in that folder)

Context menu  → FinderSync extension (sandboxed) ──interm://open?path=…──▶ host app ──▶ same as above
```

Design notes, SDK evidence and the pitfalls we hit (FinderSync toolbar buttons can only open a menu; the extension entry point must be `NSExtensionMain`) are in [docs/DESIGN.md](docs/DESIGN.md) — currently written in Chinese.

## Commands

```bash
make build        # compile + assemble dist/Interm.app
make test         # unit tests (no GUI needed)
make install      # install to ~/Applications
make uninstall    # uninstall (unregisters the extension before deleting files)
make selftest     # structure / signature / registration / runtime self-test
make smoke        # verify path resolution without opening a window
make icons        # regenerate the icons
make clean
```

Troubleshooting: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) (Chinese).

## Development

```
Sources/IntermCore/    UI-free logic (URL scheme, path normalisation, presets, launcher, preferences, menu model)
Sources/Interm/        Host app (CLI, URL, Services, menu bar, SwiftUI settings)
Sources/IntermFinder/  FinderSync extension (sandboxed; forwards paths only)
Tests/IntermCoreTests/ 70 unit tests
Scripts/               build, sign, install, icons, self-test
Bundle/                Info.plist, entitlements, generated icons
```

`swift build` produces just the two executables; `Scripts/build.sh` assembles the `.app`/`.appex`, writes the Info.plists, signs from the inside out with an ad-hoc identity, and verifies the result.

## Limitations

- No Developer ID certificate: the build is ad-hoc signed and not notarized, so it is meant for local/personal use. Distributing it to others requires your own signing and notarization.
- Builds for the current architecture only; no universal binary.
- A FinderSync toolbar item can only open a menu (the SDK has no `toolbarItemClicked`), so the true one-click button is the app icon you drag into the toolbar.

## Icon

The app icon and the Finder toolbar icon are based on [Lucide](https://lucide.dev/icons/terminal)'s `terminal` icon (ISC licence), redrawn as `CGPath` from the original geometry in [Scripts/make-icons.swift](Scripts/make-icons.swift) — no bitmap assets in the repository.
Assets and licence text: [docs/icons/README.md](docs/icons/README.md).

## License

MIT — see [LICENSE](LICENSE).
