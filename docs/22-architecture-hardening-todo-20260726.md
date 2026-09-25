# MedCue 架构治理执行清单（2026-07-26）

关联事实矩阵：`docs/21-architecture-hardening-rag-20260726.md`

## P0：系统表面与真实记录一致

### 1. Live Activity 剂量动作命令闭环

- [x] 冻结现有三入口语义：Today、通知、Live Activity 对 markTaken/delay/skip 的状态、时间、日志、同剂量组和撤销窗口必须一致。
- [x] 建立单一 deep module 处理 Live Activity 动作命令；interface 只暴露动作请求和明确成功/失败结果，implementation 内部复用 `DoseActionPersistence`。
- [x] 为每次逻辑动作生成稳定幂等标识；重复 App Intent、深链或 Activity 恢复不得重复写日志。
- [x] iOS 17+ “已服用”只有在 SwiftData 提交成功后才能更新 Activity 为已完成；失败时保留可重试状态并写入去隐私化错误提示。
- [x] 清理“App 下次 active 再猜测消费 Activity 状态”作为主路径；仅保留有版本说明和测试的兼容恢复路径。
- [x] 评估并收紧旧系统自定义 URL seam；不破坏 iOS 16 兼容前提下，拒绝过期、未知或已消费请求。

三入口现在共用 `DoseActionTransitionPlanner`，同表测试固定三动作的状态、计划时间、记录时间、同剂量组合并日志、稳定主日志和 10 分钟撤销窗口。SwiftData hosted tests 必须串行；并行时旧/新 Schema 同进程建库可触发 `SIGABRT`，共享 scheme 已固定为非并行。

验收：

- [x] hosted tests：成功、保存失败回滚、重复回调、过期动作、任务已关闭、同剂量组恰好一条主日志。
- [ ] Simulator：App 前台、后台、终止三种状态点击“已服用”；重新进入后记录一致。
- [ ] iPhone 15 Pro/17 Pro Max：灵动岛展开态、锁屏态、通知和主 App 记录一致。
- [x] `tools/verify-native.sh` 全量通过；`git diff --check` 通过。

Simulator 运行态阻塞（2026-07-26）：测试宿主与非测试 Debug App 均能安装、前台启动，且产物含 `NSSupportsLiveActivities=true`；现有冒烟入口返回 `activeLiveActivities=0`，系统“App”设置页未登记侧载 App，因此无法执行三种进程状态的真实 Live Activity 点击。该项保持未完成，不能替代真机验收。

## P1：建立可测试的应用层 module

### 2. 药品功能纵向拆分

- [x] 先绘制 `MedicationsView` 的药品列表、编辑、导入、库存、详情和计划依赖图。见 `docs/23-medications-view-dependency-map-20260726.md`。
- [x] 优先抽取药品编辑与库存写入 module；interface 返回可测试状态和错误，不直接暴露 ModelContext。
- [x] 抽取计划保存 module；计划、剂量变化、开放任务和 reminder batch 形成一个明确事务结果，通知只消费 committed 结果。
- [x] 再拆导入/OCR 编排与详情展示；每一步保持导航和视觉结构不变。
- [x] 禁止按行数机械拆文件；删除测试表明抽出的 module 确实提供 depth，而非 shallow 转发。

库存、药品资料与计划写入小步已完成：`MedicationInventoryCommand`、`MedicationProfileCommand` 和 `MedicationPlanCommand` 覆盖内部查询、明确结果和失败快照恢复，共 14 项 hosted tests。计划路径按药品/计划/相关任务限定查询，页面只在 committed 后调度通知；已完成任务的历史剂量不会被后续计划编辑改写。

新增药品持久化也已进入 `MedicationCreationCommand`：核对后的药品、计划、可选初始库存和未来任务形成单一提交结果，通知只消费 committed reminder batch；4 项 hosted tests 固定完整对象图、无库存、无效名称与失败无残留。OCR/条码继续由既有 `VisionImportService` 作为输入 adapter，`VisionImportPipeline` 统一处方、药名、说明书和条码结果类型、cancellation 检查及最新请求 gate；照片三入口也已进入资料 command 的精确事务。

药品详情的 plan/task/risk/stock/label/dose-change 查询已全部按当前 medication ID 限定；生命周期切换进入 `MedicationLifecycleCommand`，归档级联删除进入 `MedicationDeletionCommand`，说明书保存与派生风险重建进入 `MedicationLabelReviewCommand`。导入 pipeline 的 3 项测试固定迟到结果拒绝、取消与结果整形，照片 2 项测试固定对象隔离与保存失败恢复；本节纵向 module 已完成，展示继续按导航边界保留，不做行数驱动搬运。

