SHELL := /bin/bash
.PHONY: all app test icons install install-system uninstall selftest smoke clean

all: app

## 编译并组装 dist/Interm.app
app:
	./Scripts/build.sh

## 单元测试（不需要 GUI）
test:
	swift test

## 只重画图标
icons:
	swift Scripts/make-icons.swift

## 安装到 ~/Applications 并注册扩展
install: app
	./Scripts/install.sh

## 安装到 /Applications（可能触发「App 管理」授权）
install-system: app
	./Scripts/install.sh --system

uninstall:
	./Scripts/uninstall.sh

## 结构 + 运行时自检
selftest: app
	./Scripts/selftest.sh

## 不开窗口地验证一次路径解析与终端选择
smoke: app
	dist/Interm.app/Contents/MacOS/Interm --open-at /tmp --dry-run

clean:
	rm -rf .build dist
	rm -rf Bundle/Interm.iconset Bundle/Interm.icns Bundle/IntermToolbarTemplate.png
