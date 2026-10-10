# #163 P1 首启桥撤除与教程 purpose

> Historical implementation/design record, 2026-10-10. Stage labels identify evidence boundaries, not ancestors of this public-preparation branch. Original source/evidence mappings are retained separately. Current acceptance and publication status are in [plan.md](plan.md); no historical result proves this public revision passed.

基线 HEAD `c791f11ad1a4e6fc4e7ff94554c05bec1f8c5119` / tree `051b5814a121a66742381c900a0570996a8df88f`。本切片保存到独立 `unpublished-implementation-branch` 本地commit；准确结果修订以独审交付的Git SHA与source包manifest为准。

## 当前行为

- 删除 FirstLaunchCompletionBridgeView 定义及挂载；真实首次完成同步写首次完成键并关闭引导，取消Task不再留下动画busy。260ms/840ms视觉等待删除。
- FirstLaunchSetupView 调用方显式传 purpose。真首次是「跳过/开始使用」；已经完成的强制教程与HelpCenter重看是「关闭/完成」。root重看关闭不重写首次完成键或切换tab，HelpCenter只关闭自己的cover。
- demo写入的实际busy独立为isStartingDemoMode，保持引导禁用并显示实际操作进度；没有伪造首屏初始化完成。
- 模式选择、二次确认、首页/Settings迁移、加载呈现和五药隔离尚未落地。既有演示按钮的rebuildAndExit危险路径仍是历史代码，本切片没有执行；在隔离方案完成前不能用它导入真实库。

## 文件与保留证明

App源码只动 AppNavigationViews.swift、AppRootView.swift、FirstLaunchSetupView.swift、Views/HelpCenterView.swift；新增 FirstLaunchCompletionUITests.swift。PBX、Today、Settings、seeder、schema、工具/工作流、旧Duo文档没有改动。

AppRoot的Watch host、startup task、LiveActivity消费、repair/reconcile与integrity方法、提醒重试、DEBUG fixture/inspection与药品split导航均要求与基线字节一致；MedicationAdherenceApp init/恢复文件完整保持。保留700/1400ms协调等待及demo300ms等待，不把它们误删成视觉等待。现有Guide内部教学动画不是本次删除范围。

## 验收与真实证据范围

新增原生UI suite `FirstLaunchCompletionUITests`（测试目录已绑定filesystem同步target，尚未由原生运行证实发现）：

1. 真首次skip → restart无再次引导 → 已完成elder用户强制教程final CTA → restart仍elder；前后fixture task IDs/status/due-offset、log/help/save/schedule计数相同。
2. complete首次skip → 真实Today帮助入口 → HelpCenter教程关闭 → 返回HelpCenter/Today → restart首次状态保留；前后同一组fixture可观察存储字段相同。

使用现有multiple隔离session store与可写suite；不传 `-hasCompletedFirstLaunchSetup YES`，防止launch override掩盖真实持久化。fixture生成的两药仅用于P1行为测试，不称为历史五药demo。测试不点击Demo，不触标准库/真实外部服务，不宣称完整数据库快照。

源码检查环境已检查：diff空白、Swift源码1400行预算、指定源范围及冻结45路径不变、必要启动方法/fixture/导航段字节保持、purpose调用方穷尽、文档JSON/本地commit一致性。Swift编译、hosted测试、上述UI、视觉/性能均未运行；基线PR162 CI不能代替这些新验收。协调审查回执负责独审，独立原生验证负责人在后续切片稳定后集中验证，不每个按钮触发完整CI。

检查器修正记录：首轮冻结范围检查错误假设45路径都存在于基线，遇PR136新增但尚未合并的 `docs/HEALTH_EVIDENCE_REVIEW.md` 停止。修正为基线存在的路径逐字比较、基线不存在的路径确认候选仍不存在；未改冻结范围、源码或门禁，随后完整检查通过。该工具错误不是产品测试失败，也不被算作一次原生通过。

