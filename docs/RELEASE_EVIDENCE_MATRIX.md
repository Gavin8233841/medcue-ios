# 发布证据矩阵

审计截面：2026-08-31（Asia/Shanghai）

权威基线：`main@d5d5e6920faa3f4b706ce35c696863d4faa7c459`
用途：记录当前可复核的发布证据、真实阻塞和协作下一步，不把缺失的设备、账户或视觉证据写成通过。

## 1. 判定约定

- `PASS`：证据来自同一精确修订，且可以由仓库脚本、测试结果或远端记录重复核验。
- `BLOCKED`：验收需要的设备、账户、产品决定、合并结果或实现证据当前不可用。
- `FAIL`：在指定精确修订上已有可复现的失败结果；在修复和新精确 HEAD 证据出现前不能推进。
- `N/A`：只有在 Issue 已给出书面产品或平台理由时使用。
- 标记为“自动化”的 `PASS` 只证明代码/逻辑边界，不满足 #17 的实体设备验收；模拟器、桩运行时和旧 SHA 的结果不能替代真机或当前 HEAD 证据。

证据边界：只使用虚构、脱敏数据。本文不记录 UDID、个人设备名称、凭据、用户数据库、提示词历史、GGUF 内容或本地模型哈希。主工作区已有的未提交文件不属于本分支，也未被读取或改写。

## 2. 当前基线事实

