# MedCue 决赛产品计划（Finals Product Plan）

- 日期：2026-08-23
- 状态：当前有效（current）
- 权威基线：`main` @ `d6aa4af85f225028fc3f912391328e1f745d0b34`
- 关联：[Issue #45](https://github.com/Gavin8233841/medcue-ios/issues/45)、`CONTEXT.md`、`docs/PROJECT_STATUS.md`、`docs/TEST_STRATEGY.md`、`docs/DEVELOPMENT_WORKFLOW.md`

本文档固化进入决赛阶段的产品方向、工程边界与本阶段范围。`CONTEXT.md`
中的产品不变量（iPhone 是用药事实主源、AI 不能创建/停止/替换/改变药品
与剂量、云端共享 opt-in 可撤销等）优先于本文档任何表述。

## 1. 产品方向

主用户是**需要维持用药计划的一般用药人群**；适老模式是旗舰差异化能力，
而不是唯一用户群。竞品审计（2026-08-23，覆盖 Apple 健康、Medisafe、
MyTherapy、Dosecast、丁香园）显示五款对象均无官方 VoiceOver/大字体专项
承诺，适老专项属差异化空档，MedCue 的差异化主张成立。

决赛阶段固化的产品原则：

1. **低认知负担**：单一场景单一当前任务，关键路径步骤数可审计。
2. **诚实动作语义**：按钮与状态只承诺真实发生的行为；未确认不显示为已
   完成，失败必须可见且可解释。
3. **可靠、可更正闭环**：服用/推迟/跳过/更正/重开构成完整可审计闭环，
   错误动作可更正且留痕。
4. **普通模式与适老模式共用同一份数据**：适老模式是呈现与交互层的增强，
   不产生第二份用药事实。
5. **本地优先隐私**：用药事实留在本机；云端上下文共享保持 opt-in、限定
   范围、可撤销。

## 2. 本阶段范围边界

本阶段**只做**：

- 同机协助设置（在同一台 iPhone 上完成，供家属/照护者当面协助）；
- 本地适老闭环（适老模式的交互、可读性与确认语义在本机闭环验证）。

本阶段**不做**：

- 远程子女端、亲属远程查看或代管；
- 医生小程序或任何临床端；
- AI 模型能力扩展（不做诊断、处方或自主治疗语义）。

理由：消费级竞品仅提供只读共享/漏服通知，远程代管无成熟先例，且会放大
未确认语义的错误状态风险。此边界与 `CONTEXT.md` 的发布范围（竞赛评审 +
受控真机演示 + Beta）一致；不声称 App Store、临床或商业化生产就绪。

## 3. 适老模式 M1 路线

M1 由 [Issue #46](https://github.com/Gavin8233841/medcue-ios/issues/46)
承载：建立诚实未确认语义与单一当前任务原型。适老模式验收门槛（实机
证据为准，模拟器印象不构成证据）：

- 主按钮触控区域 ≥ 44×44pt（Apple HIG）；“使用更大的触控区域”开关必须
  真实生效（今日行内主操作按钮高度从 36pt 变为 ≥ 48pt），否则在生效前
  移除该开关。
- 动态字体放大至 AX5 时内容完整可读、不截断。
- VoiceOver 可分别聚焦确认与取消按钮，焦点顺序与语义正确。
- 关键文字对比度 ≥ 4.5:1，以 Accessibility Inspector 实机读数为准。

后续里程碑的 VoiceOver、动态字体与大触控区域门槛不得低于上述基线。

## 4. 工程边界与工具事实

- 本机标准工具链为 `/Applications/Xcode.app`，Xcode 27.0（Beta 5，
  Build `27A5237l`），构建/运行/模拟器交互使用 Xcode 27 自带的原生
  MCP 服务；旧的第三方 XcodeBuildMCP 已移除且不得恢复。决策与证据见
  `docs/adr/0002-xcode-27-native-mcp-toolchain.md`。
- 工程为 iOS 17.0 / Swift 6.0 语言模式，六个 Xcode target；架构角色与
  平台边界以 `CONTEXT.md` 与 `docs/PROJECT_STATUS.md` 为准。
- 交付流程、共享文件一文件一写者、串行集成顺序与合并门禁以
  `docs/DEVELOPMENT_WORKFLOW.md` 为准。
- 测试策略（风险分层证据、车道化 CI、精确 HEAD 门禁）以
  `docs/TEST_STRATEGY.md` 为准；迭代期跑聚焦测试加
  `tools/verify-native.sh --quick`，PR 就绪前跑完整 Native Verification；
  任何新 HEAD 必须取得新 CI 证据，旧 SHA 证据不传递。

## 5. 本地里程碑文档整合

以下本地里程碑文档已审查并随本计划一并进入权威 `main`：

- `docs/26-agent-chat-experience-uplift-plan-20260823.md`：智能体 Tab
  对话体验升级方案（提案，未实施；含开放 Issue 对照附录）。
- `docs/27-catpaw-parallel-collaboration-prompt-20260823.md`：并行协作
  提示词原件（历史协作记录，约束条款仍然有效）。

两份文档中的实现类提案不改变本计划的阶段边界；执行前仍需按其各自
关联 Issue 完成 Definition of Ready。