## #138 最小护栏提案（此切片尚未整合）

准确PR138 HEAD `96ec3bc80a30f35507f7489e6d52c0ecc7f34cf9` 的patch已读取；其TodayView改动是保存后触觉state/pulse、两Screen modifier、cleanup取消触觉、delay传request并等待scheduled且记录当前、taken/skip/reopen/rollback的保存结果feedback。TodayDoseInteractionState新增纯feedback policy/modifier。不能把它复制成第二套状态，或删除/重排其commit及迟到回调判断。

拟只在TodayView呈现接线新增一个离页请求guard：pendingDoseConfirmation、doseInteraction.inFlightDoseKeys、elderActionInProgress、elderReminderSyncInProgress、isDoseUndoRollbackInFlight等任一未完成时，拒绝本次新增设置/退出模式请求，保持原Screen与pending不变，显示先完成/取消的说明；允许时调用已有root回调。移除首页入口后只删其AppStorage直写和closure，不动动作/cleanup/feedback/事务函数。TodayDoseInteractionState仍不改。

root/Settings确认由单一root模式请求owner承接；设置号码草稿由Settings本地guard阻止切换，取消模式确认不先dismiss设置。宽窄只切呈现子布局不重建TodayView。已有跨tab清理仍是既有行为，未借此修#19。若确认/prompt与其他保存状态的真实路径无法被这个最小guard覆盖，暂停相关整合而不声称安全。

协调审查回执需先读取该区段/文件摘要核冲突，然后本候选串行接线；不改PR138分支、不整PR cherry-pick，不把其未合并触觉称本候选已具备。

## P2 模式确认、真实首次选择与最小护栏候选

P1提交 `implementation-stage-01` / tree `implementation-stage-01-tree`，协调审查回执独审回执无Blocker/Required；P1本身仍没有本轮原生测试通过。上方“尚未整合”段是P1当时状态，下方为后续P2结果，不覆盖或删除原证据。

### 行为与边界

- 删Today卡、actions字段与Today的mode偏好直写；旧入口测试改为设置进入并二次确认，保留重启、布局、真实动作和已保存mode断言。Settings Toggle与适老顶部退出均发root请求，不临时写偏好。
- 单一root request owner保存UUID、来源、原模式、目标；不同host只显示自己的确认。重复请求静默保留原请求；取消、scene inactive/background、host关闭失效请求不提交；旧ID不能确认或取消新请求。未知raw读取回退完整而不自动规范化存储。
- 确认按钮非destructive。native alert的presentation setter不提前消费request，显式取消、host消失和scene变化分别取消；真正确认以原UUID与当前模式复核后才写mode。原生呈现及顺序必须在Mac测试，云端源码检查不是UIKit实证。
- 真首次完成/跳过guide后展示三项选择；完整/稍后使用完整模式，适老始终二次确认（包括未完成fixture已elder的情况）。取消确认/返回引导不写mode、完成键或choice键；成功后一次写mode+UI选择键+既有首次完成键，再启不问。已有completed用户不看新增choice键来重问；强制`-showFirstLaunch`始终tutorial，HelpCenter replay仍只关闭教程。新增偏好键无数据库迁移。
- 仅**新适老设置/退出路径**：Today读当前pending dose/inFlight/保存/提醒同步/回滚/help确认；ElderScreen读本地skip、帮助确认、照片预览、当前时钟下仍可撤销的成功反馈；拒绝时保留page与原确认，独立“请先完成当前操作”，不伪称保存失败。允许时先复核再回调root；退出的live guard在最终提交再次读状态。设置sheet也把原Today+Screen live guard带回root，Settings退出确认前再核。
- Settings号码原输入与load/save/remove后的基线不同或仍在编辑、通知权限流程未结束时，拒绝mode请求；确认前再读草稿，保留输入，不自动保存电话。root仅在成功mode commit后关设置sheet。
- Today额外传入同一now时钟回调，guard每次调用时读当前时间（fixture固定时钟亦遵守），检查`successFeedback.canUndo(at:)`；不改undo期限、撤销实现、成功反馈或剂量动作。老显示但已无undo机会不无限阻止切换。
- **没有解决**完整模式原有跨Tab/Profile cleanup；没有改变#138状态文件或任何initialTodayLoad之后的dose/cleanup函数；未导入#138未合并触觉。旧动画清理仍原样。缺号码跳设置沿用旧滚动位置与电话号码动作，不顺便扩大#50。Duo布局、loading/错误呈现补充与五药隔离还未实现。

