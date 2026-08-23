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
- Xcode 工具约定：使用 `/Applications/Xcode.app` 内 Xcode 27 Beta 5（27A5237l）自带的原生 MCP；`xcode-select` 已指向 `/Applications/Xcode.app/Contents/Developer`，命令行无需额外设置 `DEVELOPER_DIR`。旧 Build iOS Apps/XcodeBuildMCP 已卸载，不恢复、不调用。
- ShipSwift 插件：可用；2026-06-10 重启后已实测 `mcp__shipswift__listRecipes` 和 `mcp__shipswift__getRecipe` 可直接调用。
- 内置浏览器：可用，已用于核对官网和官方附件。
- Chrome 专用控制：当前未暴露可用入口，也未出现在可安装插件列表。
- Documents 能力：后续可用于填写和检查初赛 Word 文档。
- Stitch：用户已在 2026-06-10 明确弃用；不再作为本项目插件恢复、可用性检查或问题修复目标。若本机残留 Stitch 配置或缓存，不需要继续修复其认证、`gcloud` 或 Google Cloud token。

## 仍需补齐

- 指导老师信息，计划由班主任担任。
- 参赛队名。
- 学校、学院、专业等报名信息。
- 官方决赛日期与最终提交材料要求公布后重新校准计划。

## Xcode 与 Scheme

当前工程、Scheme、Target、Bundle ID 和 iOS 26.5 模拟器已通过 Xcode 27 原生 MCP 与本机构建路径核对，不需要用户重复提供。只有当前变更产生了原生工具无法回答的新外部事实时，才请求补充。