计划性能基线已加入不含医疗内容的 `plan.save`、`plan.reconcile` Signpost；Release 真机 Instruments 的 P50/P95、Hang/Hitch 和内存结果仍待用户协作采集，未写成已验收。用户于 2026-07-27 复测“今日 -> 药品详情 -> 疗程编辑 -> 修改并保存”路径，确认此前约三秒的明显掉帧已显著改善、几乎无卡顿；该结论只覆盖用户实际复测路径，不扩写为全 App 性能验收。

计划保存后的提醒重排已完成应用层后台化：提交成功后先建立不含 SwiftData 对象的不可变 `MedicationReminderPostCommitSnapshot`，再由 utility detached task 内的 actor 执行最多 60 条 UserNotifications/AlarmKit 取消与建立。2 项 hosted tests 固定快照隔离与排序/上限/取消行为；该阶段完整门 hosted `75/75`。用户已在真机复测原问题路径，确认此前约三秒的明显掉帧已显著改善、几乎无卡顿；该结论只覆盖实际复测路径，不记录为全 App 帧率或 Instruments 验收。

### 3. Today / Records / Risks 状态编排

- [x] 将剂量动作反馈、归档/撤销、快照生成分别收敛到业务 module。
- [x] View 仅持有展示状态、导航与用户输入；系统调用经过明确 seam。
- [x] 为状态转换补纯测试，覆盖快速连点、切 Tab、取消 Task、数据保存失败。

复诊资料管线已完成：同一数据 revision 与日期范围只建立一次快照；入口不再用 6 个无范围 `@Query` 物化全库，改为按日期和关联 medication IDs 的 `VisitSummaryDataCommand`；PDF 使用不持有 SwiftData 的 `Sendable` export payload 在 utility detached task 排版/原子写盘；日期变化、离页和重新生成会取消任务，并由 generation gate 拒绝旧结果。原有 2 项 revision 测试加 4 项范围/隔离/取消/PDF 测试全部通过。

Today、Records 与 Risks 已继续推进纵向小步：Today 的完整渲染快照通过精确 revision cache 避免动画状态刷新时重复重建，归档/恢复写入进入 `TodayArchiveVisibilityCommand`，剂量撤销/重新打开及其横幅撤回进入 `DoseReopenCommand`；风险归档/重新打开进入 `RiskReviewCommand`；Records 修正写入进入限定同药品分钟窗口的 `DoseRecordCorrectionCommand`，该页面当前没有另一套记录撤销写路径。View 只在 committed 后驱动展示反馈和通知、Live Activity 等系统 adapter。快速重复调用、保存失败、精确 rollback、AI 切 Tab 取消、Vision/复诊资料旧任务取消与 generation gate 均已有回归测试；最终完整门 hosted `112/112`。

后续投影深化把 Today 的资格筛选、逻辑剂量去重、排序、摘要、完成率、状态替换完成率与 revision cache 收敛到 `TodayDoseProjectionStore`；`TodayView` 已删除同一套筛选、优先级和完成率算法，Live Activity 刷新也只消费投影资格任务。时间 revision 会在跨过具体 dueAt 时立即失效，同一临界点前仍可复用缓存。风险卡优先级去重、活动/归档分离、分类和 refresh revision 收敛到 `RiskDisplayProjection`；风险 identity 优先使用 detection signature，空 signature 回退到风险种类和规范化内容，避免同药品不同风险误合并。`TodayDoseInteractionState` 统一瞬态交互与延迟任务生命周期，`TodaySystemSurfaceSynchronizer` 统一提交成功后的通知和 Live Activity 同步；保存失败不会进入系统 adapter。Today 投影/交互/系统同步专项 `13/13`；独立展示区域继续位于 `TodayScreen`、`TodayDoseComponents`、`RiskListViews` 与 `RiskDetailViews`，入口 `TodayView.swift` 当前 912 行，`RisksView.swift` 当前 132 行。

### 4. AI 会话与端侧运行时

- [x] 保留现有 `MedicalAIClient` interface，拆分 prompt/answer plan、流解析/响应整形、llama runtime adapter。
- [x] 取消、超时、空响应、质量修复和医疗 Guard 的顺序只在一个 implementation 中定义。
- [x] 新增流解析、取消、失败不保存半条消息和边界 Guard 回归测试。

