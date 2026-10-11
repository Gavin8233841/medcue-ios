# P2 原生 UI 已证实断点的测试修复

> Historical implementation/design record, 2026-10-10. Stage labels identify evidence boundaries, not ancestors of this public-preparation branch. Original source/evidence mappings are retained separately. Current acceptance and publication status are in [plan.md](plan.md); no historical result proves this public revision passed.

基于首页Required `implementation-stage-05`、唯一Mac宏整合 `implementation-stage-06`。生产App、Settings、模式guard/alert宿主、剂量和初始化均不改；演示生产改动暂停。原adaptive-home-stage、pending-recovery-stage及Mac证据保留。

## 原生证据与归因边界

原生验证技术回报：固定P2树historical-reference-71构建成功、hosted7/7；Duo UI4过7失败；普通iPhone只有stdout2过5失败、封装中止exit-15，无完整xcresult。此证据不覆盖本HEAD或首页修复。证据ZIP下载失败，没有假称云端观看录屏；协调者独审的完整分类是本切片授权依据。

首启3例在一个Alert内部父子同标识Cancel/Enable歧义，未到持久化断言。legacy Duo停在错误整框包含断言，847宽按钮对669宽计算视口，尚未点击。电话录像只有120前缀，不能当完整草稿；模式开关未定位/点击。Skip实际Sheet没有标名取消；help后续未运行。设置开关已tap但无模式Alert仍待Mac最小tap/子控件命中实验，不能归为guard或宿主错误。

## 最小测试范围

| 文件 | 改动 |
| --- | --- |
| 新 NativeUITestActions.swift | 先唯一确切标题Alert，再唯一无同标识后代的叶按钮；未知/多leaf失败。NativeList只选前台可点击Table/CollectionView叶容器并受控滚动。Skip仅已知Sheet＋唯一确认身份，按存在的命名取消或可测外部区域关闭，必须验证关闭与导航可点 |
| ExperienceModeUITests.swift | mode取消/启用使用上面严格helper；完整号码输入、收键盘后完整保留与键盘消失前置断言；帮助号码和模式入口只滚设置List；skip/help路径保留owner/store断言。CompleteModeTestNavigation新增实际设置入口路径，仍核唯一可点、真实设置页和模式控件 |
| FirstLaunchCompletionUITests.swift | 首次Enable限定唯一标题Alert及唯一叶按钮；首次完成/强制回放/restart/store断言保留 |
| MedicationAdherenceAppUITests.swift | 仅testSettingsCanOpenElderMode：复用真实Profile→Settings helper，移除该旅程错误的整框包含定位调用，保留唯一可点/实际设置页/模式与适老内容断言 |

没有任意firstMatch去歧义、tab第5项、设备名分支、静默skip、timeout增加、断言删除、CI/PBX或其他journey修复。throws只传播严格定位失败。List未知容器或多个可点叶容器直接失败，不回落全屏乱滚；mode Alert不存在仍失败，不用延迟掩盖产品断点。