### 验收矩阵与待原生项

| 范围 | 新/迁移测试 | 当前证据 |
| --- | --- | --- |
| 取消/后台/重复/过时ID/当前mode变化/确认后才busy | ExperienceModeTransitionTests 7项：取消失效、确认一次、旧回调、新busy拒绝、live guard、同模式/首启elder、unknown偏好零规范化 | 已写，Swift未编译/执行 |
| 真首次取消/关闭/background/later+restart；elder二次确认+restart | ExperienceModeUITests 前2项；可写suite，无首次完成launch override | 已写，未运行 |
| 进入及Settings/顶部两条退出确认取消、重启 | ExperienceModeUITests第3项＋迁移旧testSettingsCanOpenElderMode | 已写，未运行 |
| pending dose两条导航拒绝、草稿保留、undo机会、skip/help modal owner | ExperienceModeUITests第4–7项 | 已写，未运行；skip/help测试证明系统模态门禁，不冒充人为注入toolbar回调实证 |
| unknown旧用户、真实P1重启/强制教程/HelpCenter回放 | 第8项＋保留P1两项 | 已写，未运行；unknown UI用启动参数验证显示，持久化零规范化由纯策略测试覆盖 |
| 真inFlight异步保存/提醒同步交错、确认弹出后busy、状态闭包在SwiftUI真实owner更新后仍live | root/Today源码guard；纯策略有新busy拒绝 | **尚无原生实证**，Mac需结合既有故障fixture审定/补可控交错；未为此改事务或生命周期 |
| 新test发现、普通iPhone/Duo/AX、模式alert前后VoiceOver焦点 | test目录同步映射，既有App文件编译注册 | **未运行**；本新UI suite限定iPhone，Duo代表回归由Mac集中选择，不宣称硬件开合 |

测试不点击历史Demo。除明确testActiveUndoOpportunity的一次taken外，mode/首启/取消场景前后读取fixture任务ID、status、due-offset、task/log/help/save/schedule计数一致；不是全库快照或真实患者数据。Undo测试断言一次真实taken+一次save，无额外mode导航药物动作。

P2受授权App范围为6个现有文件（Navigation/Root/FirstLaunch/Settings/TodayScreen/TodayView），P1 HelpCenter保持；加1 hosted suite/1 UI suite，迁移2既有UI文件，更新这4份规划文档。无新增App文件或PBX登记；没有schema、seeder、tools、workflow、资源、第三方许可变化。准确revision、tree、差异/源码SHA256由本地commit后的retained evidence 回执提供。

### P2 本地低成本检查实绩

- `git diff --check`：通过。
- `bash tools/swift-source-size-check.sh`：通过，1400行门槛未改；TodayView 1342、TodayScreen 1358、Settings 835行，最大NotificationService 1361行。
- owner JSON解析、14路径P2白名单、逐字保护比较：66项源码检查通过（仅静态）。原冻结45中仅授权Settings/TodayView有UI改动；其余34个存在文件逐字相同、9个原本不存在路径仍不存在。
- root从runStartupMaintenance到EOF（含所有repair/reconcile/fixture/inspection）、原startup任务/scene-active消费段、experienceContent Tab/medication split导航、Today从initialTodayLoad到EOF、ElderScreen从loadErrorState到EOF与c791精确base逐字相同；PBX、App init/恢复、seeder、DoseInteractionState、Timeline/Components、整个tools/.github/旧Duo/Core/Broker树不变。
- 首轮检查误用了不存在的`tools/check-source-size.py`路径；读取真实文件名后使用既有`swift-source-size-check.sh`通过。没有变更门禁或把路径错误算作产品测试失败/通过。
- 新7项hosted、8项UI及迁移既有测试仅保存源码，未编译、未发现、未执行；没有claim新native/CI/无障碍/性能通过。Duo与五药仍待后续切片。独审完成前不push。