云端与端侧请求现在共用 `MedicalAIRequestOrchestrator`、`MedicalAIResponseFinalizer` 和 `AIChatResponseCommand` 的顺序约束；`LocalLLMStreamParser` 与 `LocalMedicalModelRuntime` 分别承接流解析和 llama runtime implementation。切换 Tab 会取消当前请求，迟到 request ID、空响应和未通过 Guard 的内容不能进入最终消息；SwiftData 提交失败不会显示或遗留半条 assistant 消息。AI 定向回归 `13/13`，并包含分段控制标签、调用方取消、超时、错误 request ID、空响应、剂量加倍和自行停药拦截。

后续深化已完成：`LocalMedicalAIClient.swift` 从约 1214 行收敛到约 195 行，prompt、事实摘要、清洗和质量判定进入 `LocalMedicalResponsePolicy`，client 只保留 provider、生成/流式生成、取消传播与一次质量修复编排。`AIConversationPersistenceCommand` 统一消息批次、消息删除、授权保存/撤销和失败回滚，`AIAssistantView` 中直接 `modelContext.insert/delete` 与 `AppPersistenceCommitter.save` 已归零；`AIChatResponseCommand` 保留原 interface 并委托同一 implementation。

AI 页面后续新增 `MedicalAIContextBuilder` 与 `AIConversationMaintenancePolicy`，统一“今天”问题的任务范围、逻辑剂量去重、授权字段裁剪，以及历史迁移、消息配对清理、快捷提示清理和中断请求修复；两组共 6 项 hosted 测试通过。`AIConversationSendPlanner` 进一步统一第三方声明、运行时、授权 scope、凭据和本地/云端派发决策，9 项测试固定所有停止与派发分支；消息仍需先提交成功再启动请求。对话、输入、运行态和屏幕展示已继续拆入独立 View 文件，`AIAssistantView.swift` 当前 932 行。

## P1：配置、并发与平台测试

### 5. 领域策略集中

- [x] 为已核验常量补行为测试：AI 20 秒、生命周期 14 天、Live Activity 5 分钟、通知 60 条、HealthKit 56 天、端侧 token 档位。
- [x] 分别建立 Medical AI、生命周期、Live Activity、通知、健康上下文策略 module；不用单一全局常量文件。
- [x] 调用方通过语义 interface 获得策略，默认值与当前产品行为完全一致。

`DomainPolicyTests` 的 5 项行为测试固定 AI 超时、趋势窗口和 token 档位，生命周期中断/宽限期，Live Activity 激活/陈旧窗口，通知上限及 HealthKit 回看范围；调用方已改用各领域 policy interface。

### 6. Swift 6 并发治理

- [x] 先修 `MedicationWatchSnapshotCenter` 与 `MedicationWatchReminderScheduler` 的 WatchConnectivity callback seam。
- [x] 审计两个 `@unchecked Sendable`，用不可变状态、actor 或经过证明的同步替代；不批量消警告。
- [x] 按 Target 执行 targeted → complete 诊断；只有零错误且全量构建通过才修改工程语言模式。
- [x] 对 ModelContext 的查询/保存测量主线程耗时；只有证据显示阻塞时才调整执行模型。（2026-08-25：性能测量基础设施已实现，详见 `docs/26-modelcontext-performance-baseline-20260825.md`；真机 Instruments 数值仍需用户执行）

WatchConnectivity 状态已收敛到 MainActor/actor，Watch reminder adapter 改为 async/await；工程源码中的显式 `@unchecked Sendable` 已归零。2026-07-28 已完成五个 Target 的 Swift 6.0 语言模式迁移，App、Tests、Live Activity、Watch App 与 Watch Widget 的 Debug/Release 配置均为 `SWIFT_VERSION = 6.0`。迁移后的最新完整本地门通过：Swift Core `152/152`、hosted tests `165/165`、XCUITest `2/2`、主 App 无签名 Release、Release 敏感产物断言、Watch Simulator Debug 与 watchOS device SDK Release；不再沿用此前“工程保持 Swift 5”的旧状态。计划保存与任务协调已加入 `plan.save`、`plan.reconcile` Signpost，复诊资料查询已限定范围；Release 真机 Instruments 数值仍需用户执行，第四项保持未完成。

### 7. 平台测试矩阵

