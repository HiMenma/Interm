SHELL := /bin/bash
.PHONY: all build app test icons install install-system uninstall selftest smoke dist screenshots clean

VERSION ?= 1.0.0
BUILD_NUMBER ?= $(shell date +%Y%m%d%H%M)

all: build

## 编译并组装 dist/Interm.app
build: app

app:
	./Scripts/build.sh

## 单元测试（不需要 GUI）
test:
	swift test

## 只重画图标（会覆盖 Bundle/ 里已提交的成品图标）
icons:
	swift Scripts/make-icons.swift

## 安装到 ~/Applications 并注册扩展
install: build
	./Scripts/install.sh

## 安装到 /Applications（可能触发「App 管理」授权）
install-system: build
	./Scripts/install.sh --system

uninstall:
	./Scripts/uninstall.sh

## 结构 + 运行时自检
selftest: build
	./Scripts/selftest.sh

## 不开窗口地验证一次路径解析与终端选择
smoke: build
	dist/Interm.app/Contents/MacOS/Interm --open-at /tmp --dry-run

## 抓 README 用的窗口截图（需要「屏幕录制」权限）
screenshots: build
	./Scripts/capture-screenshots.sh

## 打包发布资产（zip + sha256）
dist:
	VERSION=$(VERSION) BUILD_NUMBER=$(BUILD_NUMBER) ./Scripts/dist.sh

clean:
	rm -rf .build dist
	rm -rf Bundle/Interm.iconset
