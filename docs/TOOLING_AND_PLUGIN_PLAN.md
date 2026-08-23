# MedCue 本机工具与插件计划

最后核对：2026-08-23

工具用于缩短“理解—修改—验证”循环，不能替代源码、测试、真机证据或用户理解。

## 工作区硬边界

- 唯一活动仓库：`/Users/Admin/Developer/MedCue/appcontest-2026-prep`；
- `/Users/Admin/Desktop/appcontest-2026-prep` 及迁移目录只读；
- 不在只读目录创建分支、worktree、构建产物或修改；
- 恢复任务先运行 `git rev-parse --show-toplevel`，路径不一致就停止。

## 当前 Xcode 基线

- `/Applications/Xcode.app`：Xcode 27 Beta 5，build `27A5237l`；
- `xcode-select`：`/Applications/Xcode.app/Contents/Developer`；
- Swift：Apple Swift 6.4；iPhoneOS 与 watchOS SDK：27.0；
- iOS 26.5 与 watchOS 26.5 Runtime 已验证可用；
- Xcode Intelligence 的 `Allow External Agents to Use Xcode Tools` 为 `Always`；
- Xcode 原生 MCP 已验证可读取工程并执行原生 RunProject；Release、Demo 和 iOS 26.5 模拟器路径已由前序任务验收。

这些证据只说明当前本机工具链可用，不自动证明未来提交的代码、真机行为、签名或发布产物正确。除非当前变更的验收需要，不重复完整 Release、Demo 和 MCP 全流程。

## Xcode 操作规则

- 优先使用 Xcode 27 自带原生 MCP 读取工程、Scheme、构建、测试和模拟器状态；
- 命令行 fallback 直接使用当前 `xcode-select` 指向的工具链，不写死旧下载路径；
- 旧 Build iOS Apps 插件和独立 XcodeBuildMCP 已移除，不安装、不恢复、不调用；
- 不启用或读取旧 Xcode 回退副本；回退需要产品负责人另行明确决定；
- 不自动升级部署目标、改签名、清理 DerivedData 或修改工程设置来掩盖失败。
- 当前 Xcode 27 暴露的 Watch SDK 名称是 `watchsimulator27.0` 和
  `watchos27.0`；`tools/verify-native.sh` 的本机默认值仍是 26.5。脚本完成
  独立治理前，本机完整门禁须通过其公开环境变量传入上述已验证名称；CI
  已传入通用 `watchsimulator` 和 `watchos`，不受该本机默认值影响。

## 当前需要的能力

- 产品设计：用于收敛用户问题、最小旅程和无障碍验收；
- Xcode 原生工具：用于 SwiftUI、Preview、构建、测试和模拟器证据；
- GitHub：只读协作跟踪、Pull Request、评审和准确提交 CI；
- Documents / Presentations：只在决赛材料进入对应里程碑时使用。

只有出现可复现问题时才启用专项性能、内存或自动化工具。当前不因“可能有用”安装额外插件，也不让工具扩大账号权限、上传源码或处理真实健康内容。

## 隐私边界

- 不读取或输出密钥、`AISecrets.plist` 内容、GGUF 内容、用户数据库、健康数据或设备标识符；
- 不把真实健康数据放进提示词、截图、日志或测试夹具；
- 只报告工具名称、版本、启用状态和脱敏结果，不输出令牌、请求头或敏感环境变量；
- 不绕过密钥保护，不用插件输出替代医疗、隐私或发布证据。

## 每次变更的最小工具验收

1. 先核对仓库、分支、准确 HEAD、工作树和文件重叠；
2. 只运行能证明当前小步的聚焦检查；
3. 原生代码迭代运行相关测试与 `tools/verify-native.sh --quick`；
4. 整合前运行完整相关门，并记录准确提交；
5. 真机、账号或外部服务行为单独记录，不用 Simulator 或源码审查代替。