## P2R：完整源审回执后的 Required 测试定位修复

协调审查回执报告P2完整独审未发现明确生产Blocker，415源码文件及Git tree逐项一致；Required是测试把完整模式等同于TabBar存在，并按第5项定位个人页面。PR162 Duo原生证据已证实其导航在Toolbar。该错误不是产品失败，不以skip、无条件降级、删断言或放宽timeout处理。

授权改动仅两份UI测试：ExperienceModeUITests的完整模式/个人定位，与旧testSettingsCanOpenElderMode迁移。一个共享helper在已有UI测试文件内，只查TabBar/Toolbar的准确AppTab中文标签；两容器各至多1项、可点项合计严格等于1，重新确认可点后才激活，再断言native selected、真实Today timeline/tab identity或Profile.root/tab identity、唯一settings入口及真实应用设置页。没有新增测试文件或PBX变更。Duo仍参与iPhone guard，测试数没有减少，旧布局/保存模式/重启断言保留。

生产App、Core、所有7项hosted、P1UI suite、工具/工作流/资源均与P2 `implementation-stage-02`字节一致。本提交同时保存纯设计文件expanded-home-next-slice.md；未开始首页或demo生产改动。准确提交/tree及原retained evidence 同一文件版本由交付回执记录。

云端diff空白/源码1400行检查通过；没有Swift/Xcode，定位修复仍未编译或原生运行。AppTab的中文标签来自准确冻结源码，TabBar/Toolbar容器策略来自PR162原生证据；具体Profile/Today AX暴露仍由Mac聚焦运行确认，不能将未观测glyph编造成稳定identifier。

**原生验收缺口继续保留**：7个hosted测试证明请求状态机；live guard测试只是普通MainActor引用闭包，未证明SwiftUI真实owner的状态更新交错。8个UI尚未证明弹出模式请求后真实保存/提醒busy改变再提交；多个alert先后、后台失效后不复活、宿主关闭后的旧callback、大小/AX变化也没有本轮native通过。这些须与普通iPhone/Duo导航修复集中验证，源审与包装验证不能替代。


## 首页独立布局切片（后续授权）

从mode-navigation-test-stage独立接线；详细边界、测试与停止条件见[layout-slice-review.md](layout-slice-review.md)。两栏独立滚动，右侧选择回顶部与焦点策略已写；668×360内容预算待原生校准。新增TodayTaskSelectionTests十项与TodayTaskWorkspaceUITests三项，云端均未执行。后者仅复用原两药/future fixture，没有新增长列表或五药数据。

宏测试文件保持mode-navigation-test-stage字节不变、原生验证负责人负责。mode-navigation-test-stage原生build-for-testing exit65、八处#require编译错误、执行零测试；独立云端宏修复historical-reference-63仅保留，不在首页分支擅自集成。P2原retained evidence 不再覆盖。本布局尚不能宣称完整编译或原生通过；返回Mac补丁后另次串行整合。

已证实本机读写恢复：首页源码写入后Git读取/差异检查成功，Swift1400行预算通过，最高TodayScreen1368行。受保护TodayView剂量函数尾段、适老Screen尾段、外层lifecycle和冻结P2文件按mode-navigation-test-stage字节比较通过；PBX恰好四行登记。无新增框架、许可来源或付费调用，原仓库仍干净。