- [x] 通知规划 adapter：授权拒绝、重复调度、数量上限、时区变化。
- [x] Watch 同步 adapter：重复消息、离线队列、过期快照、重连。
- [x] Widget timeline：空态、过期、隐私模式。
- [ ] Live Activity：见 P0，作为首个完整应用层测试样板。

`PlatformBehaviorTests` 的 5 项测试覆盖通知拒绝、去重后应用上限、时区组件，Watch 离线只排队一次且最新快照覆盖并在重连发送，以及 Watch/Widget 首次同步、过期、空态与隐私态。实体 Watch、表盘刷新和后台重连仍需真机矩阵。

## P2：兼容性、安全与交付

### 8. 原始类型增量治理

- [x] `DoseAmount.unit` 增加非破坏性规范化类型，保留原始字符串兼容旧数据。
- [x] `DrugLabelSection` 从 title 派生类型化 section kind；正文 text 继续保留来源原文。
- [x] 未知单位/标题必须可保真往返，不得因枚举化丢失真实药品资料。

`DoseUnitKind`、`DoseAmount.normalizedUnit` 与 `DrugLabelSection.kind` 均为派生语义，不改变原始 Codable 字段；`RawTypeCompatibilityTests` 的 3 项测试固定已知单位归一化、未知单位和未知标题 JSON 往返保真。

### 9. 隐私数据流核对

- [x] 列出相机、HealthKit、定位、药品资料、AI 对话、本地模型各自在设备内、系统框架、云端的实际流向。
- [x] 区分 Info.plist 权限用途、PrivacyInfo required-reason API 与 collected data 声明。
- [ ] 与 App Store 隐私答案和用户可见授权文案逐项对齐；没有官方后台证据的项标为待用户核验。

代码可证明的数据流与三类声明已记录在 `docs/24-privacy-data-flow-audit-20260727.md`。App Store Connect collected data 实际答案需要发布者账户证据，不能由仓库代替。

### 10. 本地门禁与远端 CI

- [x] 把 Live Activity P0 测试、静默保存防回退、Core/hosted tests、Release/Watch 构建保持在 `tools/verify-native.sh`。
- [x] 在私有 GitHub 仓库建立可执行的 `Native Verification` workflow，并用本地 CI-stub 全新 DerivedData 验证 package resolution 与 hosted tests。
- [x] 推送当前 CI 修复后确认 GitHub Actions 全量门绿色；不得以本地复现替代远端结果。

本地门同时检查 PrivacyInfo required-reason 声明，并递归拒绝 Release 产物中的 `AISecrets.plist`、`.env.local`、GGUF 与 SQLite 用户数据。2026-07-28 最新完整门通过：Swift Core `152/152`、hosted `165/165`、XCUITest `2/2`、主 App 无签名 Release、Release 敏感产物断言、Watch Simulator Debug 与 watchOS device SDK Release。五组投影/会话专项合跑 `20/20`；Broker/endpoint 专项 `13/13`。首次远端运行因发布源码中的 llama 占位目录无法解析而退出 74，且 runner 缺少 `rg`；修复后 GitHub Actions `Native Verification` 运行 `30330080655` 全量通过。当前 workflow 在 `MEDCUE_DISABLE_LOCAL_LLAMA=1` 下使用不导出 `llama` module 的 stub product，普通本地/真机构建仍使用真实 xcframework；CI 安装 `ripgrep`，验证脚本也显式要求 `rg`。

新增 `tools/swift-source-size-check.sh` 并接入快速/完整门，默认限制为 1400 行；当前最大文件为 `OnboardingHeroViews.swift` 1247 行。原评估中的 `MedicationsView.swift`、`RecordsView.swift`、`TodayView.swift`、`SettingsView.swift`、`AIAssistantView.swift` 与 `AppRootView.swift` 已按纵向功能拆分，入口文件当前分别为 275、321、912、488、932 与 268 行；`RisksView.swift`、`MedicationTrendViews.swift`、`LocalMedicalAIClient.swift` 分别为 132、199、195 行。`NotificationService.swift`、帮助中心、Today 剂量组件、Records 剂量组件、复诊 PDF 支持和趋势模型本轮继续按所有权拆到独立文件。原 1449 行 `MedicationOverviewViews.swift` 已按快照、仪表板、卡片和目的页面拆为 54、398、346、250、447 行文件；药品任务观察统一为近 90 天至未来 8 天，“今日待处理”只观察当天。该门只防止文件体积回退，业务编排仍以 deep module 和事务测试为完成依据；仍有少数按功能聚合的支持文件超过 1000 行，但不再以机械拆分为目标。

