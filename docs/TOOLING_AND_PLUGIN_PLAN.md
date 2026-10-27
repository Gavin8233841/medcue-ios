# MedCue 本机工具与插件计划

工具链基线核对：2026-08-23；规范与 skill 适用范围更新：2026-09-07。
本次规范更新不代表重新完成了下述 Xcode、模拟器或真机验收。

工具用于缩短“理解—修改—验证”循环，不能替代源码、测试、真机证据或用户理解。

## 工作区硬边界

- 唯一活动仓库：`/Users/Admin/Developer/MedCue/appcontest-2026-prep`；
- `/Users/Admin/Desktop/appcontest-2026-prep` 及迁移目录只读；
- 不在只读目录创建分支、worktree、构建产物或修改；
- 恢复任务先运行 `git rev-parse --show-toplevel`，路径不一致就停止。

## 当前 Xcode 基线

- `/Applications/Xcode.app`：Xcode 27 Beta 5，build `27A5237l`；
- `xcode-select`：`/Applications/Xcode.app/Contents/Developer`；
- Swift：Apple Swift 6.4；iPhoneOS 与 watchOS SDK：27.0；
- iOS 26.5 与 watchOS 26.5 Runtime 已验证可用；
- Xcode Intelligence 的 `Allow External Agents to Use Xcode Tools` 为 `Always`；
- Xcode 原生 MCP 已验证可读取工程并执行原生 RunProject；Release、Demo 和 iOS 26.5 模拟器路径已由前序任务验收。

这些证据只说明当前本机工具链可用，不自动证明未来提交的代码、真机行为、签名或发布产物正确。除非当前变更的验收需要，不重复完整 Release、Demo 和 MCP 全流程。

## Xcode 操作规则

- 优先使用 Xcode 27 自带原生 MCP 读取工程、Scheme、构建、测试和模拟器状态；
- 命令行 fallback 直接使用当前 `xcode-select` 指向的工具链，不写死旧下载路径；
- 旧 Build iOS Apps 插件和独立 XcodeBuildMCP 已移除，不安装、不恢复、不调用；
- 不启用或读取旧 Xcode 回退副本；回退需要产品负责人另行明确决定；
- 不自动升级部署目标、改签名、清理 DerivedData 或修改工程设置来掩盖失败。
- 当前 Xcode 27 暴露的 Watch SDK 名称是 `watchsimulator27.0` 和
  `watchos27.0`；`tools/verify-native.sh` 的本机默认值仍是 26.5。脚本完成
  独立治理前，本机完整门禁须通过其公开环境变量传入上述已验证名称；CI
  已传入通用 `watchsimulator` 和 `watchos`，不受该本机默认值影响。

## 当前需要的能力

- 产品设计：用于收敛用户问题、最小旅程和无障碍验收；
- Xcode 原生工具：用于 SwiftUI、Preview、构建、测试和模拟器证据；
- GitHub：只读协作跟踪、Pull Request、评审和准确提交 CI；
- Documents / Presentations：只在决赛材料进入对应里程碑时使用。

只有出现可复现问题时才启用专项性能、内存或自动化工具。当前不因“可能有用”安装额外插件，也不让工具扩大账号权限、上传源码或处理真实健康内容。

## Skill 使用范围

- 按本次任务选择技能，先核对描述、所需文件和可用工具；没有对应需求时不加载全文、不执行整套流程。
- 通用视频、设计或演示文稿请求不自动选择某个框架。优先沿用现有项目和用户已选工具；HyperFrames 的流程仅用于实际采用 HyperFrames 的交付，不接管 SwiftUI 开发。
- 多个入口描述同一能力时，选一个与当前任务和工具版本匹配的来源，不叠加运行。安装数量不代表必须启用的流程数量；目录整理或插件移除另行明确范围。
- 已有资料足以完成小改动时，复用现有风格和约定。skill 的访谈、文档模板或推荐步骤不能自行变成用户未要求的审批门。
- 不因恢复项目、预览或小改动而顺带升级依赖、安装 CLI、开通账户或启用外部传输；按当前任务的必要性和已有授权判断。
- 若 skill 引用的脚本在当前分支不存在，报告准确缺项；使用已存在且适用的验证入口。不得从其他工作树直接运行替代版本来证明当前分支，也不得伪造脚本或绕过强制门禁。
- 2026-09-07 核对：当前本地分支的 `medcue-pre-commit-ci-check` 所需 `tools/run-pre-commit-checks.sh`、`tools/test-pre-commit-system.sh`、`tools/install-hooks.sh` 和 `docs/pre-commit-checks.md` 均未落入此工作树。其实现由开放的 PR #77 管理；使用前重新核对分支文件，不能把 skill 可见性当作检查系统已就绪。
- `19-codex-plugin-restore-prompt.md` 和 `20-codex-full-skill-plugin-recovery.md` 是历史恢复资料，不是每次任务的安装清单。仅在明确的恢复需求下，依据当前工具帮助和授权范围使用。
- 如 skill 导致暂停或额外确认，说明具体文件、条款及未满足的条件。项目安全规则和明确用户授权始终适用。

