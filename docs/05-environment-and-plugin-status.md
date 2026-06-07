# 环境与插件状态

## 已确认

- Swift Toolchain 6.3.2 已部署。
- Visual Studio Community 2022 17.14.33 已部署，含 MSVC 与 Windows 11 SDK。
- Python 3.10.11 已部署。
- SDKROOT 已配置到 Swift 的 Windows.sdk。
- VS Code 已安装 swiftlang.swift-vscode 和 LLDB DAP。
- SwiftPM 烟测项目路径：REDACTED_HOME_PATH
- SwiftPM 烟测已完成：swift build 成功，swift run 输出 Hello, world!。

## 使用注意

Swift 命令需要从 Developer PowerShell for VS 2022 进入，普通 PowerShell 没有自动加载 MSVC 的 link.exe 编译环境。

## Codex 插件状态

- GitHub 插件：可用，适合后续版本管理、仓库查看、提交和 PR。
- Build iOS Apps 插件：可用；当前会话没有配置 Xcode 项目、Scheme、模拟器。
- 内置浏览器：可用，已用于核对官网和官方附件。
- Chrome 专用控制：当前未暴露可用入口，也未出现在可安装插件列表。
- Documents 能力：后续可用于填写和检查初赛 Word 文档。

## 仍需补齐

- 指导老师信息，计划由班主任担任。
- 参赛队名。
- 学校、学院、专业等报名信息。
- 选定 App 方向。
- 若继续启迪：macOS/Xcode 或可被 Codex 使用的 iOS 构建环境。

## Xcode 与 Scheme

当前不需要用户提供 Xcode、Scheme 或模拟器信息。等出现 `.xcodeproj` 或 `.xcworkspace` 后，先用 Build iOS Apps 插件读取会话默认值和项目配置；如果插件无法确定 Scheme、Target、Bundle ID 或模拟器，再要求用户补充精确信息。