| 项目 | 精确证据 | 判定与限制 |
| --- | --- | --- |
| `main` | `d5d5e6920faa3f4b706ce35c696863d4faa7c459`，`feat: Add ModelContext performance measurement infrastructure` | `PASS`：本矩阵的唯一源码基线。 |
| Native Verification | [Run 32803611679](//github.com/Gavin8233841/medcue-ios/actions/runs/32803611679)；head SHA 与上面完全一致 | `PASS`：Classify、Full Native Builds、Swift Core、iOS unit、iOS UI、required result 均成功。该 CI 不是实体设备签名验收。 |
| 工具链 | Xcode `27.0`，build `27A5237l` | `PASS`：本机工具事实；不等于 Apple 账户或签名可用。 |
| 实体 iPhone / Apple Watch | `xcrun xctrace list devices` 仅显示设备离线；未取得可安装、配对、锁屏或后台运行证据 | `BLOCKED`：#17 的硬件行不能以离线设备名或 UDID 推断通过。 |
| 可用模拟器 | iOS 26.5 与 watchOS 26.5 模拟器可启动 | `PASS`（环境）：可做自动化/布局预检；不能证明安装、通知、Watch Connectivity、Live Activity 或午夜跨天硬件行为。 |
| 本地 llama 运行时 | CI 明确以 `MEDCUE_DISABLE_LOCAL_LLAMA=1` 构建；干净证据工作树没有被忽略的 `llama.xcframework` 或 GGUF | `BLOCKED`：不能声称本地模型真机首次响应已演示。私有模型只可由设备持有人在本地提供。 |

## 3. #17 实体设备最小矩阵

以下行沿用 [Issue #17](//github.com/Gavin8233841/medcue-ios/issues/17) 的编号语义。每行最终执行时还必须补充精确签名 Release SHA、版本/构建号、设备型号、OS、步骤、预期/实际结果和脱敏证据链接。

| 行 | 边界与最小步骤 | 当前仓库/CI 证据 | 状态 | 跟进 |
| --- | --- | --- | --- | --- |
| 17-01 | 全新安装、受控升级、冷启动、前后台、终止、重启和持久化恢复 | hosted 测试使用内存/CI 构建；没有签名实体安装记录 | `BLOCKED` | #17；需设备持有人执行并记录签名构建。 |
| 17-02 | 建档 → 计划 → 剂量编辑 → 任务生成 → 已服用/延迟/跳过（若入口提供）→ 更正/重开；重启后无重复 | `MedicationCreationCommandTests`、`MedicationPlanCommandTests`、`DoseRecordCorrectionCommandTests`、`DoseReopenCommandTests` 覆盖部分事务逻辑；完整 UI 写入链路仍属 #52/#7 | `BLOCKED` | #52、#7、#17；需完整 XCUITest 和实体重启证据。 |
| 17-03 | 通知/AlarmKit 授权、拒绝、恢复、投递、取消；锁定/解锁及各进程状态 | `PlatformBehaviorTests` 覆盖通知策略和去重；没有实体投递/锁屏记录 | `BLOCKED` | #17；需真实通知授权与锁屏矩阵。 |
| 17-04 | Live Activity 创建、更新、有效动作、过期/无效拒绝、关闭和提交后同步 | `MedicationReminderLiveActivityActionCommandTests` 覆盖保存失败、过期、关闭、延迟、动作 URL 往返及旧属性解码；没有锁屏/冷启动实体记录 | `BLOCKED` | #2、#17；需实体状态切换和未授权探针证据。 |
| 17-05 | iPhone Widget 刷新、空/过期/已完成渲染 | `MedicationWatchSnapshot` 的空态/过期/隐私投影及 Widget reload 路径有源码/单测证据；没有实体时间线截图 | `BLOCKED` | #17；需实体 Widget timeline 截图/日志。 |
| 17-06 | Watch 安装、首次同步、断开/重连、过期/完成传播、提醒授权投递、复杂功能刷新、午夜跨天 | `PlatformBehaviorTests.watchDeliveryQueuesLatestSnapshotOnceWhileOfflineAndSendsOnReconnect` 及快照状态测试通过；没有配对 Watch 硬件证据 | `BLOCKED` | #17；需配对设备，iPhone 仍是事实来源。 |
| 17-07 | 本地 AI 取消/重试；非医疗提示词的选择加入 Broker 成功及离线失败 | 本地响应策略和取消边界有 hosted 测试；CI 关闭 llama；无设备模型安装到首次响应记录 | `BLOCKED` | #6、#8、#28、#17；先满足可信 runtime 前置条件。 |
| 17-08 | 撤销 AI 同意并移除已授权上下文，不泄露健康信息 | `AIConsentRevocationCommandTests` 和上下文构建测试存在；没有设备交互/脱敏审计包 | `BLOCKED` | #12、#17；需设备与隐私证据。 |
| 17-09 | 账号、备份、天气展示与实际能力一致 | #4 的产品完整性要求仍未形成实体/账户验收 | `BLOCKED` | #4、#17；需产品选择和 Apple 账户证据。 |
| 17-10 | Records/就诊摘要入口、PDF 导出/分享生命周期、取消/失败清理 | #60 当前 exact-head CI 失败，且真机文件保护清单未完成 | `BLOCKED` | #15/#60、#17；先修复 PR #60 并重跑。 |
| 17-11 | VoiceOver 焦点/标签与最大动态字体覆盖关键 iPhone/Watch 路径 | 仅有少量 accessibility action 源码；UI smoke 只有 2 项，无完整 VoiceOver/XXXL 记录 | `BLOCKED` | #17、#52；需专门 UI/设备证据。 |
| 17-12 | #8 的延迟、帧率、内存测量与 Release 设备基线 | `docs/26-modelcontext-performance-baseline-20260825.md` 和 `ModelContextPerformanceTests` 记录自动化测量基础；无实体 Release 指标 | `BLOCKED` | #8、#17；不能用主观模拟器印象替代。 |

## 4. #28 本地模型安装到首次响应

| 检查 | 已证实 | 状态 |
| --- | --- | --- |
| 来源与安装完整性 | `LocalMedicalModelStore` 固定下载来源、文件扩展名、大小范围、精确字节数、SHA-256、重试/失败状态，并设置不进入备份；`LocalMedicalModelIntegrityTests` 覆盖完整性失败不替换已安装文件 | `PASS`（自动化边界） |
| 应用内下载进度与持久化 | `LocalMedicalModelStore.downloadModel()` 有进度状态和安装后重新解析；尚无干净安装实体录屏/日志 | `BLOCKED` |
| 真机 runtime | `LocalMedicalModelRuntime` 在未编译 llama 时明确返回 `runtimeUnavailable`；CI 使用 `MEDCUE_DISABLE_LOCAL_LLAMA=1` | `BLOCKED` |
| 离线安全响应 | `LocalMedicalAIClient` 有响应后处理、低质量/越界重试和取消检查；没有带真实 runtime 的实体首次响应证据 | `BLOCKED` |
| 可复核结论 | 当前只能写“未演示”，不能写“比赛演示已就绪” | `BLOCKED`；下一步为 #28 设备持有人提供非敏感前置条件并执行一次完整旅程。 |

## 5. #52 完整写入与视觉回归

[Issue #52](//github.com/Gavin8233841/medcue-ios/issues/52) 当前没有开放 PR。`MedicationAdherenceAppUITests` 在 `main@d5d5e692…` 只有两个 smoke 测试：主 Tab 可达性和首启跳过/下一步；它们不覆盖“建档 → 计划 → 服药 → 更正/重开”的完整写入链路，也没有截图基线/差异报告。故 #52 的三个验收项均为 `BLOCKED`，不能由现有 CI 绿灯推断完成。

最小协作请求已写回 Issue：先从当前 `main` 建立单独分支，明确 XCUITest 的持久化断言、合成数据、失败时不显示虚假成功，以及关键界面截图基线的存储和 CI 输出；不得接管 PR #60 或其他在途文件。

## 6. #33 中文优先 GitHub 界面

PR [#53](//github.com/Gavin8233841/medcue-ios/pull/53) 已合入（merge commit `93bdaf877cbcb339ff3d57a6c1c862e5ef511d80`），中文优先 README、模板、标签映射和开放 Issue 迁移已有远端读回记录。Issue #33 仍开放的唯一明确产品决策是 Topics 的精确词条：当前 Topics 为空，本文不猜测或写入词条。状态为 `BLOCKED`（owner decision），不是代码或 CI 阻塞。

## 7. YZY 开放 PR 门禁截面

规则集要求：`Native Verification (required result)` 通过、review threads resolved、禁止非快进；当前 ruleset 的 required approving reviews 为 `0`，但不因此跳过作者累计自审、fresh-context 安全审查、精确 HEAD CI、冲突检查或必要的设备/账户证据。

| PR | 精确 base → head | 远端状态/最近证据 | 状态与最小下一步 |
| --- | --- | --- | --- |
| [#49](//github.com/Gavin8233841/medcue-ios/pull/49)（Issue #47） | `d6aa4af85f225028fc3f912391328e1f745d0b34` → `01fedeca1bb031106928760eb8dd22a90614ca90` | `OPEN`, Draft, `BEHIND`, mergeable；旧 run [32645995638](//github.com/Gavin8233841/medcue-ios/actions/runs/32645995638) 在旧 base 上成功；五个源码包文件 | `BLOCKED`：先 rebase/更新到当前 `main@d5d5e692…`，再重跑 exact-head CI，完成结构性 `.mobileprovision`/`xcuserdata` 口径确认和累计审查。 |
| [#60](//github.com/Gavin8233841/medcue-ios/pull/60)（Issue #15） | `d6aa4af85f225028fc3f912391328e1f745d0b34` → `bd04d2a2784e98972a615cf37d76fef6accdfc3e` | `OPEN`, Draft, `CHANGES_REQUESTED`, `BEHIND`；run [32697674064](//github.com/Gavin8233841/medcue-ios/actions/runs/32697674064) Full Native/required 失败 | `BLOCKED`：按现有 review 修复尾随空白/EOF、ShareLink 完成/取消所有权、取消后确定性同步和真正注入属性检查失败，再以新 HEAD 重跑。 |
| [#63](//github.com/Gavin8233841/medcue-ios/pull/63)（Issue #61） | `d6aa4af85f225028fc3f912391328e1f745d0b34` → `9b10b5ab2742089bc393d418bdcb2a0b84d06b35` | `OPEN`, 非 Draft, `DIRTY/CONFLICTING`；run [32742602403](//github.com/Gavin8233841/medcue-ios/actions/runs/32742602403) 因 UI journey 等待“保存”超时失败 | `BLOCKED`：更新当前 main、解决冲突并修复/重现失败；不要在本线程抢写其治理审计文件。 |
| [#73](//github.com/Gavin8233841/medcue-ios/pull/73)（Issue #62） | `b0b376108df1097ee062f58ad27f879e97d2a2e5` → `f86cdfed82658c924fba9ebf0ece6b7136ce42ae` | `OPEN`, `DIRTY/CONFLICTING`；run [32802522062](//github.com/Gavin8233841/medcue-ios/actions/runs/32802522062) Full Native/required 失败；PR 自述新增 Swift 文件未加入 Xcode target | `BLOCKED`：从当前 main 重整 target membership、解决冲突，再重跑完整 exact-head gate。 |
| [#48](//github.com/Gavin8233841/medcue-ios/pull/48)（Issue #47 旧栈） | `15517b3649639539c05015970d2f6088df7426f9` → `e9749e7dd2451278fad4193aa827a0b722bc8d8d` | `CLOSED`, 未合入，2026-08-23 关闭 | `N/A`：仅保留历史证据；不得重复推进，#49 是替代 PR。 |

以上状态均来自 2026-08-31 的 GitHub 读回；旧 SHA 的成功 CI 不转移到当前 `main` 或新 HEAD。

## 8. 生态体验审计（只读）

### 已有一致性

- iPhone 是事实来源：`MedicationWatchSnapshotPublisher` 在提交后保存快照、刷新 Widget timeline，再通过 WatchConnectivity 发送；Watch 端保存快照并触发 Widget 刷新。
- Watch 快照已有首次同步、过期、空态、隐私态、开放/已处理排序和离线队列/重连发送逻辑；这些是自动化可证明的边界，不是硬件验收。
- Live Activity 动作测试覆盖提交失败抑制副作用、过期/关闭拒绝、幂等相关路径和提交后同步；外部 URL 信任模型仍由 #2 跟踪。

### 待产品确认的体验机会

- 用药动作按钮目前未发现 `sensoryFeedback` 或 `UIImpactFeedbackGenerator` 实现；适度成功/失败触感可能降低误触，但属于用药语义体验变更，不能在本证据线程直接添加。
- 现有长按和语音辅助主要服务 AI 对话归档/复制及撤回无障碍动作，不是用药动作的长按语音流程；需另立小范围产品决定和可访问性验收。
- Watch、Widget、Live Activity 共享快照/提交后同步方向一致，但锁屏、断连、时间线刷新和设备权限仍无实体证据。任何补齐应保持 iPhone 提交后事实来源，不新增旁路写入。

## 9. 协调阻塞审计与唯一下一步

截至本截面，没有发现由本协调线程引入的代码改动、文件重叠或 CI 失败；主工作区的既有脏文件被保留，未作为任何 PR 的证据。当前真实阻塞是：实体设备/Apple 账户不可用、#28 的 llama runtime 前置条件缺失、#52 尚未实现、#33 Topics 缺少持有者精确词条，以及 YZY PR 的旧基线/冲突/失败 CI。

唯一下一步：由设备/仓库持有人先提供一台在线且已配对的测试 iPhone/Apple Watch（使用虚构数据）和本地 llama runtime 前置条件；在此之前，保留本矩阵和 GitHub 协作请求，不宣称发布或真机验收完成。
