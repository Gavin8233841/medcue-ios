# 决赛范围与待办收口

> 截至 **2026-10-05 13:24 UTC** 的范围评估。表格是处理建议，不表示 Issue 已关闭、PR 已合并或原生/设备验收已经完成。

## 目标与版本

本轮聚焦竞赛演示和可复核交付：诚实用药事实、可靠可更正闭环、隐私与医疗边界、适老可达性、现场稳定性。全产品扩展、长期规模优化和广泛架构重构可后排；不以“非商业上线”为理由省略已启用能力的安全边界。

- [仓库](https://github.com/Gavin8233841/medcue-ios) main：[`4d9c6d50d46a5735dc014da5434e1063d8cf7493`](https://github.com/Gavin8233841/medcue-ios/commit/4d9c6d50d46a5735dc014da5434e1063d8cf7493)
- 开放31个 Issue、14个 PR；准确 HEAD 的 workflow 为13个 success、#73 failure
- 范围依据：[决赛产品计划](https://github.com/Gavin8233841/medcue-ios/blob/4d9c6d50d46a5735dc014da5434e1063d8cf7493/docs/FINALS_PRODUCT_PLAN.md)
- 单项 CI 通过不等于完成所有验收、组合主线通过或真机就绪

## 全量待办决策表

A＝核心/安全责任保留；B＝可独立云端推进；C＝原生/设备证据或既有候选串行整合；D＝建议本轮 not_planned；E＝先核对所有者/协作者意见。A/C也可能包含高优先级安全项。当前没有需要另开实现的独立B项。

| Issue / 标题 | Owner；当前状态 | 类别 | 本轮建议与收益依据 | 关联实现/依赖 |
| --- | --- | --- | --- | --- |
| [#2 【P1】【安全】确保只有经授权的 Live Activity 交互才能修改剂量状态 / [P1][Security] Ensure only authorized Live Activity interactions can mutate dose state](https://github.com/Gavin8233841/medcue-ios/issues/2) | Gavin8233841；OPEN / 进行中 | C | 保留：已合入代码修补；仍需系统入口、旧活动和锁定/冷启动证据 | #97/#102 已合并；#14/#17；共享测试与 #113 串行 |
| [#7 【P1】【质量】自动化“创建计划-服药-纠正”用药流程 / [P1][Quality] Automate the create-plan-dose-correction medication journey](https://github.com/Gavin8233841/medcue-ios/issues/7) | Gavin8233841；OPEN / 进行中 | A | 保留：核心建档→计划→服药→撤销→重启闭环；#113 正式复审未收口 | #113 开放；#73/#52 共享测试后续串行 |
| [#9 【P2】【医疗 AI】将 LocalMedicalResponsePolicy 变为内聚且经过测试的边界 / [P2][Medical AI] Make LocalMedicalResponsePolicy a cohesive tested boundary](https://github.com/Gavin8233841/medcue-ios/issues/9) | Gavin8233841；OPEN / 进行中 | A | 保留并优先：继续保留现有安全验收与评审要求，覆盖最终展示/持久化 | #132/#140 开放；既有 #99/#105–#108 切片已合并 |
| [#10 【P2】【架构】将 AI 请求生命周期置于经过测试的会话所有者之后 / [P2][Architecture] Move AI request lifecycle behind a tested conversation session](https://github.com/Gavin8233841/medcue-ios/issues/10) | 未指派；OPEN / 已阻塞 | D | 建议 not_planned：AI 会话整体架构重构收益间接，暂不扩大改动面 | #1/#6/#12 已关闭；#8 基线；#11 下游；无直接实现 PR |
| [#11 【P2】【性能】为 AI 观察设界并按需加载会话历史 / [P2][Performance] Bound AI observation and load conversation history on demand](https://github.com/Gavin8233841/medcue-ios/issues/11) | 未指派；OPEN / 已阻塞 | D | 建议 not_planned：长历史分页/观察性能工程不属于已确定演示负载 | #10 仍开放；#1 已关闭；#8 基线；无直接实现 PR |
| [#14 【P1】【隐私】定义锁屏用药可见性与解锁要求 / [P1][Privacy] Define lock-screen medication visibility and unlock requirements](https://github.com/Gavin8233841/medcue-ios/issues/14) | Gavin8233841；OPEN / 已阻塞 | C | 保留：代码层隐私策略已落地，系统展示与升级清理仍待观察 | #97 已合并；#2/#17 |
| [#16 [P1][Governance] Verify and retire the writable GitHub deploy key](https://github.com/Gavin8233841/medcue-ios/issues/16) | yzy1020；OPEN | E | 待所有者决定：外部依赖及安全操作授权未闭环，保留协作者认领 | yzy1020 认领；账号所有者外部依赖确认；无实现 PR |
| [#17 【P1】【发布】执行最小真机系统验收矩阵 / [P1][Release] Execute the minimum physical-device system acceptance matrix](https://github.com/Gavin8233841/medcue-ios/issues/17) | 未指派；OPEN / 已阻塞 | C | 保留：按实际演示能力收窄执行矩阵；缺少的设备证据继续如实标注 | #74 是已合并证据文档；#2/#14/#28 等系统边界 |
| [#18 【P2】【架构】将 Add Medication 创建与导入置于可测试的工作流所有者之后 / [P2][Architecture] Move Add Medication creation and import behind a tested workflow owner](https://github.com/Gavin8233841/medcue-ios/issues/18) | 未指派；OPEN / 已阻塞 | D | 建议 not_planned：添加药品整体工作流重构后排；具体解析修复继续 | #7 开放；#1 已关闭；#145/#146 独立保留；无重构 PR |
| [#19 【P2】【架构】将 Today 剂量交互置于可测试的生命周期协调器之后 / [P2][Architecture] Move Today dose interactions behind a tested lifecycle coordinator](https://github.com/Gavin8233841/medcue-ios/issues/19) | 未指派；OPEN / 已阻塞 | D | 建议 not_planned：Today 生命周期重构后排；用药闭环和触觉候选继续 | #2/#7 开放；#1 已关闭；#137/#138 独立保留；无重构 PR |
| [#20 [Debt] Decouple locale-independent state from localized text](https://github.com/Gavin8233841/medcue-ios/issues/20) | Gavin8233841；OPEN / 进行中 | A | 保留：真实单位/状态/跨进程语义不能随全产品英语化一起取消 | #114 开放；#148 保留；#109/#110/#115/#125/#128 已合并 |
| [#21 [Feature] Deliver complete English product surfaces across every MedCue bundle](https://github.com/Gavin8233841/medcue-ios/issues/21) | Gavin8233841；OPEN / 已阻塞 | E | 暂缓、保持开放：先核对历史认领及未交接工作，再决定全产品英语化范围 | 历史 CatPaw 认领；#20/#22；无直接实现 PR；#114 不撤销 |
| [#22 [Feature] Make the Medication Assistant bilingual without weakening safeguards](https://github.com/Gavin8233841/medcue-ios/issues/22) | Gavin8233841；OPEN / 已阻塞 | A | 保留安全责任：完整英文 AI 功能可后排，当前混合语种/受控降级不能丢失 | #9/#20；历史 codex/22-bilingual-safeguards 认领；无直接开放 PR |
| [#28 【质量】在真机上验证本地模型从安装到首次响应的旅程 / [Quality] Prove the local-model install-to-first-response journey on device](https://github.com/Gavin8233841/medcue-ios/issues/28) | Gavin8233841；OPEN / 进行中 | C | 保留、条件排期：先明确是否演示端侧模型，离线/来源/重试/设备未完成 | #112 Draft；#111/#133 已合并；普通构建默认 runtime stub |
| [#46 【M1】【适老模式】建立诚实未确认语义与单一当前任务原型](https://github.com/Gavin8233841/medcue-ios/issues/46) | Gavin8233841；OPEN / 进行中 | C | 保留：旗舰适老基础已合入，仅补缺失系统边界，不重复开发已合并子项 | #78/#86/#87/#100/#101 等已合并；#50/#17 |
| [#50 【Feature】适老模式「需要帮助」动作：经系统确认界面拨打预设号码](https://github.com/Gavin8233841/medcue-ios/issues/50) | Gavin8233841；OPEN / 已阻塞 | C | 保留：应用内证据不等于系统电话确认；Simulator 能力受限仍是边界 | #46 实现已在 main；#17；系统电话边界未验 |
| [#52 【Quality】完整写入流程 XCUITest 与视觉回归基线](https://github.com/Gavin8233841/medcue-ios/issues/52) | yzy1020；OPEN / 已阻塞 | E | 待协作者确认：只优先关键写入/视觉证据，先完成共享 UI 测试文件交接 | yzy1020；#113 → #73/#52 按共享文件串行 |
| [#61 【P2】【治理】建立可复核的 GitHub Issue 健康度审计 / [P2][Governance] Add a reproducible GitHub Issue health audit](https://github.com/Gavin8233841/medcue-ios/issues/61) | yzy1020；OPEN / 已阻塞 | E | 待协作者确认：治理工具优先级低于产品闭环；#90 交接和正式 review 未收口 | yzy1020；#90；旧 #63/#79 关闭未合并 |
| [#62 【P2】【体验】为药品与风险列表添加局部搜索 / [P2][UX] Add scoped search to medication and risk lists](https://github.com/Gavin8233841/medcue-ios/issues/62) | yzy1020；OPEN / 已阻塞 | E | 待协作者确认：搜索可后排，但当前导航失败未解决，不能按已完成关闭 | yzy1020；#73；#113 UI 测试、#112 隐私文档交接 |
| [#124 [P2][UX] Stabilize AX5 medication overview tile navigation and its UI check](https://github.com/Gavin8233841/medcue-ios/issues/124) | 未指派；OPEN | C | 保留：AX5 导航间歇性失败未定因，重跑成功不等于修复 | #113 Dashboard、#73 MedicationsView及共享测试 |
| [#127 [P2][AI UX] Investigate intermittent third-party notice dismissal at AX5](https://github.com/Gavin8233841/medcue-ios/issues/127) | 未指派；OPEN | C | 保留：首次 AI 告知页关闭偶发失败，不能绕过授权或仅延长等待 | #112/#136 AI 视图与 #113/#73 共享测试 |
| [#130 [P1][AI UX] Unify Medical Assistant chat layout and interaction after #117/#121](https://github.com/Gavin8233841/medcue-ios/issues/130) | Gavin8233841；OPEN / 已阻塞 | C | 保留最小验收：首批外观修正已合入；长回复/键盘/运行方式需真实画面核对 | #131 已合并；#112/#136 文件交接；#127 独立 |
| [#135 HealthKit 回顾与智能体证据链：扩展只读指标、可靠统计和独立共享范围](https://github.com/Gavin8233841/medcue-ios/issues/135) | 未指派；OPEN | C | 保留现有候选：本地事实回顾；HealthKit/隐私系统证据与组合整合待交接 | #136，且与 #112 有3个路径重叠 |
| [#137 【P2】【体验】为今日已提交动作添加克制、诚实的触觉反馈](https://github.com/Gavin8233841/medcue-ios/issues/137) | Gavin8233841；OPEN | C | 保留现有候选：触觉是可选增强，真实触感、系统开关和无障碍尚待验证 | #138；与 #19 整体重构独立 |
| [#139 [P2][AI] 修复本地回复解析的 Unicode 索引错位](https://github.com/Gavin8233841/medcue-ios/issues/139) | Gavin8233841；OPEN / 进行中 | C | 保留现有修复：已复现 Unicode 解析错误，准确单项 CI 不替代组合验收 | #140；#9；不替代 #132 |
| [#141 【P2】【技术债】降低本地回复清理表达式的类型检查复杂度](https://github.com/Gavin8233841/medcue-ios/issues/141) | Gavin8233841；OPEN | C | 保留现有修复：最小表达式拆分支持组件验证；不宣称 App 性能提升 | #142；首次UI失败与同源重跑成功分别保留 |
| [#143 【P2】【交互】取消提醒权限说明后允许继续编辑并重新保存计划](https://github.com/Gavin8233841/medcue-ios/issues/143) | Gavin8233841；OPEN | C | 保留现有修复：取消权限说明后恢复保存，避免核心演示流程锁死 | #144 |
| [#145 【P2】【导入】完整匹配规格型号标签，避免规格草稿混入标签残片](https://github.com/Gavin8233841/medcue-ios/issues/145) | Gavin8233841；OPEN / 进行中 | C | 保留现有修复：规格草稿文字准确，仍要求人工确认，不扩张 OCR 医疗能力 | #146；不完成 #18 重构 |
| [#147 【P2】【库存】按既有等价剂量单位正确计算消耗](https://github.com/Gavin8233841/medcue-ios/issues/147) | Gavin8233841；OPEN | C | 保留现有修复：既有单位别名影响库存估算，不扩单位换算 | #148；不完成 #20 全部语义迁移 |
| [#149 【P2】【复诊导出】完整纳入所选末日的最后一秒，明确半开日期边界](https://github.com/Gavin8233841/medcue-ios/issues/149) | Gavin8233841；OPEN | C | 保留现有修复：复诊导出必须准确覆盖所选日期，不能丢失末秒记录 | #150 |
| [#153 适老模式：扩大成功反馈撤销按钮的标签触控区域](https://github.com/Gavin8233841/medcue-ios/issues/153) | Gavin8233841；OPEN / 进行中 | D | 建议 not_planned：尚未形成 PR 的 Undo 56pt标签微调暂缓，原撤销能力保留 | 无关联 PR；远端候选分支仍等于 main；无新增提交 |

合计：A 4、B 0、C 17、D 5、E 5。建议首批收口仅 **#10、#11、#18、#19、#153**；#21 保持开放，待历史认领对账。

## 五项 not_planned 建议理由

### #10 AI 请求生命周期整体重构

当前要求将发送、取消、重试、迟到事件、提交顺序与恢复收进独立会话所有者，属于跨页面/服务的架构工程。暂缓它能控制决赛前回归面，优先完成已确定的核心旅程及医疗边界修补。

没有直接实现 PR；正文历史依赖 #1/#6/#12 均已关闭，不能继续写成现存阻塞。#11 依赖本项。关闭原因应为“本轮不计划整体重构”，不应写成“已修复”。现有取消、撤权和保存失败保护继续保留；#9/#22/#127/#132 不受影响。

来源：[Issue #10](https://github.com/Gavin8233841/medcue-ios/issues/10)

### #11 长会话历史与观察范围性能工程

当前范围是有界上下文、历史按需加载、归档状态正确性，以及长历史内存/延迟对照。本轮尚未确定必须支撑的大规模长期会话演示负载；此时启动分页和观察体系改造的决赛收益低于闭环与稳定性修补。

没有直接实现 PR；依赖 #10 及 #8 的相关基线。暂缓不授权删除或截断历史，也不放宽发送时的授权范围。出现实测演示卡顿或明确负载后再重开；不宣称已经达到性能目标。

来源：[Issue #11](https://github.com/Gavin8233841/medcue-ios/issues/11)

### #18 Add Medication 工作流所有者重构

当前要求统一手动/OCR/条码/照片、权限、取消、保存和提醒派发的生命周期，涉及广泛状态和接口。决赛前优先最小可复现修复与端到端证据，暂缓整体结构调整。

没有直接重构 PR；#7 尚未完成。规格标签错误已有独立 #145/PR #146，继续保留。人工复核、事务创建、过期结果拒绝、重复保存防护及保存后副作用顺序均不变；不删除现有输入和导入能力。

来源：[Issue #18](https://github.com/Gavin8233841/medcue-ios/issues/18)、[PR #146](https://github.com/Gavin8233841/medcue-ios/pull/146)

### #19 Today 生命周期协调器重构

当前要求统一确认、剂量动作、瞬时反馈、撤销期限、回滚、取消与系统同步。其收益主要是长期可测试性和维护性，暂不作为决赛前必须新增的整体重构。

没有直接重构 PR；#2/#7 仍保留。#137/PR #138 仅是触觉切片，也继续保留。not_planned 不改变剂量、提醒、撤销、更正、幂等及“提交成功后才反馈”的既有规则。

来源：[Issue #19](https://github.com/Gavin8233841/medcue-ios/issues/19)、[PR #138](https://github.com/Gavin8233841/medcue-ios/pull/138)

### #153 Undo 按钮标签触控微调

实际范围仅为 ElderDoseSuccessFeedback 的按钮标签：多行、居中、整行宽、最小56pt及矩形命中形状；拟议差异8 added/1 deleted，不改变撤销回调、文案、identifier、可见条件或10分钟窗口。

当前没有关联 PR；[认领分支](https://github.com/Gavin8233841/medcue-ios/tree/codex/153-elder-undo-target)仍为 main `4d9c6d50`，没有新增提交。正文明确真实几何、边缘命中、小屏/AX5及VoiceOver均未验证。目前没有证明主线 Undo 违反最低触控要求或阻断演示，故先收口已准备候选，暂缓此微调；后续若观察到触控困难，应按证据重开。现有撤销能力、候选原件和分支保留。

来源：[Issue #153](https://github.com/Gavin8233841/medcue-ios/issues/153)、[认领记录](https://github.com/Gavin8233841/medcue-ios/issues/153#issuecomment-5970067383)

## 必须保留的范围与交接

- **#21 暂不关闭**：存在历史认领，需先核清未交接工作。全产品英语化与已有英语能力、比赛英文材料、#114 Watch语义/双语候选是不同范围；现有能力不删除
- **#22/#9 保留当前安全责任**：完整英文功能可以后排，当前共享边界的混合语种、受控降级与最终保存责任不能一起撤销
- **#132 保留**：继续保留现有安全验收与评审要求；不以单项CI成功代替全部验收。来源：[PR #132](https://github.com/Gavin8233841/medcue-ios/pull/132)
- **#113 保留**：HEAD `2a96d8d8` 的 [CI成功](https://github.com/Gavin8233841/medcue-ios/actions/runs/36464962234)，但现有正式 `CHANGES_REQUESTED` 尚未收口；[PR正文](https://github.com/Gavin8233841/medcue-ios/pull/113)要求当前累计差异重新评审
- **#112/#28 保留并按演示需求排期**：已有一次 Simulator 安装到回答观察；断网、受控失败/重试、运行时来源和设备边界仍未齐，不因优先级降低宣称完成
- **yzy1020 的 #61/#90、#62/#73、#52/#16 不抢关**。#90 实时非Draft、正文旧Draft状态不一致；[2026-09-30交接请求](https://github.com/Gavin8233841/medcue-ios/pull/90#issuecomment-5909927615)尚无后续确认。#73 最新 CI failure，另有未完成的搜索导航问题
- **#2/#14/#17/#46/#50 保留真实系统证据界限**。源码、mock、成功重跑或已合并的文档不能代替锁屏/通知/电话/设备验收

## 已准备的八项候选

下列8个 Draft PR 共45个不同变更路径保持原有交接范围，本轮范围收口不改其代码或撤销候选。最终组合仍需独立原生验证；#136 与 #112 存在3个重叠路径，按既有 owner 串行整合。

| PR | 对应 Issue | 准确源 HEAD | 单项 CI |
| --- | --- | --- | --- |
| [#136](https://github.com/Gavin8233841/medcue-ios/pull/136) | #135 | `85f7cd630d9b15267a10b7d7a622f47e028d30ac` | [success / attempt 1](https://github.com/Gavin8233841/medcue-ios/actions/runs/36981956573) |
| [#138](https://github.com/Gavin8233841/medcue-ios/pull/138) | #137 | `96ec3bc80a30f35507f7489e6d52c0ecc7f34cf9` | [success / attempt 1](https://github.com/Gavin8233841/medcue-ios/actions/runs/36916758246) |
| [#140](https://github.com/Gavin8233841/medcue-ios/pull/140) | #139 | `d62501be2d6282290aec06e54edd8db4126d1719` | [success / attempt 1](https://github.com/Gavin8233841/medcue-ios/actions/runs/36920146368) |
| [#142](https://github.com/Gavin8233841/medcue-ios/pull/142) | #141 | `18cce1ff0b1134bc06ad51af79093b362ca392c7` | [success / attempt 2](https://github.com/Gavin8233841/medcue-ios/actions/runs/36924836778) |
| [#144](https://github.com/Gavin8233841/medcue-ios/pull/144) | #143 | `b07a21a08c14b9b25dd2e3adc2dd62b90b21cda3` | [success / attempt 1](https://github.com/Gavin8233841/medcue-ios/actions/runs/36935296012) |
| [#146](https://github.com/Gavin8233841/medcue-ios/pull/146) | #145 | `858f8a277415daa5ea373ea43c9bace0f79ac8d6` | [success / attempt 1](https://github.com/Gavin8233841/medcue-ios/actions/runs/36936050402) |
| [#148](https://github.com/Gavin8233841/medcue-ios/pull/148) | #147 | `77452f5882fa2b111b9e2fb04d48d857db9797fc` | [success / attempt 1](https://github.com/Gavin8233841/medcue-ios/actions/runs/36948111885) |
| [#150](https://github.com/Gavin8233841/medcue-ios/pull/150) | #149 | `683c54c4a808560b4b7c0350c9e1b1b9e25a6893` | [success / attempt 1](https://github.com/Gavin8233841/medcue-ios/actions/runs/36948443286) |

#142 的 attempt1 UI失败仍是有效历史；attempt2成功只说明同源码重跑通过，不证明原失败根因已修复。

## 收口原则

建议项以 `not_planned` 表达本轮范围，不以 `completed` 表达修复完成。记录理由和来源，保留代码、分支、历史与候选原件；若出现新的实现、认领答复或安全事实，先重新评估对应项。

不以开放Issue数量或测试数量折算产品完成百分比。验收分别记录实现、准确提交CI、组合集成、系统/设备证据及演示范围。

