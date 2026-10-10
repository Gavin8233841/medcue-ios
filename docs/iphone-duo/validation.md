# Validation status — Issue #161

Date: 2026-10-09 UTC. Base: `4d9c6d50d46a5735dc014da5434e1063d8cf7493`.

## Current validation route — 2026-10-09 06:45 UTC

The product owner explicitly requested: “不在 ipad 验证，保持用 device hub”. Device Hub remains the authoritative route for subsequent Duo validation. Confirm its available connection, SDK/runtime, supported operations and exact source revision before claiming execution; no new Device Hub build, posture or acceptance result is established by this change.

All dedicated iPad validation, reruns, polling and iPad-specific test/export optimization are paused until the owner explicitly requests resumption. The `synthetic-native-evidence` job in `adaptive-visual-evidence.yml` is disabled with literal `false &&` ahead of its unchanged original guards. Its workflow, helper, permissions, concurrency, action references and prior evidence are retained; the existing full Native workflow and all product/test sources remain unchanged.

Everything below is historical evidence or a superseded iPad execution plan. Prior iPad results remain valid only for their recorded scope and revision, never as Duo acceptance. Pausing the lane does not turn failed, skipped or unexecuted checks into passes. Static pause-condition and preservation checks do not establish Device Hub readiness or native acceptance. Resumption requires an explicit owner request and review of the restored condition.

## Candidate evidence before native CI

- Two existing product files changed; three independent test files added. No workflow, project-file, permission, medical rule, frozen path, or persistence-command change.
- `git diff --check` and repository Swift source-size check passed on the combined candidate.
- Independent static reviews closed identified source findings: stale scanner metadata filtering, real SwiftUI anchor coverage, wrapping long identity labels, same-process failure retry, honest log-association scope, strict iPad geometry assertions, and hosted-view fixture/AX checks.
- Static review does not establish Swift compilation, successful tests, visual quality, or hardware compatibility.
- This Linux authoring environment has no Swift/Xcode. The quick native preflight stopped at missing `plutil`; no native pass is claimed.

## New tests and execution requirements

| Suite | New methods | Intended execution | Current status |
| --- | --- | --- | --- |
| BarcodeScannerGeometryTests | 14 Swift Testing tests | Existing app-hosted unit-test lane | Authored and statically reviewed; not yet run |
| MedicationDetailAdaptiveLayoutTests | 3 XCTest tests, 8 host states | Existing app-hosted unit-test lane, ordinary iPhone destination | Authored and statically reviewed; not yet run |
| AdaptiveWindowStateUITests | 3 XCTest tests | iPad Simulator with measurable window rotation | Authored and statically reviewed; not yet run |

The current CI's iPhone UI destination will skip all three iPad-only tests. A green overall run cannot count those as coverage. Their acceptance requires 3 passed, 0 skipped on an appropriate iPad destination. No workflow changes are included.

The detail tests mount the real production view with synthetic in-memory SwiftData. A 1024-point hosted container is not a physical iPhone or Duo screen. AX labels/frames do not prove visible text is untruncated or buttons perform the intended action. Screenshots are attached to the test result for review, but the current workflow has no success-artifact upload; creation of attachments must not be reported as persistent external screenshot delivery.

Camera aspect-fill/format readiness and actual scanning require native camera evidence. iPad rotation does not establish folding, Split View, or Device Hub posture behavior. Duo SDK/runtime and physical-device evidence remain open.

## Frozen candidate content

These content hashes bind the completed static reviews, not successful native results. Later changes invalidate the corresponding prior evidence and require review again.

