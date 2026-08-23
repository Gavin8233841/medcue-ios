## 关联 Issue / Linked Issue

Closes #

## 协作 / Coordination

- 工作负责人 / Work owner: @
- 工作状态 / Work state: 进行中 / Active；交接 / Handoff；待评审 / Ready for review；需修改 / Changes requested
- 分支 / Branch:
- 预期文件 / Intended files:
- 重叠的开放 Pull Request / Overlapping open Pull Requests: 无 / None；串行顺序记录在 Issue #
- [ ] 我已在编辑前检查 Issue 负责人、标签、最新有效评论、当前 `main` 和开放 Pull Request 文件列表。 / I checked the Issue assignee, labels, latest meaningful comments, current `main`, and open Pull Request file lists before editing.
- [ ] 没有活动 Pull Request 占用预期文件，或协调代理已在继续工作前记录串行集成顺序。 / No active Pull Request owns an intended file, or the coordinating agent recorded the serial integration order before work continued.
- [ ] 实现进行中时 Issue 带有 `state:in-progress`，或已在 GitHub 中记录发布/转移。 / The Issue has `state:in-progress` while implementation is active, or the release/transfer is recorded in GitHub.
- [ ] 如果这是交接，最新状态记录了完整 base 和 HEAD SHA、脏文件、已推送检查点、完成的检查、阻塞项和一个后续动作。 / If this is a handoff, the latest status records the full base and HEAD SHAs, dirty files, pushed checkpoint, completed checks, blockers, and one next action.

只使用合成或已清理的证据。不要填写真实用药记录、健康信息、API token、设备标识符或绝对路径。
Use synthetic or sanitized evidence only. Do not include real medication or
health records, API tokens, device identifiers, or absolute user paths.

## 问题与结果 / Problem And Outcome

描述用户或工程问题，以及预期的可观察结果。 / Describe the user or engineering problem and the intended observable result.

## 范围 / Scope

- 范围内 / In scope:
- 范围外 / Out of scope:

## 变更风险 / Change Risk

分类 / Classification: 常规 / Routine；标准 / Standard；安全关键 / Safety-critical；外部或难以逆转 / External or difficult to reverse

原因及额外的评审、威胁、回滚、设备或账号证据 / Reason and any extra review, threat, rollback, device, or account evidence:

## 验收证据 / Acceptance Evidence

- [ ] 验收标准已映射到结果 / Acceptance criteria are mapped to results.
- [ ] 最后一次已跟踪文件变更后，我使用与任务风险相称的最强可用模型/推理能力，检查了完整的 base-to-HEAD 累积 diff 和当前 Pull Request 正文。 / After the last tracked-file change, I reviewed the complete base-to-HEAD cumulative diff and current Pull Request body using the strongest available model/reasoning appropriate to the task risk.
- [ ] base SHA、head SHA、Pull Request 正文和成功 CI 证据都描述当前版本；没有声称任何待定或已过时的结果。 / The base SHA, head SHA, Pull Request body, and successful CI evidence all describe the current revision; no pending or superseded result is claimed.
- [ ] 重点自动化测试通过 / Focused automated tests pass.
- [ ] 选定 lane 的 exact-head 检查通过；native/full lane 或 `main` push 还通过完整 `tools/verify-native.sh` / The selected lane passes at the exact HEAD; native/full lanes and `main` pushes also pass the complete `tools/verify-native.sh` gate.
- [ ] `tools/verify-native.sh --quick` 通过，或在 Windows 等无 macOS/Xcode 环境中如实记录不可用原因 / `tools/verify-native.sh --quick` passes, or its unavailable macOS/Xcode prerequisites are recorded honestly.
- [ ] 所需真机/账号检查已完成，或说明理由后标记 N/A；只有 Draft Pull Request 可以保留待完成证据。 / Required physical-device/account checks are complete or marked N/A with a reason. Pending evidence is allowed only while this Pull Request is Draft.
- [ ] 安全关键工作已完成新上下文独立评审，或说明理由后标记 N/A。 / Fresh-context independent review is complete for safety-critical work, or this is marked N/A with a reason.
- [ ] 默认自主合并门已满足：累计自审、Issue 指定模型 fresh-context 复审、Blocker 0 / Required 0、exact-head CI、current-main 集成和所需外部证据；否则已记录例外并唤醒协调者 / The autonomous-merge gate is satisfied, or an exception is recorded and the coordinator is notified.
- [ ] 适用的竞赛、知识产权、依赖许可和署名检查已完成，或说明理由后标记 N/A。 / Applicable competition, intellectual-property, dependency-license, and attribution checks are complete or marked N/A with a reason.

基础版本 / Base revision:

拟议版本 / Proposed revision:

CI 运行 URL 与准确 head SHA / CI run URL and exact head SHA:

命令与结果 / Commands and results:

```text

```

独立复审 / Independent review:

- 模型 / Model:
- 完整审查 HEAD / Reviewed full HEAD:
- 结论 / Result: Blocker 0 / Required 0 / Suggestions / Questions

## 风险评审 / Risk Review

- 数据/持久化/迁移 / Data/persistence/migration:
- 医疗安全/隐私/安全 / Medical safety/privacy/security:
- 性能/无障碍/本地化 / Performance/accessibility/localization:
- 竞赛/知识产权/依赖许可/署名 / Competition/IP/dependency-license/attribution:
- Watch/Widget/通知/Live Activity 影响 / Watch/Widget/notification/Live Activity impact:
- 回滚或恢复 / Rollback or recovery:

## 残余风险与后续工作 / Residual Risk And Follow-Up

列出明确限制和关联的后续 Issue。不要把相邻工作隐藏在本 Pull Request 中。
List explicit limitations and linked follow-up Issues. Do not hide adjacent work
inside this Pull Request.
