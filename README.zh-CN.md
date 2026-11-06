# MedCue

[简体中文](README.zh-CN.md) · [English](README.md)

MedCue 是一款原生 iPhone 与 Apple Watch 用药管理应用，帮助用户整理用药计划、记录服药事件、查看依从性趋势、关注库存，并准备简洁的复诊沟通信息。

MedCue 用于用药安全支持和日常管理，不诊断疾病、不处方，也不替代医生或药师。

## 当前发布范围

当前目标是学生竞赛评审、受控真机演示和 Beta 测试。项目目前不宣称已达到 App Store、商业生产或临床生产就绪状态。竞赛规则、知识产权、依赖许可、基础用药安全、隐私和数据完整性仍然是当前发布门槛。

## 功能概览

- Today 时间线支持记录已服用、延后、跳过、更正和重新打开的剂量任务。
- 药品资料支持疗程日期、剂量变化、多次提醒、包装照片和库存估算。
- 提供记录、日历、依从性趋势、风险复核和复诊摘要导出。
- Apple Watch、表盘组件、通知和 Live Activity 由 iPhone 作为主要事实来源。
- 可选的 HealthKit 信号只作为上下文趋势展示，不作诊断解释。
- 支持本地 OCR 和条码辅助导入；识别结果必须经用户复核后才能保存。
- 提供本地和云端医疗助手模式，具备明确同意、范围化上下文、传输校验和响应安全边界。
- iPhone 应用已有以简体中文为源语言的 String Catalog；Watch、Widget 和 Live Activity 等伴随 Bundle 的完整本地化仍在 [Issue #20](https://github.com/Gavin8233841/medcue-ios/issues/20)、[Issue #21](https://github.com/Gavin8233841/medcue-ios/issues/21) 和 [Issue #22](https://github.com/Gavin8233841/medcue-ios/issues/22) 中跟踪。

## 本地决赛离线模型

2026-10-28 本地决赛候选采用 MiniCPM5-2B Q4_K_M（约 1.56 GB，Apache-2.0），默认直接回答，思考模式保留为显式测试选项。权重单独下载或导入，不包含在仓库或源码包中。英文药名和正常格式可保留；没有固定答案兜底。此为本地试用结果，不代表已发布版本，取舍及限制见 [模型决策](docs/adr/0003-use-minicpm5-2b-for-local-finals-evaluation.md) 和 [工程状态](docs/PROJECT_STATUS.md)。

## 架构

仓库将领域逻辑与 Apple 平台集成分开：

- `swift-core/`：纯 Swift 领域模型、排程、依从性、趋势、库存、标签、风险和 AI 安全逻辑。
- `ios-app/MedicationAdherenceApp/`：SwiftUI 应用、SwiftData 持久化、应用命令、系统服务适配器、Watch 应用、Watch Widget 和 Live Activity 扩展。
- `Packages/LlamaFramework/`：本地模型运行时的包边界。
- `tools/`：可复现的验证和发布安全检查。

应用写入使用明确的命令和事务边界。SwiftData 成功提交后，才允许显示成功状态或执行通知、Watch 快照和 Live Activity 等提交后的副作用。关键剂量动作设计为在应用内和系统入口之间保持幂等；当前 Live Activity URL 入口仍存在授权和幂等性缺口，详见 [GitHub Issue #2](https://github.com/Gavin8233841/medcue-ios/issues/2)，因此尚未达到发布条件。

## 隐私与安全

- 用药数据使用版本化 SwiftData Schema 在本地保存，并有迁移覆盖。
- 云端 AI 默认选择加入，只接收用户明确授权的上下文范围。
- 凭据不进入源码仓库，发布产物会执行敏感配置检查。
- iOS 远程端点经过 HTTPS 校验，客户端拒绝重定向，并使用临时会话存储。
- 本地模型文件在使用前进行完整性校验。
- AI 输出在展示或保存前经过医疗响应边界处理。
- 助手不能创建、停止、替换或改变药品和剂量。

## 构建要求

- 兼容项目格式的 macOS 和 Xcode 26.5 或更高版本
- iOS 17.0 或更高版本
- WatchOS 目标支持
- 用于真机签名的个人或组织 Apple Developer Team

打开：

`ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj`

源码仓库有意不包含本地 llama 二进制文件。普通构建默认使用本地推理 stub：

```zsh
xcodebuild \
  -project ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj \
  -scheme MedicationAdherenceApp \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  -jobs 1 \
  build
```

如果要连接真机本地模型运行时，请先按照 [`ios-app/MedicationAdherenceApp/Frameworks/README.md`](ios-app/MedicationAdherenceApp/Frameworks/README.md) 提供本地 `llama.xcframework`，构建时设置 `MEDCUE_ENABLE_LOCAL_LLAMA=1`。stub 路径只验证其余源码和集成边界，不验证真实 llama 二进制或真机推理。仓库自动化目前还没有验证该框架的来源或摘要；在将它视为可信依赖前，必须单独完成这些检查。

真机运行时，请为主应用及其扩展选择同一个开发团队，然后在 Xcode 中运行共享的 `MedicationAdherenceApp` scheme。

## 测试与验证

运行可移植领域测试：

```zsh
cd swift-core
swift test
```

在不包含本地二进制的干净源码克隆中运行完整原生验证门禁：

```zsh
tools/verify-native.sh
```

原生门禁覆盖领域测试、托管持久化和应用测试、主导航与首次启动 UI 冒烟测试、未签名 Release 构建、Watch 构建、项目预检和敏感产物断言。

连接本地 XCFramework 后，可在门禁中设置 `MEDCUE_ENABLE_LOCAL_LLAMA=1`。真实推理还需要被忽略的 GGUF 模型和明确的冒烟流程；CI stub 或成功的链接构建都不能证明真实模型行为。

## 仓库结构

```text
.
├── .github/
├── cloudfunctions/
├── docs/
├── ios-app/
│   └── MedicationAdherenceApp/
├── Packages/
│   └── LlamaFramework/
├── swift-core/
├── tools/
├── AGENTS.md
├── CONTEXT.md
├── README.md
└── README.zh-CN.md
```

## 开发治理

开发使用 Issue -> branch -> Pull Request -> CI 流程。开始工作前请阅读 `AGENTS.md`、`CONTEXT.md`、`docs/PROJECT_STATUS.md` 和 `docs/DEVELOPMENT_WORKFLOW.md`。[`docs/README.md`](docs/README.md) 和 [`docs/README.zh-CN.md`](docs/README.zh-CN.md) 提供文档索引；[`docs/GITHUB_LOCALIZATION.md`](docs/GITHUB_LOCALIZATION.md) 记录中文优先、英文保留的 GitHub 文案、模板和标签约定。历史追加日志仅用于审计，不是当前 backlog。

## 医疗免责声明

MedCue 是用药整理和教育工具。提醒、风险摘要、趋势、导入文本和 AI 生成内容可能不完整或不准确。用户应向合格的医疗专业人员核实用药决定，并遵循适用的处方、药品标签和临床指导。

每次提问独立处理，同一次云端请求直接带入已授权用药资料。开启健康摘要共享后，明确的个人睡眠分析问题会附加当前 14/30 天睡眠与实际用药的逐日摘要。

Apple 健康摘要增加静息心率、睡眠时长及已有阶段记录、每日步数、活动能量和运动分钟数。点开指标可查看近 7/30/56 天图表。旧用户可在 App 内 Apple 健康页更新读取授权。用药与睡眠页支持联动选择日期；云端睡眠分析使用同一份实际数据摘要。

竞赛演示版云端回答保留模型原文，客户端仅记录内容检查标记，不再因剂量或频次关键词替换整段回答。模型回答仍可能有误，请结合记录与说明书核对。