| File | SHA-256 |
| --- | --- |
| `ios-app/MedicationAdherenceApp/MedicationAdherenceApp/Views/BarcodeScannerView.swift` | `af49f9a7b18349bebd0cffb6c258022c450f22a86ba99e6e21fc9c8c4f5bb030` |
| `ios-app/MedicationAdherenceApp/MedicationAdherenceApp/Views/MedicationDetailView.swift` | `8265cff9295f182de1a49f2bb80d8c7de11b69fb19d50cd89e6469bb366c9ae2` |
| `ios-app/MedicationAdherenceApp/MedicationAdherenceAppTests/BarcodeScannerGeometryTests.swift` | `70bc00c5f6ba33bf094e61841bd5e8280b597e6694d52f0e781c366b30f0b842` |
| `ios-app/MedicationAdherenceApp/MedicationAdherenceAppTests/MedicationDetailAdaptiveLayoutTests.swift` | `77b5993d9d70f09898d82aa9dc1e53ec599bcbd1caebaaef6a62e8569b9fedbb` |
| `ios-app/MedicationAdherenceApp/MedicationAdherenceAppUITests/AdaptiveWindowStateUITests.swift` | `114b4fe068a838395090932a68a563ca24cf4b4a5ae3b4067636564926beb9ed` |

## First native attempt and corrective candidate

