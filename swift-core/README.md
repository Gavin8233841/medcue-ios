# MedicationAdherenceCore

这是当前 SwiftPM 核心模块。它只实现跨平台业务逻辑，不直接引用 SwiftUI、SwiftData、UserNotifications、Vision 或 HealthKit。

## 平台要求

- Swift tools version：6.3。
- SwiftPM 平台声明：macOS 12、iOS 15。
- 当前验证工具链为 `/Applications/Xcode.app` 的 Xcode 26.5（17F42）与 Apple Swift 6.3.2。版本变化后必须重新运行完整质量门，不能把 beta 工具链记录当作当前事实。

## macOS 测试命令

```zsh
cd $HOME/Desktop/appcontest-2026-prep/swift-core
swift test
```

如需核对当前工具链：

```zsh
xcode-select -p
swift --version
```

## 已实现

- 药品、用药计划、剂量、服药记录模型。
- 固定本地时间提醒规则。
- 固定间隔提醒规则。
- 服药完成率统计。
- 药品说明书风险关键词提取。
- 用户导入说明书解析支持中文常见内联章节写法，例如同一行连续出现 `【禁忌】`、`【注意事项】`、`【药物相互作用】`、`【不良反应】` 时会拆成独立章节，避免风险卡依据串入整篇说明书。
- openFDA Drug Label 客户端。
- RxNorm 药品名标准化客户端。
- RxClass 药品类别客户端。
- 离线演示药品数据和 API fallback 结构。
- iOS 本地通知所需的通知负载规划，不直接依赖 UserNotifications。
- 用药提醒策略模型：统一稍后 30 分钟、5 分钟升级提醒、15 分钟自动忽略和提前 6 小时二次确认，供 iOS 通知、今日页和实况活动共用同一口径。
- 时区变化后的用药计划复核判断。
- 药品计划变更审计，用于区分医生处方、说明书、用户自定义等来源。
- 就诊摘要生成，用于导出近期用药、服药率和风险提示。
- 扫码、OCR 和手动录入后的导入审核，确保识别结果先由用户确认。
- 药品风险评估聚合，把说明书风险、用户病症、饮食注意、药品类别和药物来源合并为前端可展示的警示卡片。
- 风险三类分组：药物相互作用、药物与饮食/生活方式相互作用、药物与病症/症状相关注意。
- 离线风险评估演示数据，保证无网络时仍可展示完整风险复核流程。
- 说明书可读化展示模型，保留来源章节、原文摘录和安全边界。
- 依从性洞察，按日期统计完成、跳过、延后和连续记录天数；未来未到期提醒不提前纳入连续记录，跨天稍后按用户操作日归属。
- 用药趋势仪表盘：至少 7 个有提醒日期后生成多主题趋势，覆盖用药纪律、时间稳定、剂量变化、用药负担和健康信号；每个主题提供透明公式摘要、模型权重、近 7 天 vs 前 7 天周期对比、近 7 天线性斜率/方向强度、数据置信度和主要贡献因素；每个趋势点保留当日公式组件，前端点选时可查看该日分数拆解；曲线会对剂量变化、归档/中断和授权健康样本显示事件标记；未来未到期提醒不提前参与评分，健康信号按同类指标近期中位数和波动幅度做非诊断性稳定度估计。
- 剂量变化记录模型：记录旧剂量、新剂量、生效日期和用户确认备注；趋势模型会把剂量变化、药品类型、来源和生命周期状态作为解释上下文，不把它解读为诊断、处方或疗效判断。
- 药品库存估算和低库存提醒，用于减少因药品不足导致的漏服；药盒估算已扩展到日均消耗、预计可用天数和数据不足提示。
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

本包已作为本地 Swift Package 接入 iOS App。iOS 工程层负责：

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
- 用户导入中文说明书的整行标题、冒号标题和 `【章节】正文` 内联标题拆分；风险卡依据按章节保留短片段。
- 离线药品说明 fallback。
- RxNorm 和 RxClass 基础数据结构。
- 通知负载规划和药品图片动作。
- 用药提醒策略：稍后按原计划提醒时间顺延 30 分钟、计划后 5 分钟升级提醒、计划后 15 分钟自动忽略、提前 6 小时以上需二次确认；远离计划时间的稍后操作由 App 层二次确认。
- 时区变化复核。
- 计划变更确认规则。
- 就诊摘要生成。
- 药品导入审核、低置信度识别提示和确认后建模。
- 风险评估卡片生成、病症和饮食复核、处方和用户来源复核、药品类别解释和离线演示路径。
- 说明书可读化卡片、长文本摘录限制和来源保留。
- 依从性按日统计、连续记录天数和补记修正。
- 用药趋势仪表盘不足一周、改善、下降和平稳判断，以及透明公式摘要、近 7 天 vs 前 7 天周期对比、近期斜率方向、置信度、贡献因素说明、趋势点当日拆解和曲线事件标记。
- HealthKit 健康信号进入趋势模型后的稳定度评分。
- 剂量变化、药品类型、录入来源和生命周期状态作为用药趋势解释上下文，数据不足时仍保留剂量变化摘要。
- 未来未到期提醒不提前影响连续记录或趋势；跨天稍后按用户操作日归属。
- 药品库存估算、低库存提醒、剂量单位不一致提示、预计可用天数和消耗数据不足提示。
- 医疗 AI 授权范围校验、未配置供应商占位响应。
- 医疗 AI 请求提示构造，确保未授权快照不会被拼入请求，并保留医生或药师复核边界。
- 风险三类分组、添加入口限制和服药操作撤销记录。

当前测试数量、验证日期与完整门结果统一见 `../docs/PROJECT_STATUS.md`。