### 10a. AI Token Broker

- [x] 建立独立 CloudBase HTTP Broker 本地实现与 TDD 契约，固定请求边界、上游锁定、错误映射、超时、实例内短期去重与限流。
- [x] 在 CloudBase 注入服务端 `ARK_API_KEY`/`ARK_MODEL`、创建函数、配置调用权限，并以不含医疗正文的真实请求完成健康检查和日志抽检。
- [x] 新增 iOS Broker adapter、统一 client factory、Release HTTPS allowlist 与客户端契约回归。
- [x] 以不含医疗资料的真实请求完成真机端到端验证；在外部身份或 App Attest 到位前，不把静态 client token 宣称为生产级设备证明。

`cloudfunctions/medcue-ai-broker` 的本地测试当前为 `17/17`，iOS Broker/endpoint 专项 `13/13`。CloudBase 独立函数、默认 HTTPS gateway、服务端环境变量、非医疗真实请求和最近 15 分钟日志抽检均已完成；用户随后在真机以不含医疗资料的请求确认 Broker 模式可用。当前闭环满足竞赛与真机 Beta 边界，但静态 client token 仍不是生产级设备证明，App Attest/DeviceCheck、用户与设备绑定、短时令牌、按主体配额与撤销仍是商业发布增强项。

### 11. 手动 UUID 引用完整性

- [x] 建立只读 `PersistenceIntegrityAuditor`，覆盖孤儿计划、剂量变化、任务、风险、说明书、库存、生命周期和动作日志，以及任务/剂量变化跨药品引用计划。
- [x] 启动时每个 App 生命周期只执行一次；日志只输出固定问题类别和计数，不输出 UUID、药名、医疗内容，也不自动修复或删除用户数据。
- [x] 测试覆盖完整对象图零误报、孤儿引用不改数据、跨药品引用、日志脱敏和重复启动幂等。

2026-07-27 收到一次 Xcode 真机 Debug 会话内存终止提示；用户随后明确该提示未确认可复现，只要求记录。本轮没有将其登记为已定位缺陷，也没有据此修改内存策略；若后续稳定复现，再使用 Release/Instruments 证据单独立项。

### 12. 查询观察、国际化与无障碍

- [x] Today、药品、趋势、Records 与复诊资料的任务/事件查询按实际时间窗口或关联药品限定；药品详情的计划、任务、风险、库存、说明书和剂量变化按当前药品限定。
- [x] 删除启动后同时订阅 12 组 SwiftData 集合的 `StartupQueryWarmupView`，继续使用按需加载 Tab、页面级有界查询和 revision cache；不再为不可复用的“预热”物化全库并扩大 invalidation。
- [x] 建立并接入 `Localizable.xcstrings`，源语言为简体中文，当前纳入 397 个界面字符串键；不把尚未提供完整译文的语言写成已支持。
- [x] 为五个主 Tab 内容根、今日时间线、药品新增/资料保存/疗程保存、AI 输入/发送/归档和首启操作等关键流程提供 15 个稳定 `accessibilityIdentifier`，同时保留现有 VoiceOver label/value。
- [x] 建立 XCUITest smoke，按固定 Tab 顺序操作系统按钮并断言五个稳定内容标识，另覆盖首启“下一步/跳过”操作；Simulator 实测 `2/2` 通过。
- [ ] 完整写入流程 XCUITest、视觉回归和英语等新增语言的产品级翻译仍属于后续发布能力；当前源码不能把它们描述为已完成。

药品、风险、设置等确实需要展示全量实体的页面仍保留对应集合观察，这些是界面数据需求，不通过任意日期过滤截断真实内容。若要进一步分页，必须先定义归档浏览、搜索和历史可达性契约，再以运行数据证明收益。

## 每个小步的固定退出条件

1. 修改范围能用一个业务目的描述。
2. 先有失败或防回退测试，再改 implementation。
3. 不读取或打包密钥、`.env.local`、`AISecrets.plist`、GGUF、用户数据库或设备标识。
4. 不清理、不重置、不覆盖用户现有未提交修改。
5. `git diff --check`、相关测试和 `tools/verify-native.sh` 全部通过。
6. 更新 `PROJECT_UPDATE_LOG.md` 与本清单的实际状态；不得把 Simulator 结果写成真机验收。