Run [37875757005](https://github.com/Gavin8233841/medcue-ios/actions/runs/37875757005), attempt 1, failed in the main App Release build on 2026-10-09. `MedicationDetailView.detailPhotoActions` contained a local declaration followed by a view expression without an explicit return. No new native test suite executed; Broker tests passed 38/38. The failure is retained and is not reclassified as a successful validation.

The corrective candidate adds only `return` to that getter. Its source SHA-256 is `fff0e28dad70131c2d560108ac7d2bd15be4d1ef237e35f1d5e540b307d96ac5`; the earlier table binds the original candidate. All test contents and the scanner source are unchanged. A new commit and new CI result are required before claiming the compile error is resolved.

## Second native attempt and typed test constants

Run [37876262950](https://github.com/Gavin8233841/medcue-ios/actions/runs/37876262950), attempt 1, passed the native build suite and Swift Core 161/161, plus Broker 38/38. The iOS test targets then failed to compile two ambiguous `.infinity` expressions in `BarcodeScannerGeometryTests`; none of the 20 new tests executed. These were compile failures, not test skips.

The next candidate qualifies the two constants as `CGFloat.infinity` and the adjacent `.nan` as `CGFloat.nan`. Independent review confirmed exactly these three type qualifications, with all product code unchanged. New scanner-test SHA-256: `1b49285f0b77f346d3ba4652af10cf00620273b10c3ab82ba6db44750e885d15`. New-revision CI remains required; prior build results do not substitute for it.

## Third native attempt: product build and scanner proof; hosted AX gap

Run [37877340598](https://github.com/Gavin8233841/medcue-ios/actions/runs/37877340598), attempt 1, completed with overall failure at branch `539da969e24531ef1e1cd2b05515043eaa072707`; actual checkout was merge `851964685334967c3e8969e4c54ce0dd14b52753`, with the same tree `6f2e72d694b2486ddc82a6f908e0494d1977b06c`.

- All native build stages passed; Broker 38/38 and Swift Core 161/161 passed.
- All 14 new BarcodeScannerGeometryTests ran and passed. iOS Swift Testing total: 327/327.
- Hosted XCTest total: 7 executed, 4 passed and 3 new detail tests failed with `visibleAccessibilityDidNotStabilize`. Combined iOS unit count: 334 executed, 331 passed, 3 failed; the existing 317-test baseline passed.
- UI: 40 test entries, 37 baseline passes and 3 actual iPad-only skips on iPhone 17 Pro/iOS 26.5. This is not iPad coverage.
- No artifacts were uploaded. The AX-helper failure lacks enough observations to assign a product-layout root cause.

The follow-on candidate binds the synthetic test window to an existing foreground UIWindowScene and adds bounded AX/geometry diagnostics. It preserves the original three-second deadline, stable-array requirement, test assertions, fixture checks and screenshot names. New detail-test SHA-256: `3ef6800b9ad12809db196a835c07a34de6b4c100de4f203dddc12c9189ec523b`. It has only static review so far; it is not yet a proven fix.

## Additive iPad and image-evidence lane

Issue161 authorizes the new `adaptive-visual-evidence.yml` and `tools/iphone-duo-evidence/` slice. The existing full workflow/classifier is unchanged and still required. The additive lane only runs this public repository's same-branch PR162, on standard macos-26 with preinstalled Xcode26.6/iOS26 iPad, using read-only permissions and non-persistent checkout credentials.

The helper requires 3 real-detail tests plus 3 iPad window tests to execute and pass without skips; validates exact test identities and 24 explicit synthetic screenshots; rejects unknown schemas/paths/links/invalid PNGs; sanitizes into fresh staging; and retains at most20MB for one day. It does not publish raw result bundles, logs, device metadata, databases, or automatic screenshots. Test-source changes require a reviewed fingerprint update. Original test failures are retained, with only bounded reconstructed diagnostics.

Independent security review and 25 standard-library positive/negative tests passed in Linux. Actual macOS CLI/schema/ImageIO, iPad test execution, image generation and visual review remain pending. Any unknown format or failed test stops publication. This lane provides iPad rotation/native hosted-view evidence, not Duo posture or hardware certification.

## First additive-lane run: two preflight failures retained

At revision `d2dc36967f594473db87d827ec41476c64c76576`, [Native37880316719](https://github.com/Gavin8233841/medcue-ios/actions/runs/37880316719) stopped at the unchanged source-package rule because two negative-test strings contained a synthetic private-directory literal. [Visual37880316767](https://github.com/Gavin8233841/medcue-ios/actions/runs/37880316767) passed 25 boundary tests, then rejected the actual SDK schema root before selecting an iPad or running tests. Neither produced native test or image evidence.

The packaging fixture now uses its own TemporaryDirectory to generate an absolute path without embedding a private-user directory. The scanner is unchanged. The schema guard remains fail-closed; its new bounded diagnostic can expose only the fixed SDK's static `--schema` response, never a result bundle. The next run must establish the actual shape before an explicitly reviewed adapter can accept it. Twenty-seven Linux boundary tests pass; no native schema compatibility claim is made.

## Second additive-lane run: observed static SDK schema and reviewed adapter

At checkout `743598a1ac158e769eeb1337553b43049c910fe8` (tree
`df180bde40e02b7f52f4b3138c09066bff366e0c`),
[Visual37881518599](https://github.com/Gavin8233841/medcue-ios/actions/runs/37881518599)
passed 27 Linux-compatible boundary tests on the macOS runner, then failed
closed at `Unknown result schema root`, before simulator selection or native
test execution. Its real helper step began at 2026-10-09 03:56:08.421533Z;
the subsequent bounded diagnostics provided only the installed Xcode 26.6
static Summary and Tests schemas. The original extracted JSON SHA-256 values
are `0842cd791603c9184f8287a14db249a9f824f8fa7b3b7797dbfa8d801929e4b7`
and `845dd3ca1936c50dab17e1cf945d221ad48f162121d36b41070011f77f218f10`,
respectively. These are static SDK definitions, not actual result payloads;
no native test pass, screenshot or uploaded artifact is established by this run.

The follow-on, independently reviewed adapter recognizes the exact observed
`schemas.Summary` and `schemas.Tests` structures through canonical whole-schema
fingerprints. Unknown schema changes remain rejected. Structural TestNode
recursion is not expanded; real-result depth and identity checks remain in
force. The adapter adds no dependency, permission, product/test-source change,
or workflow change. Its 29 Python boundary tests include the sourced static
SDK fixtures and rejection cases. A new macOS run must still establish native
result and attachment compatibility, actual test passes, ImageIO sanitization,
and screenshot delivery before any visual review or device claim can follow.

## Hosted observation failure and explicit test-scope split

At branch `743598a1ac158e769eeb1337553b43049c910fe8`, Native run [37881518605](https://github.com/Gavin8233841/medcue-ios/actions/runs/37881518605) confirmed all native builds, Core161 and iOS SwiftTesting327 (including scanner14) passed. XCTest had four existing passes and three detail failures. All three report rawAX=0 despite a visible, key, foreground-scene-attached host and a mounted List; adding a scene did not fix the observation method. The overall run and UI result were still pending when this entry was written. These failures are preserved, not rewritten as layout passes.

The replacement hosted suite explicitly proves render/trait/scroll/store invariants instead of inaccessible semantic AX. It retains eight states, requires stable finite geometry, overlapping traversal to actual boundaries, midpoint-specific sampling, 24 correctly sized images and unchanged full fixture snapshots. Its names now state that narrower scope, and image suffix `information` becomes `middle`. Source SHA256: `d3ad82df4c9486e2cd4de15304b9f5ab29d4acdebdaf4c6778dc70d4adead0a2`.

A separate two-test real-app XCUITest suite uses existing synthetic complete/due fixtures, public out-of-process snapshots and actual navigation. It checks six exact static-text markers independently of action labels, four enabled/hittable/fully visible controls, scrolling/return, measured iPad portrait-landscape-portrait changes, and only the limited fields exposed by the existing read-only inspector. Its six iPad images sample the top only. Source SHA256: `ca885b70c979a8a293606ec5b0e88bd93f4e0c08b8ed7aa95eea3f82ed7f1c56`.

Both candidate files passed independent source review, not native execution. Column placement, all long-text clipping, RTL visual order, full control coverage across every hosted state and Duo hardware/posture acceptance remain open. The evidence helper must require all three suites (3+3+2 tests) and the exact 30-image inventory; existing full CI remains required. Actual-image review remains necessary before any frontend quality claim.

## First render-invariant execution and scroll-oracle correction

At `dc47658f3151d7a838d9ebf036ef18e5da118de1`, [Visual37884466207](https://github.com/Gavin8233841/medcue-ios/actions/runs/37884466207) failed its first hosted suite and exported no artifacts; subsequent window/AX stages did not run. Full Native iOS-unit logs in [37884466190](https://github.com/Gavin8233841/medcue-ios/actions/runs/37884466190) confirm all three hosted tests failed with 503 cascading assertions, while SwiftTesting327 and the four pre-existing XCTest cases passed. Full builds and Core161 passed; overall/UI completion was still pending when written.

The trace identifies a midpoint rounding bug: a target317.1667 can render at317, within the existing1pt target tolerance but below the exact midpoint capture predicate. This prevented capture and repeatedly requested the same coordinate. Narrow first-step offsets also moved from requested183.350 to256.333 (AX5) and215.900 to268 (ordinary/RTL). The exact backing-layout cause is not established by these observations.

The reviewed correction uses the existing1pt tolerance to recognize an interior midpoint; it never accepts top/bottom as middle. A single3s seek deadline requires three stable observations actually at the requested coordinate, reissuing a still-valid fixed target after layout adjustments and recomputing explicit boundary targets from current geometry. Invalid progress, gaps or incomplete traversal throw at the first failure instead of cascading. No increased tolerance, extended deadline, skips or empty-observation pass is introduced. Test/attachment names, renderer and complete store snapshots are unchanged. New hosted SHA256: `6ca65ac4c148e461c69a112c7ae8b7718546702b0f6792b8e13373f651eaf8ff`; exact independent review found no remaining Required/Blocker. Native execution remains required.

The same dc476 Native run subsequently ended failure: UI37 baseline passes,3 actual iPad-only skips and2 new detail-AX failures. Both new tests tapped the medication tab and selected the nonempty interrupted group, then failed to reach the expandable medication-group button. They never entered detail; no detail semantic or screenshot claim follows. Both runs had zero uploaded artifacts.

A diagnostic-only candidate preserves the exact selectors,15-swipe budget and assertions while naming the failed navigation stage and sampling only the known synthetic medication-tab subtree before search and on exhaustion. Samples are bounded to20 nodes/120 characters per text field; no full OS tree, new image/text attachments, product seam or medication action is added. The actual runtime group label/type is still unknown, so no speculative selector correction is claimed. Candidate SHA256: `6f7429ed6f1b50e54bbb9263e8c4ad4d21e0f873eafaaa958ee774819ff6e6a6`; independent delta review found no Required/Blocker. Source fingerprints are updated to the exact reviewed hosted and AX candidates, not relaxed.

## Fixed-step traversal and separately labelled partial evidence

At `466c55ef0671a4b101fc7535e5c75f5a493e8074`, Visual37887886915 returned0 from the hosted and window xcodebuild invocations, then65 from accessibility; it exported no artifact. Exit0 alone is not a verified exact-suite pass count. Ordinary iPhone Native unit reported two hosted passes and one AX5-1024 failure: a traversal jump from3748.667 to5025.333 exceeded the750pt viewport. The latter coordinate equals the newly measured bottom, demonstrating that a previously bounded step followed a dynamically changing bottom after lazy content height increased.

The independently reviewed correction freezes each already planned step coordinate, then remeasures extents for the next overlapping step. Existing1pt tolerance, three stable samples,3s deadline,100-step limit, interior midpoint/current-bottom completion, image contract and store snapshots are unchanged. Hosted SHA256: `a5b0a8f2d83b37055e6ed835313b6b6632a8917f21d2a48626781a30438075cb`; native execution remains pending.

The additive evidence helper now validates each successful suite immediately and can retain a complete prior successful hosted24-image set when a later native suite fails. Its status manifest and README explicitly label PARTIAL, fixed suite passed/failed/not_run states, null unverified counts, exact source and A16 simulator destination; original failure exit status stays nonzero. No failed-suite images are eligible. Any schema, identity, PNG, source, public-repository or other guard failure blocks all publication. Readiness is false initially and only becomes true after verified fresh staging; child tools cannot inherit Actions command-file handles. Only then may the workflow upload even though the native step remains failed; no continue-on-error is used. Existing full CI is unchanged.

The five-file helper/workflow delta passed independent security review and44 Linux tests. This establishes fail-closed control flow, not native format compatibility or actual artifacts. Full visual acceptance still requires real image inspection and the outstanding semantic/device tests.

The466c55 full UI run ended with37 baseline passes,3 window skips and2 new detail failures. Bounded runtime observations now distinguish the accessible group container (type Other, custom comma-delimited label, value已折叠) from its visually overlapping Button (different combined label and empty value). The old button-only query searched the container's label and therefore could not match. Both font cases show the same distinction. Flat diagnostic samples do not independently prove runtime parent-child ancestry.

The reviewed candidate queries a unique tab-scoped group, then its unique button, requires the group to become已展开 before selecting a unique medication row, excludes the actual toggle label, and still requires the real detail destination. The scoped child query is a fail-closed hypothesis to verify natively, not a claimed runtime pass. All text/control/store/rotation assertions remain. AX SHA256: `282aa6554910805c78a195e14ab6ea8d8205b2b45802802a67660199d3600728`. No artifact exists from466c55.

## First complete hosted pass and opaque attachment metadata projection

At `7a1afb95f25838b29bcc09f06f7bebec79bd4ca6`, full Native37891012701 iOS-unit succeeded: all three hosted methods (eight states), four pre-existing XCTest cases and327 SwiftTesting tests passed. Builds, Broker38 and Core161 passed. Full UI was still pending when this entry was written. This proves the narrowed render/geometry/store contract, not visual or semantic acceptance.

Visual37891012742 attempt1 stopped before native execution on an HTTPError with unknown status/cause. After public repository visibility was independently verified, one same-head failed-job retry was accepted; no other retry was requested. Attempt2 reached hosted then window exit0, passed their immediate exact3-method/0skip result validations, then AX exit65. These passed counts follow the verified guard control flow; raw result JSON was not printed. Partial export then stopped at an unexpected attachment-item metadata field, with zero artifacts. No AX/visual pass follows.

Independent security review concluded that rejecting all opaque extra attachment metadata adds brittleness without protecting the selected pixel boundary. The explicit reviewed contract now projects only known required fields: string exported file/name and an explicitly present Booleanfalse failure flag for selected images. Unknown item fields are not read, traversed, used for selection, copied, logged or staged. Root/row shape, exact test/name inventory, source fingerprints, path/link checks, PNG bounds/re-encoding, public-repository and partial-status gates are unchanged. Missing/renamed/malformed consumed fields still fail. Failure diagnostics use only fixed known-field presence/type enums and a capped count, never arbitrary field names or values.

This four-helper-file change passed independent implementation review and48 Linux positive/negative tests, including nested forged metadata and missing/non-Boolean failure flags. It does not claim the full actual SDK manifest has been observed or native image export has succeeded. Actual artifacts and image inspection remain pending.

The7a1afb full UI run subsequently ended with both new iPhone detail-AX methods passing. Total42 entries:38 passed (36 baseline+2new),3 iPad-only skipped,1 existing baseline failed at the five-second settings phone-field existence check before any settings value/save assertions. The logs do not establish transient failure versus regression; that frozen test/source is unchanged. The complete native gate therefore remains failed despite new feature checks passing.

A16 detail-AX failure reason was hidden by the original bounded diagnostic filter. An independently reviewed diagnostic-only extension maps25 fixed source message prefixes, including three known navigation-stage names, into fixed reason codes. It forwards no labels, values, arbitrary suffixes, paths or raw lines; unknown messages remain withheld and the20×400 bounds remain. The combined helper candidate passes51 Linux tests. This is observation improvement, not an A16 repair. Native export compatibility and the A16 failure cause remain to be established.

## Ordinary native gate passed; Device Hub remains the active acceptance route

At `c56c927e6e5b04e17a59a9120bd815fe7b554160`, [Native37894657868](https://github.com/Gavin8233841/medcue-ios/actions/runs/37894657868) completed success, including the required aggregate result. Actual PR merge checkout was `123b943d78dab043510f7a7010c798264a996396`; source tree `64b4e3de0978ec6f2a9db7f1ae1fde90abc0313f`.

- Three native builds, Broker38 and Core161 passed.
- iOS unit334 passed:327 SwiftTesting, four existing XCTest, three hosted detail tests covering eight states.
- Ordinary iPhone UI42 entries:39 passed (37 baseline+2 detail AX),3 iPad-only skips,0 failures. The previously failing settings check passed in this run; its earlier failure remains historical evidence, not erased or assigned an unproven cause.
- Visual37894658067 was cancelled to honor the Device Hub direction. No artifacts were uploaded by either run, and no iPad/Duo acceptance is claimed.

This passing revision proves its ordinary native gate only. Device Hub screenshots, true Duo runtime/posture behavior and visual review remain outstanding. The following workflow/docs-only pause revision does not alter product or test source; its own exact-head checks are tracked separately.

## 2026-10-10 根导航独立候选：源码与测试准备

基线 `dbb67d8aa17487ca096fba7f86fc557de1596880` / tree `ef0aa8bb3b5b69c0fe42cf1a1e6933a827019ab9`。本轮在独立 `codex/161-duo-navigation-candidate-20261010` 候选工作目录进行，未改原 PR 分支、未推送、未合并、未发布。此前 helper/patch 在当前执行器缺失，本轮 session 为重新实现，不能沿用此前8项检查结论。

### 范围及协作

- 当前 #113 HEAD 经 GitHub 核实仍为 `2a96d8d89b51fc5c25d364e2f19960ab65e6cb6d`；AppRoot 的 DEBUG fixture 段相对本轮基线逐字节不变，只有药品 tab 的宿主改动。#113 未被合并或完整导入。
- 当前 #73 HEAD 仍为 `903f67ee1a77531c5874f5638688de39ab6a851e`。保留其药品搜索增量和两个搜索算法，未导入风险页、App 初始化、UI fixture 或 workflow。生产 helper 因 PBX 独立所有权而临时放在已编译 MedicationsView 内，用 `MedicationBrowseSearchTextNormalizer` / `MedicationBrowseSearchIndex` 命名，算法经去 imports/类型名映射后与该 SHA 相同；对应原测试仅重命名。日后正式串行集成 #73 时用其正式 helper 替换并删除这些临时类型，避免重复定义。#73 尚未合并。
- 单一 NavigationSplitView 使用 preferredCompactColumn 的系统 Back，真实 MedicationDetailView 仅按药品 UUID 改身份。过滤列表不作为删除依据；全量 @Query 的 ID 移除才清除失效选择。没有新增保存、网络、医疗建议或持久化状态。
- Tests 和 UITests 均为现有文件系统同步根组，因此新增测试无需 PBX 修改；这证明发现机制，不代表已经编译或执行。

### 已执行的云端检查

- `git diff --check`：通过。
- `tools/swift-source-size-check.sh`：通过，1400行门槛不变。
- `python -B tools/test-source-package.py`：9/9 通过。此为打包工具回归，不是 Swift 测试。
- 45 个冻结路径零交集；`native-verification.yml`、暂停的 `adaptive-visual-evidence.yml`、PBX 与基线字节相同。
- `tools/verify-native.sh --quick`：未通过启动前置条件，实际报 `required command not found: plutil`。当前执行器没有 Swift、Xcode 或 iOS runtime；未绕过此门禁，未执行原生编译/测试。

### 已编写但尚未执行

- 14项 session 状态测试：选择/返回锚点、搜索/生命周期过滤、折叠状态、隐藏与显式删除、无自动选中、重复事件和重新选择。
- 从 #73 精确来源改名的搜索算法回归测试。
- 4项普通 iPhone Simulator 真实 App 测试：默认字号搜索—详情—返回—同 UUID 再选—清除恢复折叠；AX5 恢复展开；编辑名称后取消、返回、现有存储检查、重启检查原名称与 UUID；两药 fixture 中返回后选择不同 UUID，核对真实详情名及两个任务。仅使用合成 fixture，没有真实健康数据。

### 必须保留的原生验收缺口

本轮不能声称原生“主流程已接入通过”。候选需准确修订的完整 native CI 及独立审查；之后通过现有 Device Hub 验证实际 Duo SDK/runtime 支持的宽窄与 AX 转换。iPad专项继续暂停，不以 iPad 旋转代替。

重点原生脚本：
1. 默认与 AX5 完成四项新 App 测试，确认系统 Back 实际返回、搜索不丢、重复选择同 ID 可再次进入。
2. 有足够内容预算的 regular 容器实际并列显示列表与真实详情；窄容器/AX字号单栏，药名、按钮及侧边系统控件不裁切。实际列宽由系统决定，源码阈值不是设备尺寸；核验首次宽窗口展示及用户隐藏 sidebar 后的行为，保留系统控制。
3. 已选药品进入其风险详情等更深页面，Back 后选择另一药品，再重复开合；旧详情路径不得遮盖新选择或残留上一药品 sheet。
4. 编辑草稿、系统权限说明和添加流程的弹层打开时改变尺寸；检查同一草稿、操作目标、取消零写入及保存恰一次。仅保持同一 `.id` 不能证明 SwiftUI 系统宿主不会重建。
5. 筛选隐藏已选药品时详情保留；归档不是删除；实际删除成功后不再显示失效详情，失败不能伪装成成功。
6. 长列表返回锚点、VoiceOver 焦点、RTL、后台/恢复和 tab 往返需要实际证据。新单药品fixture只能检查选中行可见，不证明任意长列表滚动精度。现有检查器只能观察 task/log/counter 与取消后的药名，不能证明完整数据库无变化。

硬件姿态、相机、系统栏、物理性能和真实用户体验仍未验收；不增加新依赖、凭据或付费资源。对比基线的独立提交可回退。

独立新上下文生产源码审查：Blocker 0 / Required 0，仅为源码候选审查，不是原生验收。审查文件 SHA-256：AppRootView `81f470f044a439b376345d92226d4f4bb5acc4320ea2346caf681700919c8fe7`；MedicationsView `7a271244f13dda8467b5e56cbe623eae7fda9af9e5e357d1dd5b845c5ba279e8`。累计源码与最终测试仍须准确提交的完整门禁。

最终4项 UI 测试源码另经独立新上下文复核：Blocker 0 / Required 0，文件 SHA-256 `98580e7c95e4c207b5f313b3d55f5422c0a507a3b9ac194851568b68ec343f1c`；这仍不证明编译、运行或界面验收。
