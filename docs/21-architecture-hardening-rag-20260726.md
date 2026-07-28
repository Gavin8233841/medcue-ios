# MedCue 架构治理 RAG（2026-07-26）

## 目的与事实口径

本文件把两份外部代码评估转换为可执行风险矩阵。外部评分只作为线索；结论以当前正式工程源码、现有测试和原生构建门为准。

当前基线：

- 分支 `codex/main-current-progress`，基线 HEAD `REDACTED_HEX40`；工作树已有大量已验证但未提交修改，必须原地保护，禁止清理、重置或覆盖。
- Swift Core `149/149`、iOS hosted tests `16/16`、`tools/verify-native.sh` 最近一次完整通过。
- App 源码中的精确 `try? modelContext.save()` / `try? context.save()` 已归零；剂量动作已经使用 `DoseActionPersistence` 事务提交与失败回滚。
- 主 App、Watch、Widget 等 Xcode Target 仍是 Swift 5 模式；Swift 6 complete 诊断已在 WatchConnectivity actor/sendability seam 失败。

## RAG 总表

| 颜色 | 项目 | 核验结论 | 可处理性 | 完成证据 |
|---|---|---|---|---|
| 红 | Live Activity“已服用”先显示完成、后落库 | **成立且范围明确。** iOS 17+ `MarkMedicationReminderTakenIntent.perform()` 只更新 ActivityKit 为“已完成”；SwiftData 要等 `AppRootView` 激活后调用 `consumeCompletedLiveActivities()`。若 Activity 在消费前消失，主库可能没有记录。 | 可自行解决；先做 P0。必须复用 `DoseActionPersistence`，建立幂等动作标识，数据库提交成功前不得展示“已记录”。 | 自动测试覆盖重复回调、保存失败、App 冷启动恢复；Simulator 覆盖终止进程后动作；真机补最终验收。 |
| 红 | Live Activity 动作来源与幂等 | 自定义 URL 仅校验 scheme、host、UUID、action；UUID 难猜但不是动作认证。重复消费当前主要依靠任务已关闭而自然返回，没有显式操作幂等键。 | 主要可自行解决；iOS 17+ 优先统一到 App Intent 命令模块。旧系统深链兼容策略需分阶段保留。 | 同一操作重复投递只产生一条日志；无效/过期动作不改数据；旧系统回归通过。 |
| 黄 | 巨型 View 与应用编排泄漏 | **成立。** `MedicationsView.swift` 6150 行，另有五个入口超过 2000 行；大量 `@State`、`@Query` 与系统调用集中在 View。 | 可分阶段自行解决，不能一次性机械拆文件。先抽“动作/编辑/导入/库存/会话编排”等 deep module，再搬展示代码。 | 每步减少 View 持有状态或系统调用；新增接口测试；功能、截图和完整构建门不变。 |
| 黄 | 应用层测试断层 | **成立。** Core 很强，hosted tests 目前 16 项，尚未覆盖 Watch 同步、Widget timeline、Live Activity 生命周期、通知规划和页面状态。 | 可显著改善；系统真实生命周期仍需 Simulator/真机补验。 | Fake/Spy adapter 测试 + 原生构建 + 明确运行态矩阵。 |
| 黄 | 配置和策略常量分散 | **成立。** 已核验包括云端 AI 20 秒、生命周期中断 14 天、Live Activity 5 分钟、通知 60 条、HealthKit 56 天、端侧模型 220/640 tokens 等。 | 可自行解决。按领域建立小而 deep 的策略 module，禁止创建无语义的全局常量仓库。 | 原值行为测试先冻结；迁移后调用方只依赖语义 interface；结果无变化。 |
| 黄 | Swift 6 与并发治理 | **成立。** Core 使用 Swift 6；App/扩展仍为 Swift 5。两个 `@unchecked Sendable` 需逐项证明，WatchConnectivity 回调是已复现阻塞点。 | 大部分可自行处理；全 Target 开关只能在诊断零错误且完整构建通过后启用。 | targeted/complete 诊断依次通过；不得靠批量 `@unchecked Sendable` 消警告。 |
| 黄 | `LocalMedicalAIClient` 职责过多 | **成立。** 单文件约 1700 行，同时包含 prompt 编排、流解析、质量修复和 llama runtime。 | 可自行安全拆分，保留现有 `MedicalAIClient` interface 和输出事实边界。 | 现有 Core/hosted tests 全过；补流解析、取消、质量回退测试；回答行为快照一致。 |
| 黄 | 原始类型与领域语义 | 部分成立。`DoseAmount.unit` 为 String，容易产生单位比较分散；但 `DrugLabelSection.text` 保留原文 String 是合理的，问题在标题分类而非正文类型。 | 可增量处理。先增加非破坏性的单位规范化和值语义；说明书增加由原始标题派生的类型，不立即改 Codable/SwiftData 存储。 | 兼容旧数据和现有 JSON；新增归一化/未知值测试；无迁移丢失。 |
| 黄 | Privacy manifest 数据流 | 外部报告“用了相机/HealthKit/通知就必须全部写入 manifest”不准确；权限用途在 Info.plist。真正要核验的是云端 AI/天气等是否构成收集，以及 App Store 隐私回答是否一致。 | 本地代码和数据流可审计；最终商店声明需要用户账户中的官方答案。 | 形成逐字段数据流表；PrivacyInfo、Info.plist、产品文案和商店答案一致。 |
| 绿 | 关键 SwiftData 静默保存 | 外部旧报告已过期：精确静默保存已从 50 降至 0，关键剂量动作有事务与回滚。 | 已完成主修复；继续做防回退和故障注入。 | 现有 hosted tests + 静态门禁持续通过。 |
| 绿 | 依从性重复计数、非法日期、启动 fatalError、Endpoint 与模型完整性 | 外部旧报告已过期：上述问题已进入正式工程并通过相应测试/构建。 | 已完成；不得为评分重复重写。 | Swift Core 149 项、hosted 16 项和原生门禁。 |
| 灰 | “Keychain 读写没有锁所以不安全” | 当前 `SecureAIConfigurationStore` 受 `@MainActor` 隔离；缺少显式锁本身不是已证实缺陷。应审查是否有跨 actor/同步阻塞，而不是盲目加锁。 | 不按外部结论直接修改。 | 并发诊断与调用图证明真实问题后再处理。 |

## 当前真实阻塞

1. 实体 Apple Watch 的后台、断连重连、表盘 Widget 与通知/触感只能在用户提供已解锁且开发模式可用的硬件后完成最终验收；代码和 Simulator 测试不等价。
2. 完整 CI 需要已选定的远端平台、仓库权限和签名/秘密管理方案；在此之前只能完善本地可复现门禁，不能提交不可执行的占位工作流。
3. 服务端 Token Broker 需要后端、部署与密钥轮换权限；客户端可先收紧 endpoint 和数据最小化，但不能凭空完成后端交付。
4. App Store 隐私答案及竞赛/商店后台状态需要用户账户中的官方页面或截图；仓库文档不能证明线上状态。

## 执行原则

- 首个小步只处理 Live Activity“已服用”的真实持久化契约，不与巨型 View 重构同时进行。
- 每个架构步骤必须通过一个窄 interface 提升 depth、leverage 与 locality；不能仅为降低文件行数搬运类型。
- 所有系统表面更新顺序统一为：验证请求 → 幂等检查 → SwiftData 提交 → 通知/Activity/Watch 更新 → 用户成功反馈。
- 任一步若改变功能或视觉行为，先补回归测试，再运行 `tools/verify-native.sh`；未通过则保留现有成果并停止扩大修改范围。
