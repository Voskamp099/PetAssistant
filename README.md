# 总裁小助理 · PetAssistant

**简体中文** | [English](README.en.md)

一只安静待在 macOS 桌面上的小猫。点击它，查看并听取今天的 Apple Calendar 日程和 To-do list；不点击时，它就留在原地陪伴你。

![当前的小猫](Resources/cat_idle.png)

## 当前功能

- 原生 SwiftUI + AppKit 菜单栏 App，不显示 Dock 图标。
- 静态猫图，可拖动，位置会保存。
- 点击循环：日程 → To-do list → 无字幕的猫 → 日程。
- 每页只朗读一次；读完保留字幕，等待下一次点击。
- 日程时间采用 12 小时制数字 + AM/PM，使用电脑当前时区。
- 中文和英文分段朗读，英文使用英文声音；支持选择本机已安装的声音。
- 日程页根据电脑当前时间显示早晚问候。
- To-do list 支持新增、完成和删除，按日期保存在本机，跨日自动切换。
- 隐藏／显示快捷键：**Control + Option + Command + P（⌃⌥⌘P）**。
- 隐藏后再次打开 App，也会恢复猫，不自动朗读。

## 构建与启动

### 兼容性

| 平台 | 当前状态 |
|---|---|
| Apple 芯片的 Mac，macOS 14 及以上 | 当前构建目标；已在目标系统上验证 |
| Intel Mac | 尚未提供 Intel 或通用安装包，未验证 |
| macOS 13 及更早版本 | 当前构建不支持 |
| Windows / Linux | 当前版本不支持 |

需要 Xcode Command Line Tools。当前仓库提供源码构建方式，尚未发布可直接下载的安装包。

```bash
./scripts/build.sh
codesign --force --deep --sign - build/PetAssistant.app
open build/PetAssistant.app
```

直接使用 `swiftc` 编译，不使用 Swift Package Manager。`Package.swift` 是历史占位文件。

首次运行需要日历读取权限；启动只显示猫，不自动播报。权限可在 System Settings → Privacy & Security → Calendars 中管理。

## 使用

点击猫可依次查看日程、待办、无字幕页面。第三页只有猫。

右键菜单可编辑待办、隐藏宠物或退出。菜单栏面板提供日程、待办、声音选项和显示／隐藏入口。顶部图标拥挤时，直接使用 ⌃⌥⌘P，或再次打开 App。

隐藏宠物会停止正在进行的朗读。重新显示会保留位置与字幕。

## 开机自启

```bash
./scripts/install-login.sh install
./scripts/install-login.sh status
./scripts/install-login.sh uninstall
```

安装的是当前构建路径的 LaunchAgent；移动项目后需要重新安装。自动启动也保持安静。

## 数据

日历通过 Apple EventKit 在本机读取；语音使用系统 AVSpeechSynthesizer。当前 App 没有云同步和 AI 聊天。

待办文件保存在 `~/Library/Application Support/PetAssistant/todos/YYYY-MM-DD.json`，声音与窗口位置使用 UserDefaults 保存。仓库不包含个人日历、待办、运行日志、构建缓存或本地交接文件。

## 目录

```text
Sources/PetAssistant/     SwiftUI 界面、AppKit 窗口、日历、语音与待办逻辑
Resources/               猫图与 Info.plist
scripts/build.sh         直接 swiftc 构建并打包
scripts/install-login.sh 开机自启管理
```

## 目前的边界

猫仍然使用静态图，没有走路、睡觉等逐帧动画。App 使用本地 ad-hoc 签名，尚未做面向公众分发的 Developer ID 签名、Apple 公证或自动更新。当前版本主要面向个人使用。