## 隐私边界

- 不读取或输出密钥、`AISecrets.plist` 内容、GGUF 内容、用户数据库、健康数据或设备标识符；
- 不把真实健康数据放进提示词、截图、日志或测试夹具；
- 只报告工具名称、版本、启用状态和脱敏结果，不输出令牌、请求头或敏感环境变量；
- 不绕过密钥保护，不用插件输出替代医疗、隐私或发布证据。

## 每次变更的最小工具验收

1. 先核对仓库、分支、准确 HEAD、工作树和文件重叠；
2. 只运行能证明当前小步的聚焦检查；
3. 原生代码迭代运行相关测试与 `tools/verify-native.sh --quick`；
4. 整合前运行完整相关门，并记录准确提交；
5. 真机、账号或外部服务行为单独记录，不用 Simulator 或源码审查代替。

## Agentic Coding Build-Cache Safety (2026-09-01)

The local storage audit verified a build-cache growth failure mode. The largest
observed tree was the nested `.codex-build/codex-46-elder-mode-m1/.codex-build` directory:
it contained a full Git worktree inside a build-output namespace, and the
worktree then accumulated 122 separately named Xcode output directories. The
pure Xcode cache portions were at least 70.5 GiB; the source worktree, logs,
test-result bundles, attachments, and untracked source changes are not cache
and must not be removed with it.

The root cause is verified from the current scripts and captured build logs:

- `tools/verify-native.sh` creates the requested `VERIFY_NATIVE_ROOT` and its
  child directories, but does not prune a prior run. Its unit and UI test lanes
  place `-derivedDataPath` below that root.
- `tools/run-local-model-smoke.sh` defaults to a repository-local
  `.codex-local/local-model-smoke-derived-data` path and also keeps the full
  Xcode output until an owner-approved cleanup.
- Repeated agentic coding runs used a new descriptive namespace for each retry,
  review, font-size check, and visual check, such as
  `.codex-build/elder-layout-ui-edge-v2` and
  `.codex-build/exact-elder-ui-regular-after-fix`. Each namespace kept its own
  Build, index, module cache, SDK cache, package checkout, and logs.
- A full worktree placed below `.codex-build` made every relative output path
  resolve below another `.codex-build`, producing the nesting and rapid growth.

Required prevention rules:

- Never place a Git worktree or source clone below `.codex-build`. Use the
  canonical repository or the approved `Developer/MedCue/worktrees/` location.
- For ordinary CLI or automated Xcode work, use the governed external cache
  location `Developer/MedCue/cache/Xcode/DerivedData/`. The existing
  repository-local `.codex-local` verification exception remains in force
  until it is changed through an approved Issue.
- Reuse one stable DerivedData namespace per active workline. Do not create a
  new namespace merely to distinguish a retry. Preserve the small evidence
  outputs needed for review, not a full DerivedData tree for every attempt.
- Before a high-volume validation loop, record the absolute repository root,
  branch, HEAD, `git status --porcelain=v2`, and the exact output root. Stop if
  the root is under `.codex-build`, the output root changes unexpectedly, or
  the governed cache budget is exceeded.
- After evidence is recorded, review exact paths before removing only
  regenerable Build, index, module-cache, SDK-cache, and Swift package cache
  files. Preserve source, `.git`, models, secrets, device data, redacted logs,
  required `*.xcresult` evidence, and required attachments.
- Do not move build caches, simulator data, `.git`, or application support data
  to iCloud. If an uncommitted workline is at risk, back up its Git bundle or
  patch to iCloud before any cleanup; do not treat iCloud as a build cache.
