# MedicationAdherenceCore

这是当前 SwiftPM 核心模块。它只实现跨平台业务逻辑，不直接引用 SwiftUI、SwiftData、UserNotifications、Vision 或 HealthKit。

## 平台要求

- Swift tools version：6.3。
- SwiftPM 平台声明：macOS 12、iOS 15。
- 新 Mac 已安装 Xcode 26.5，可使用 Xcode 内置 Swift 6.3.2 运行测试。
- 如果系统默认 `xcode-select` 仍指向 Command Line Tools，可在命令前临时加：

```zsh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift test
```

## 已实现

- 药品、用药计划、剂量、服药记录模型。
- 固定本地时间提醒规则。
- 固定间隔提醒规则。
- 服药完成率统计。
- 药品说明书风险关键词提取。
- openFDA Drug Label 客户端。
- RxNorm 药品名标准化客户端。
- RxClass 药品类别客户端。
- 离线演示药品数据和 API fallback 结构。
- iOS 本地通知所需的通知负载规划，不直接依赖 UserNotifications。
- 时区变化后的用药计划复核判断。
- 药品计划变更审计，用于区分医生处方、说明书、用户自定义等来源。
- 就诊摘要生成，用于导出近期用药、服药率和风险提示。
- 扫码、OCR 和手动录入后的导入审核，确保识别结果先由用户确认。
- 药品风险评估聚合，把说明书风险、用户病症、饮食注意、药品类别和药物来源合并为前端可展示的警示卡片。
- 风险三类分组：药物相互作用、药物与饮食/生活方式相互作用、药物与病症/症状相关注意。
- 离线风险评估演示数据，保证无网络时仍可展示完整风险复核流程。
- 说明书可读化展示模型，保留来源章节、原文摘录和安全边界。
- 依从性洞察，按日期统计完成、跳过、延后和连续记录天数。
- 药品库存估算和低库存提醒，用于减少因药品不足导致的漏服。
- 医疗 AI 供应商无关接口，支持聊天、风险优化、OCR 导入复核和条码导入复核的请求/响应结构。
- 医疗 AI 请求提示构造器，把用户授权的药品快照、服药记录、风险卡片、说明书摘要和导入草稿整理成供应商可用的中文安全提示。
- 添加药品三入口工作流：手动添加、医嘱/OCR 导入、药盒条码扫描。
- 服药操作历史和撤销时间窗，用于前端完成动画、移出待办和误操作找回。

## Windows 测试命令

在普通 PowerShell 中执行时，需要显式加载 VS Developer Shell、Swift Toolchain、Swift Runtime 和 SDKROOT：

```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
& "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\Launch-VsDevShell.ps1" -SkipAutomaticLocation -Arch amd64 -HostArch amd64
$swiftRoot = "REDACTED_HOME_PATH"
$toolchainBin = "$swiftRoot\Toolchains\6.3.2+Asserts\usr\bin"
$runtimeBin = "$swiftRoot\Runtimes\6.3.2\usr\bin"
$env:SDKROOT = "$swiftRoot\Platforms\6.3.2\Windows.platform\Developer\SDKs\Windows.sdk"
$env:Path = "$toolchainBin;$runtimeBin;$env:Path"
& "$toolchainBin\swift.exe" test
```

## iOS 工程接入方式

进入 Mac + Xcode 阶段后，把本包作为本地 Swift Package 接入 iOS App。iOS 工程层负责：

- SwiftData 持久化适配。
- UserNotifications 本地提醒适配。
- Vision 条码和 OCR 适配。
- HealthKit 授权与读取适配。
- 库存提醒、复诊摘要分享和导入复核的界面适配。
- SwiftUI 展示与交互。

## 当前测试覆盖

- 固定本地时间和固定间隔提醒。
- 服药完成率统计。
- 风险关键词提取。
- 离线药品说明 fallback。
- RxNorm 和 RxClass 基础数据结构。
- 通知负载规划和药品图片动作。
- 时区变化复核。
- 计划变更确认规则。
- 就诊摘要生成。
- 药品导入审核、低置信度识别提示和确认后建模。
- 风险评估卡片生成、病症和饮食复核、处方和用户来源复核、药品类别解释和离线演示路径。
- 说明书可读化卡片、长文本摘录限制和来源保留。
- 依从性按日统计、连续记录天数和补记修正。
- 药品库存估算、低库存提醒和剂量单位不一致提示。
- 医疗 AI 授权范围校验、未配置供应商占位响应。
- 医疗 AI 请求提示构造，确保未授权快照不会被拼入请求，并保留医生或药师复核边界。
- 风险三类分组、添加入口限制和服药操作撤销记录。

当前新 Mac 测试结果：40 个 Swift Testing 测试全部通过。
