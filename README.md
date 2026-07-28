# MedCue / 用药跟踪

本交付包包含原生 iOS、watchOS、Live Activity、Widget 与 Swift Core 源码。包内不含本地模型、二进制 llama framework、开发密钥、用户数据库、构建缓存或内部操作时间线；离线模型依赖需按 `tools/install-llama-xcframework.sh` 在本机安装。

## 当前原生开发策略

- 产品定位：中文名“用药跟踪”，英文兼容名 `MedCue`；面向用药依从性、提醒、记录、库存、说明书/风险复核、趋势和复诊沟通，不提供诊断或自动调药。
- iPhone 是药品与任务数据的事实源；Apple Watch 是只读伴随端，展示今日任务、提醒状态和表盘复杂功能。
- 当前工具链固定为 Xcode 26.5（17F42）与 Swift 6.3.2；不恢复 Xcode 27、ACP、FoundationModels/Core AI、TRAE 或 Web 路线。
- 修改采用小闭环：精确读取现有工程与源码，最小改动，随后执行 Swift Core、工程预检、构建和必要的 Simulator/真机验收。

## 历史竞赛资料（不再执行）

以下文件仅作为仓库历史归档，不代表当前规则、任务或提交状态：

- 官网通知页：https://www.appcontest.net/REDACTED_HOME_PATH
- 章程：official/2026-附件二-大赛章程.pdf
- 组织机构：official/2026-附件一-组织机构名单0323.pdf
- 报名手册：official/2026报名手册.pdf
- 初赛模板：official/初赛作品说明文档模板.docx

## 目录说明

- docs：规则、赛道、技术边界、产品方向、数据源、安全边界和环境状态。
- docs/11-development-todo.md：当前后端、前端和 AI 接入待办清单。
- checklists：报名、作品提交和复赛前检查。
- templates：文档写作和沟通模板。
- official：本地保存的官方附件副本。
- swift-core：Windows 可测试的 SwiftPM 核心模块。
- ios-app：SwiftUI iOS App 工程，接入 swift-core 作为本地 Swift Package；当前主界面为今日、药品、智能体、记录、个人五 Tab，风险复核已并入药品页。

## 当前实现状态

- swift-core：136 个 Swift Testing 测试通过，覆盖提醒、风险聚合、说明书解析与可读化、依从性洞察、趋势、库存 checkpoint、导入审核、医疗 AI 请求边界和环境用药关注。医疗 AI 安全门会阻断诊断、处方、新开药、停药、换药、剂量调整和频次调整等直接治疗决策。
- ios-app：已建立 hosted `MedicationAdherenceAppTests` target、tracked shared scheme 和统一 11 模型的 `MedicationAdherenceModelContainer`；2 项 SwiftData 基线测试通过。`tools/verify-native.sh` 完整验证通过；主 App 无签名 Release、Watch Simulator 26.5 Debug 与 watchOS 26.5 device SDK Release 均构建成功。Release 与 iOS 测试产物断言确认不含本地 AI 敏感配置，主 App 产物包含 Watch App 与 Watch Widget。
- 已落地的可交互能力：首启引导横移/缩放/淡入动画、今日任务完成/撤销、今日天气与环境用药关注、已处理记录横滑操作、药品页健康式概览、药品详情、详情页药品照片选择/拍照入口、疗程和多提醒时间编辑、药盒低量提示、记录页四入口、周/月历记录、用药趋势仪表盘、授权 HealthKit 生命体征读取、复诊摘要分享、三入口添加药品、本机 OCR、条码图片识别、真机相机扫码、智能体首次确认、聊天式智能体界面、智能体授权、后台 Keychain 凭据读取、Apple 账号与 iCloud 备份准备入口、风险置顶收敛与二级详情。
- 已接入的智能体能力：在线与端侧回答在展示和持久化前都经过医疗安全门；端侧流式阶段不展示未经审查的回答或思考增量。真实密钥只通过受控本地配置或 Keychain 进入 Debug App，不写入源码、文档、测试、Release 产物或构建日志。
- 演示数据边界：Release 与普通 Debug 不自动写入演示数据；仅显式 `--seed-demo-data` 或 Live Activity smoke 参数可触发。固定演示 UUID 被用户数据占用时跳过，用户同名药不会被覆写或转为演示内容。
- Watch Simulator：46mm/40mm 的 8 类状态共 16 次启动均返回 PID；已配对 iPhone/46mm Watch 的真实 WCSession 首发与后续状态变化通过。首发从 `2/5、待处理 3` 开始，iPhone 写入恰好 1 条 taken 日志后更新为 `3/5、待处理 2`；滚动后的隐私行也已确认不显示药名或剂量。Widget 表盘实际刷新、实体设备通知和 App Group provisioning 仍待验收。
- 数据可靠性修复：今日动作/重开在可取消动画之前同步提交；库存以 `lastUpdated` 为实物盘点 checkpoint，不再重复扣盘点前历史。HealthKit 查询取真正最新 250 条，未使用的临床记录和后台投递 entitlement 已移除。

## 下一步

1. 在已建立的 iOS 单元测试 target 和内存 SwiftData 容器上，引入 `VersionedSchema`、迁移计划和无用户数据的合成旧库 fixture，并补重复启动幂等测试。
2. 将 Today、通知响应、Live Activity 与自动忽略收敛到单一剂量动作事务模块，显式处理保存错误。
3. 验收 Watch Widget 表盘实际刷新，并在实体 iPhone/Watch 上验收通知投递和 App Group provisioning。

路线 A Git checkpoint 已建立；后续提交继续排除历史赛事材料、密钥、GGUF、构建缓存和本地 xcframework。