Apple官方[confirmationDialog](https://developer.apple.com/documentation/swiftui/view/confirmationdialog(_:ispresented:titlevisibility:actions:))说明regular环境使用弹层外点击关闭而非标准dismiss按钮。本候选将Duo实测无命名取消和该文档结合，为实际Sheet定义受几何约束的外部点击；**尚未原生验证这组AX bounds是否提供支持区域**。若没有，测试直接失败并保留证据，不随机点击、不推断关闭已成功。不能把API文档当本设备native pass。

## 验收与停止条件

云端检查生产路径与Mac宏文件字节保持、原测试方法集合/业务断言、diff空白及1400行；没有Swift/Xcode，UI helper及新调用均未原生编译执行。原生7hosted通过只属于Mac early-native-stage树；不称当前整合HEAD通过。

下一步独审核准此测试定位策略，收到设置最小分辨证据后再精确修对应层。普通iPhone结果封装未知单列，不自动重跑已执行旅程。若需要改Settings多个alert、生命周期/医疗/事务、模拟器/权限/凭据或扩大原生预算，停止并交接具体证据；没有该授权。

## Fixed-run return and one-case failure evidence instrumentation

The coordinator reports native compilation success and policy 21/21 on exact
`implementation-stage-09`. The Settings journey hit the true child Switch, presented mode
confirmation, cancelled/confirmed, entered elder mode and preserved it on restart.
Its subsequent elder Settings sheet stopped at the unique foreground List
assertion; the remaining Duo/ordinary journeys were not run. This is not a pass
for this newer diagnostic commit or for the demo source snapshot.

The delivered video reportedly shows the expected help-contact auto-positioning.
The delivered event plists contain synthesized events, not candidate AX property
values. No locator change or product auto-positioning change is justified yet.

`NativeListTestActions.reveal` now captures failure evidence before asserting
candidate count (including zero or multiple), before a target/list intersection
failure, and before the final bounded-scroll assertions. The foreground selector,
scroll directions/bounds, and all assertions remain unchanged. Every candidate's
exists/enabled/hittable/frame and direct/descendant table/collection counts are
read independently, then complete app/target/list/window/sheet/navigation debug
hierarchies and an unvalidated screenshot are attached with keepAlways. A black
screenshot is invalid visual evidence; hierarchy values remain independent.
Capture is limited to launch arguments identifying a valid synthetic fixture,
mode and session UUID. It does not capture ordinary user sessions or make a
failed test pass. No timeout, retry, production or medication logic change.

Cloud verification: diff check and source-only scope checks. Native attachment
capture and its compilation are not run here. Next native run is the same formal
Settings singleton once, with this exact source; inspect real candidate values
before choosing any test-locator repair. Keep all prior failure artifacts.

## Settings-owned scroll host repair after exact AX capture

The native validation owner supplied a diagnostic technical return.
Its `native-frame-007` text has SHA-256
`6fd88091b2b93ff4f75243d54023e32bdbfb6febee0e7ea7d70cc5d4e3f08aef`.
The unique CollectionView exists and is enabled, has positive frame
`(149, 8, 653, 661)`, and has zero direct/descendant tables or collections.
Only `isHittable=false` rejects it. It contains the Settings help phone/save
controls; its mode Switch has not yet scrolled into AX. The Settings presentation
is nested Others, and `app.sheets` is empty. These are the coordinator's exact
native evidence findings; cloud did not operate Mac or execute this repair.

`revealSettings` is an explicit separate path for the Settings mode Switch and
help phone field. It requires the unique Settings navigation bar, Settings
identifiers and a unique deepest common Other owner, removing qualifying outer
wrappers rather than assuming a fixed hierarchy depth or an AX Sheet. Within
that owner it requires exactly one existing/enabled native List with finite
positive frame, no nested native List and known Settings descendants. A normal
hittable owned List is accepted without requiring help fields. Only this owned
path accepts a non-hittable container, and then only with an enabled/hittable
known Settings control or unique interactive navigation Done button.

The existing two directions and six gestures per direction remain bounded.
Every iteration rebuilds owner/List/target queries. A visible target must be
unique globally, in the current owner and in its List, enabled/hittable and
intersect the List frame; the mode action still verifies its unique direct
Switch leaf. Missing/ambiguous/misowned targets fail with the preserved synthetic
keepAlways attachments. Original generic List selection and its failure capture
remain byte-for-byte unchanged, including Profile scrolling. No background
elder scroll fallback, arbitrary firstMatch, guessed pixel gesture, timeout,
retry, production help positioning or business assertion changes.

Cloud checks cover source composition, unchanged generic helper/capture/leaf
logic, unchanged test method inventory and business assertions, whitespace and
scope. Swift compilation and whether swipe synthesis works on the owned
non-hittable container remain native validation requirements. The formal
Settings journey should reveal the Switch, cancel/confirm and preserve the
existing mode/store assertions on both eligible destinations; on failure retain
the new exact owner/List evidence rather than broadening this helper again.

The native query API is documented by Apple in
[descendants(matching:)](https://developer.apple.com/documentation/xcuiautomation/xcuielement/descendants(matching:))
and [XCUIElementTypeQueryProvider](https://developer.apple.com/documentation/xcuiautomation/xcuielementtypequeryprovider).
Those API definitions do not establish a runtime pass for this repair.
