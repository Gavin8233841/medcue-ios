# #163 公开发布准备工作项

日期：2026-10-10 UTC。准确公开基线为 PR162 的
`c791f11ad1a4e6fc4e7ff94554c05bec1f8c5119`，tree
`051b5814a121a66742381c900a0570996a8df88f`。
候选分支：`codex/163-home-interaction-public-prep`。

问题：尚未公开的开发记录含本机路径及私有协调引用，不应随公开源码发布。
目标：只继承上述公开历史，产品、测试和工程登记与已冻结实现逐一保持相同blob；
只清理拟公开文档，保持日期、范围、文件owner、失败与未完成验收的真实边界。
原始实现历史及证据单独保留，不重写或删除。

本轮不改医疗判断、剂量事务、数据库schema、初始化、权限、CI、工具、依赖或资源。
无新第三方资产或费用；不读取真实健康库、凭据值或私有原始设备证据。
本轮只本地准备和审查，不推送、创建PR、操作原生验证环境、merge或release。

验收：直接父提交必须为上述公开基线；全部非文档blob与冻结实现相同；
新增可达提交、tree路径、blob及提交消息无私有路径/来源标识/原始证据/凭据；
文档保持历史失败与本轮未运行状态。需新上下文独审与随后准确版本CI。
独立原生构建、号码方法、三个布局方法及有界像素结果待返回，不能借用旧版本通过。
停止条件：发现任何非文档差异、敏感内容、证据归属不明或owner扩张时停止相关操作。

所有权：候选整合者仅复制已冻结实现和清理本目录文档；原作者PR及分支不改。
原生验证由独立验证负责人完成；独审由独立审查者完成。
仍需尊重 #113 Root/Today/UI、#136 Settings、#138 Today、#73 PBX/启动/UI、
#160 PBX 的现有串行整合约定。本准备阶段不整合这些开放PR。

## 当前公开准备状态

冻结实现的独立源码审查已完成；这不替代本次文档清理及公开历史的新上下文审查。
当前原生负责人正在一次构建预算内执行号码草稿方法、三个宽卡布局方法及有界真实像素验收，结果待返回。
前序初始化护栏集成阶段：一次增量构建通过；Duo/iOS27.1退出重开67.858s和模式持久化69.102s完整通过。
只关闭这两个方法覆盖的初始化回归；普通iPhone/iOS27.0（型号未回报）号码方法74.410s失败，完整输入后首个value读取因旧祖先查询漂移失败，后续键盘/模式阻断/store断言未执行。
号码查询生命周期修复现已包含在冻结实现；不测试保存号码或再次编辑，也不借前序通过声称本次通过。
准确公开候选完整CI、实际应用启动隔离/外部效果哨兵、Release/device排除、性能测量、照片/真实开合及VoiceOver仍未闭环。
当前无推送或PR；未发生本次公开披露，准备工作不意味着清理任何已公开泄露。

## 历史设计、切片范围与验收记录

下方阶段标记仅区分实施与证据范围；原始版本映射单独保留，不属于本公开分支提交历史。
后续记录中的阶段性“未运行”指其当时范围；当前状态以上方段落为准，不合并跨版本通过数。

# #163 首页任务分工、适老引导与启动减负

## 当前独立切片：适老宽屏药物卡内重排

基线为冻结 `implementation-stage-26` / tree
`implementation-stage-26-tree`。新分支
`unpublished-implementation-branch`；原始验证源码及环境保持。后面的早期阶段记录保留原版本范围。

问题：适老当前卡在宽容器里仍先整行药名/状态与照片，再另行剂量、时间，
剩余待处理数在卡外；宽度未用于组织当前任务的阅读顺序。协调审查回执仅回报旧 earlier-integrated-stage
Duo 图留白多、时间/剩余未入首屏，普通机可见。该阶段源码检查未看这些原生图，也没有
新候选像素证据，不据此声称重排已经改善首屏。

产出：只在当前卡内提供正文 leading 栏（药名→状态→剂量→计划时间→还有N项）
及 trailing 96pt 照片顶对齐。RTL 随系统自然镜像。N仍来自现有
`max(0, openTasks.count - 1)` snapshot；宽卡内只显示一次，窄/AX保留原纵排和
卡外剩余文本，零项不显示。卡自然高度，长名称自然换行，不缩字、限行或固定卡高。

布局选择：读取既有安全区容器 GeometryReader 宽度、horizontalSizeClass 和
DynamicTypeSize。只有 regular、非 accessibility 字号、有限有效的卡内内容宽度
至少520pt时启用横排；520是可审阅调整的内容阅读预算，不是机型/姿态判断。
当前外侧16pt、卡内18pt均扣除一次，因此对应容器边界为588pt。标准标题字号、
照片比例、间距和窄屏排版保持。空间不足按单栏回退，不用屏幕规格硬编码。

所有权：只改 TodayScreen 的 currentTaskCard/taskIdentity 与剩余文本位置，
在已接入 TodayDoseComponents 提取原照片按钮/布局指标并增加纯布局策略，
在 ElderModeTests 添加边界/字号测试，以及本既有 plan。TodayScreen 已1400行，
提取展示组件是为了保持现有行数门槛，不改 project/CI/tools 或另造根 owner。
不增加 @State/@Query/计时器、剂量动作、照片解码器或外部依赖；不改 TodayView、
底部三动作/safeAreaInset、所有 guard/首启/模式/提醒/持久化/真实数据。唯一生产写者
为源码检查环境分支；Mac负责后续同源像素和状态验证，协调审查回执负责独审协调。

验收：纯策略测试覆盖真实内容预算、regular/compact/nil、所有标准/AX字号及
非有限/不足宽度。原生验证不得以这些测试或源码编译替代像素：

1. 同一候选SHA、同一拥有的合成fixture/药物ID/任务ID/时钟及默认字号：Duo首屏
   名称、状态、剂量、计划时间、唯一剩余数和三按钮的完整frame均在实际可见容器内；
   控件实际可点击；不先滚动冒充首屏。普通iPhone及AX5沿用旧单栏，文字/动作可达。
2. 原生AX严格限定唯一当前卡/实际scroll/按钮叶，核对剩余数全局只一处，wide时在卡内、
   compact/AX时在卡外。系统隐藏或祖先ID传播导致歧义时报告首个观测失败，不firstMatch。
3. 首选药物/任务、待确认及演示库记录保持；在同一实例宽→窄→宽及字号变化后实际取消
   原确认，不重建Today owner、不切到另一药、不重复维护/写入。保留来源guard修复状态。
4. 长名称、中英混排、RTL、无照片和AX5分别核查自然换行/可见frame/读序；无图保留
   原中性占位及不可点照片按钮，不用真实药库/照片。真实照片预览仍是既有fixture缺口。

停止条件：默认字号首屏预算不足时报告各容器/控件frame和准确首错，不缩字/减点击面积；
出现裁切、重复剩余/根owner、状态丢失、需要动全局或剂量/数据模块、来源guard后续变更
或scope冲突时停止扩展。保留干净单切片提交供后续rebase，独审后才安排独立原生构建。
未运行结果保持pending，不合并发布/推送/操作原生环境。完整源码及校验记录供独立审查，原始验证源保持。

依据：[Apple Duo设计指南](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)、
[Apple布局指南](https://developer.apple.com/design/human-interface-guidelines/layout)及
[SwiftUI LayoutDirection](https://developer.apple.com/documentation/swiftui/layoutdirection)。
2026-10-10访问：两条HIG页面正文要求JavaScript，不能假称已核其完整文字或Duo规格；
LayoutDirection官方摘要明确支持LTR/RTL。具体520预算来自本任务评估，不是Apple规定。
已读取AGENTS、DEVELOPMENT_WORKFLOW适老/无障碍规范、现有plan及相关布局/照片测试。

本切片云端自查：四路径范围及`git diff --check`通过；TodayScreen提取后低于1400行，
全树源码行数检查通过。逐段比对确认完整模式Screen、State声明、guard发布及predicate、
taskActions、底部safeAreaInset、原文字渲染、照片decoder和既有指标数值不变；
TodayView/BundledDemoHost及全部20项UI方法源码未动。新增纯测试源码为
`wideCurrentCardRequiresRealContentBudgetAndRegularTraits`、
`wideCurrentCardAlwaysFallsBackForAccessibilityText`、
`wideCurrentCardRejectsInvalidAndInsufficientWidth`（ElderModeTests）。
它们尚未运行；`verify-native.sh --quick`在缺plutil时exit2，Swift/Xcode亦不可用。
编译、独审、标准字号首屏、长名/RTL/无图/AX及同实例开合均保持pending。

### 后续有界切片：号码测试查询生命周期

基于冻结wide-card-stage（协调审查回执回报静态独审无Required），分支
`unpublished-implementation-branch`。只改号码UI测试及其现有Settings定位helper，
本plan记录边界；所有生产文件/tree blob必须与wide-card-stage相同，包括完整宽卡/guard修复。
guard-publication-integration-stage一次增量构建后，Duo27.1退出重开67.858s和模式持久化69.102s完整通过，
零剂量动作首入/重启/返回完整模式顶栏enabled、skip占用disabled/取消恢复、
退出重开/检查字符串均完成；仅关闭这两方法覆盖的初始化回归，不借给wide-card-stage或新候选。

guard-publication-integration-stage普通iPhone/iOS27.0号码方法74.410s失败于ExperienceModeUITests:181读phone.value；
180输入成功，像素/AX回报完整号码已输入。旧句柄的Other index28在输入后解析到
UIKeyboardLayoutStar Preview，导致CollectionView不存在。未收键盘、未验证后续草稿/
模式阻断或最终store；本方法不测试保存号码或再次编辑。原生证据仅协调审查回执技术回报。

根因边界：重新查询后仍返回owner→List→field的位置祖先query，跨输入/键盘变化再次
解析会漂移。修复保留当前唯一Settings owner、真实List及全局/owner/List三处字段唯一性、
可交互和frame归属检查；仅phone返回以Application+唯一ID为根的句柄（count==1后选唯一
元素），不把位置祖先挂在最终返回值上。该方法每次tap/type/value前都重新验证当前owner
与字段；键盘关闭及提示dismiss后也重验。模式Switch已有独立结构helper及提示按钮均只在
对应转场前使用，不跨转场复用；提示等待实际消失后再解析Settings。禁止firstMatch、仅
全局搜到就算归属、额外重试/延迟、减弱完整草稿/禁止模式变化/最终store断言或改业务。

产出为一个可审查测试提交及新完整集成源码包；更新布局retained evidence 同条目至v1并保留v0和
prior guard-publication source。源码检查须证明所有生产blob完全相同、原号码断言保留、20项UI方法不变。
新候选号码方法完整原生执行和布局像素仍pending。任何owner/List/字段歧义或检测到
后台字段时停止并保留首错；缺原生链不构造通过。完成交独审，不操作Mac/推送/发布。

阶段：首页Required独立保存implementation-stage-05、Mac唯一宏补丁独立整合implementation-stage-06；已证实P2原生UI定位问题的测试候选待独审/原生，见[P2-native-ui-test-review.md](P2-native-ui-test-review.md)；演示生产暂停。P1 独立源审通过（协调审查回执回执）；P2 原生mode-navigation-test-stage构建被测试宏编译错误阻塞，原生验证负责人负责修复；首页独立布局候选已接线，新增测试待原生发现/执行，详见layout-slice-review.md。2026-10-10 UTC。下方调查基线与后续计划保留其证据范围。

Issue：[163](https://github.com/Gavin8233841/medcue-ios/issues/163)。独立候选分支：`unpublished-implementation-branch`。
精确基线 HEAD：`c791f11ad1a4e6fc4e7ff94554c05bec1f8c5119`；tree：`051b5814a121a66742381c900a0570996a8df88f`。

用户明确指定从 PR162 的精确 HEAD 建立独立候选，此指令覆盖 AGENTS 的通常 main 起分支规则。
不修改 PR162/main，不 merge/release，不操作 Mac，不恢复 iPad 专项，不安装插件、不付费、不动凭据或安全设置。
本文件与 [source-inventory.md](source-inventory.md)、[ownership.json](ownership.json) 保存调查与边界；[validation.md](validation.md) 说明当前小切片与未运行验收。旧 `docs/iphone-duo/*` 完整保留。

## 已核实工程状态

- origin 为 `https://github.com/Gavin8233841/medcue-ios.git`。GitHub 连接器确认 owner `Gavin8233841`、默认 `main`、public、未归档；不把账户权限当发布授权。
- `git ls-remote` 返回 PR162 分支为上述 HEAD，main 为 `4d9c6d5`；fetch 指定对象后 tree 精确吻合，独立 source snapshot 从该对象创建。
- PR162 open/Draft、未合并。GitHub workflow API 独立核实该 HEAD 的 Native Verification `38024924921` completed/success，Adaptive Visual Evidence `38024924923` skipped。
- 协调审查回执回执细项：三项构建、Broker38、Core161、unit375、iPhone UI43通过/3既有iPad跳过/0失败；本地 Duo 四项通过。细项在源码检查环境没有重跑或读取原生结果。该基线证据不覆盖本次改版、像素验收、真正开合或硬件性能。
- 已读 AGENTS、CONTEXT、PROJECT_STATUS、DEVELOPMENT_WORKFLOW、旧 Duo plan/ownership、CODEOWNERS。PROJECT_STATUS 的旧日期事实不能覆盖当前 GitHub 状态。
- 精确树及本 workspace 未找到 `.skills/` 或 `SKILL.md`；没有假称读过缺失的本地 skill。任务使用已有 Git、GitHub 只读连接器、Python 和官方资料，不新增插件。
- Linux，有 Python3/Node/Git，未发现 Swift/Xcode/plutil 原生链。`verify-native.sh --quick` 也先要求 swift/xcodebuild，不能在此宣称该门禁通过。原生构建、UI、截图及开合由既有 独立原生验证负责人负责。
- GitHub CLI API 被环境拒绝；现成 GitHub 连接器成功，未变更认证。GitHub 路径核查不能发现其他线程未推送修改，生产写入前由候选整合负责人确认唯一写入者。

## 问题、结果与范围

普通 iPhone 用户需要清晰的今日操作流；Duo 展开用户需要边选任务边核对药品和这次计划，而不是看更大的旧卡片。适老用户需要能找到设置、不会误切模式的确认流程。首次使用者应主动选择界面，已有用户应保留选择。

范围：真实首页的信息分工、适老入口迁移、首启与重看教程区分、进入/退出确认、隔离的既有 demo 调试入口、删除应用内过渡视觉与固定视觉等待。

边界：保留现有药品/任务顺序、未确认语义、30分钟提醒、事务/回滚/保存后副作用、无障碍、归档/撤销、帮助号码、本机隐私与首启维护。没有 schema、迁移、医疗规则、HealthKit、电话、通知权限或 CI 工作流改版；不宣称收口 #46/#50/#19/#137 或 #161。

## 推荐方案 A：任务流与核对面板

这是本产品基于官方资料作出的设计选择，不是 Apple 要求的特定用药布局。

| 容器 | 信息安排 | 状态与操作 |
| --- | --- | --- |
| 普通 iPhone/窄窗口 | 现有今日任务顺序、待处理与已处理/归档层级；移除首页适老推广卡 | 保留真实动作、确认、失败与撤销；不增加来回导航负担 |
| Duo 足够空间且非辅助大字号 | 左：今日时间轴及任务选择；右：所选任务药名、剂型/规格、药盒编号、小图或既有符号、该次剂量/计划/时间、真实状态及操作 | 同一 task ID/logical dose key、同一 pending confirmation；右侧承接操作，左侧不再复制第二套动作/确认 |
| AX 大字号或空间不足 | 自然单栏，核对内容可读，主动作可达 | 不缩字硬塞双栏；选择和确认不被重置 |
| 无计划/无待处理/全完成 | 使用现有真实含义的单一空态和必要已处理内容 | 不用空双栏、虚构任务或指标墙填充空间；加载和错误不能冒充空态 |

选择策略：首次默认既有可操作待处理序列的第一项，不能让未来提醒越过前面的未确认任务；这不提交动作。用户一旦主动选过，计时刷新、开合、字体变化不擅自改选。仍存在但已完成的任务可保留供核对，操作由现有状态判断；真正移除的任务显示失效/返回选择，不无声切到另一药。待确认任务优先保护，不把其确认移植到另一个 ID。

状态 owner 是现有 TodayContentView；只增加一个浏览选择状态（优先放在持续存在的 TodayScreen 或已接入的呈现模型），不能复制 TodayView、@Query、计时器、notificationService 或剂量事务。两栏是同一宿主的布局，不因宽窄重建 TodayView。系统栏、安全区与折叠区域遵循原生容器；宽度预算不是 Duo 姿态检测。优先评估稳定系统 split 容器；若需要重建 owner 才能插入则停止，不能为展示强行改导航根。

下一次摘要：展开态右侧已核对同一次任务时不重复另一张下一次卡；普通单栏保留其用途。不删除已处理、归档、撤销、失败等实际功能，也不修改完成庆祝/动作反馈动画；本次删除的是首启桥动画。

## 模式切换与首启契约

- 保留 `appExperienceMode` 的 `complete/elder` 原键值，root 管最终提交；设置与适老顶部退出发起请求，不能直接写偏好。
- 设置路径为「应用设置 → 显示与操作 → 使用适老模式」；沿用颜色、减少动态、图片、大触控等功能。适老页继续有显式「设置」，进入通用设置不总是定位帮助号码；缺号码流程仍定位号码，不扩大 #50。
- 请求不同模式 → 非破坏性系统确认（「启用适老模式」或「返回完整模式」＋「取消」）→ 再核目标/是否忙 → 写一次。取消、交互式关闭、重复点击均不写模式/药品/任务/动作日志，不先切再反切，不用红色删除样式。
- 真首次设置和 HelpCenter 重看教程必须显式区分 purpose。首次提供「完整模式」「适老模式」「稍后在设置中选择」。稍后默认完整模式、完成本次选择流程；不每次启动反复询问。仅显式确认实际模式变化后提交。已有 `hasCompletedFirstLaunchSetup` 用户保持原偏好，不因新增选择标记重新弹问；`-showFirstLaunch` 演示/测试强制教程不得被当成新用户迁移。
- 选择取消不标记已完成；用户可以继续/稍后。重复完成/跳过幂等；帮助中心教程不改 mode 或首次完成键。若新增 choice-resolved 键，只是本机 UI 偏好，不升级数据库。

### 必须先解决的生命周期反例

`pendingDoseConfirmation` 在 TodayContentView 的本地 @State；两种 Screen 的 onDisappear 调用 cleanupTodayScreen，清确认、inFlight、反馈和任务。仅给 Settings Toggle 加 alert **不构成** pending/draft 安全证明。

最小串行方案：

1. 展开/折叠只切内部排版，Today owner 不 disappear，不重复 initialLoad/cleanup；状态测试和原生转换同时验。
2. 从适老页发起「设置/退出」或模式请求时，若有未完成剂量确认、保存、提醒同步或不可丢弃操作，则保持原页并提示先完成/取消当前操作；不能清 pending、自动保存或复制请求。该保护需要 TodayView 最小 callback/guard 接线，与 #138 owner 协调后才能写；TodayDoseInteractionState 仍冻结。
3. 设置中帮助号码草稿与实际保存值不同或仍编辑时，模式切换暂停，保留草稿并提示先保存或明确取消编辑；确认取消必须回到原设置草稿。不能以模式切换顺便保存号码。
4. root 模式确认不得先关闭设置 sheet 再显示；提交前复核 busy/current mode 防过时确认和重复提交。确认后才允许重建模式根，且此时没有待保存操作。
5. 完整模式既有跨 tab 导航会清 Today 状态，是历史行为；不把它宣称为本次已修复，也不为此扩展 #19 全局生命周期。新增模式路径/布局不得引入额外清理。如果要保证用户先切 profile 再取消设置仍恢复此前 pending，就涉及更大 owner 生命周期变更，单列为停止条件，由候选整合负责人选择最小边界。

首批不得以「保留 pending」口号掩盖这个尚未实现/验证的契约。独立测试须覆盖设置呈现/取消、未完成确认与 inFlight 的反例，而不只检查 alert 存在。

## 启动层删除与保留清单

删除目标：AppNavigationViews 的 FirstLaunchCompletionBridgeView；AppRoot 对该层的挂载/过渡与 completeFirstLaunch 的 260ms、840ms 视觉等待。纯完成流程改为同步/幂等提交，去掉只供动画使用的 busy 状态，避免 task 取消留下 isCompletingFirstLaunch 卡住。demo 实际写入另用独立 busy/error，不共用被删的桥状态。

必须保留：系统 LaunchScreen 配置；MedicationAdherenceApp init 的持久化 opener、schema/migration 支持、恢复容器/重试、PDF清理、notification delegate/intent executor；AppRoot 的 Watch host、LiveActivity消费、旧自动跳过修复、提醒协调及重试、完整性检查；Today 初始维护、加载/错误判断与外部失败消费。

`runStartupMaintenance` 完整性检查当前仅在首启已完成时执行，首启结束触发另一路 repair/reconcile。这里记录真实时序，不顺便改变该安全检查次序。700/1400ms 的提醒协调等待和 demo 300ms 退出等待不是本次 260/840ms 视觉等待，不能一起删。

撤桥后完整模式需要显式传递真实 fetch failure/initial-loading，防止短暂空 snapshot 展示为「没有任务」。这仅为呈现参数，不更改查询/维护命令。若需要修复更广初始化竞态，拆出独立问题。性能只报告固定等待移除的源码事实；冷启动/首屏可交互/主线程卡顿按准确 build 和设备测量。

## 既有 demo 核源与隔离

源码源头是 `Models/DemoDataSeeder.swift`，五稳定 UUID 后缀001–005：布洛芬、对乙酰氨基酚、人工泪液、氯雷他定、维生素D3。均创建为 `inputSource=.demoData`、`isDemoContent=true`，当前 photoAssetName 全为 nil；不能声称恢复了用户旧药盒照片或原私有药库。

`DemoDrugLabels` 为既有 `.demo` 教育文本，引用 DailyMed 搜索页；不是本轮已验证的真实患者/处方或确切产品说明书。现有 ElderUITestFixture 则是一/两药合成包图、固定时钟、独立 session store/偏好/外部替身；与五药 demo 不相同。

`--seed-demo-data`/reminder smoke 不先删除非 demo 内容，但会刷新已有 demo 的资料、历史文字/状态和缺失计划；它不是「已有库完全不变」。`rebuildForExplicitDemoMode` 先删除 demo 相关图并 save，再 seed/save；后一步失败不能还原前一次已提交删除。`rebuildAndExit` 还改首次完成键并退出，禁止对未知/真实库调用。

推荐：扩展现有 DEBUG+Simulator 隔离 session fixture 增加 bundled-demo 场景，只在测试拥有的独立目录和偏好套件复用五药 seeder；显示「合成演示数据」，失效参数失败关闭、不回落主库。按显式 seed API 的 throws 结果报告成功，不依赖吞错的 seedIfNeeded；不自动加载到标准库、不自动 rebuild/exit。普通 Release 入口/执行路径不可用，Demo scheme 也不能被假定独立安装（其 bundle ID 与普通 app 相同）。

原生验证技术回报已确认历史 demo 就是上述五药 seeder，另有库存、说明书、风险卡、60天历史与剂量变更样例；历史 `historical-reference-70` 验收使用内存库，没有可复用持久库。后续显式在新 DEBUG/MEDCUE_DEMO 隔离容器复用这套种子，不将两药fixture或真实库搬入。seeder依赖当前日历/日期，测试场景的固定2026-09-05时钟必须与五药种子日期一致；不得照搬当前未识别的旧 `--ui-testing-in-memory-store`。只有新专用空容器可以使用既有seed，不能向未知库rebuild/exit。实际导入尚未验证，不声称已导入。

## 文件 owner 与串行实施顺序

完整路径和相关 PR 的准确 SHA 见 ownership.json。以下是候选边界，不是解除他人 owner。

| 文件/集合 | 拟改内容 | owner/限制 |
| --- | --- | --- |
| docs/home-interaction/* | 计划、源清单、owner与验收 | 源码检查环境候选唯一写入者；本阶段仅这些路径 |
| AppNavigationViews.swift | 统一 UI 模式请求契约、标识；删桥定义 | 本候选串行；避免巨型新抽象 |
| AppRootView.swift | 模式最终确认、首启 purpose/无桥完成、隔离 demo fixture扩展 | #113 fixture及PR162 medication split完全保留；不改maintenance/inspection含义 |
| FirstLaunchSetupView.swift / Views/HelpCenterView.swift | 首次选择与重看区分 | 本候选串行；HelpCenter demo未验证真实库前不执行 |
| Views/SettingsView.swift | 显示与操作入口、请求确认、草稿保护 | #136 当前占用；只选对应UI段，HealthKit/隐私授权与电话号码逻辑不搬迁 |
| Views/TodayScreen.swift | 移除首页入口、任务/核对排版、适老设置/退出 | #113 UI标识与fixture旅程；不改系统副作用/帮助拨号 |
| Views/TodayView.swift | 最小 presentation参数、加载/错误和busy护栏接线；移除旧模式直写 | #138 owner，冻结默认；需协调审查回执串行交接范围后才改，不能大改cleanup/事务/触觉 |
| Views/TodayDoseTimelineViews.swift / TodayDoseComponents.swift | 复用/抽取纯身份展示与唯一动作区 | #113 TimelineViews交集；确有需要才动，不重复动作owner |
| Models/DemoDataSeeder.swift | DEBUG隔离种子入口（如需要） | 五药数据本身不改；禁止把rebuild拓展成自动真实库导入 |
| 新 Tests/ExperienceModeTransitionTests.swift、TodayTaskSelectionTests.swift、BundledDemoIsolationTests.swift | 行为/失败/取消/幂等 | 自动同步test target；实际发现/运行待原生 |
| 新 UITests/HomeInteractionUITests.swift + 旧 MedicationAdherenceAppUITests.swift | 首启、设置进入退出、确认取消、宽窄选择、故障呈现 | 旧文件#113/#73交集；迁移旧首页入口测试，不删除动作/重启/数据断言 |
| project.pbxproj | P1不改；后续只在合理拆分App文件确有需要时精确登记 | #73/#160占用；App源码显式接入、test目录同步；用户已授权必要串行登记/独审，不覆盖其他PR。TodayScreen基线1393行，不能为避PBX把它继续堆大 |
| TodayDoseInteractionState、schema、医疗/提醒/Health/导出/AI、tools/.github、旧Duo文档 | 不写 | 保留冻结45路径的其他范围；不 cherry-pick 整个其他PR，不扩CI预算 |

步骤：P0 本计划与owner审计 → P1 去桥与首启purpose（先做可核的小差异）→ P2 模式确认/入口/最小busy保护（owner交接先行）→ P3 隔离demo → P4 单owner任务选择与展开排版 → P5 集中原生验收与独审/DraftPR。每段自审后再串下一段；不把布局和剂量状态重构揉成一个大补丁。

## 可观察验收矩阵

| 项目 | 代表场景 | 必须断言 | 证据与阶段 |
| --- | --- | --- | --- |
| 模式状态 | 同模式/反向请求/确认/取消/重复/过时请求 | 请求前mode不变、取消零写、确认一次、restart保存、无日志增加 | 纯状态tests＋hosted/UI；未运行 |
| 首启 | 新用户完整/适老/稍后；选择取消；跳过；重复完成；restart | 保留选择、不反复询问、实际切换有确认、取消不finish、首启键幂等 | 独立suite＋原生UI；未运行 |
| 旧用户/教程 | 已有complete/elder；HelpCenter重看；-showFirstLaunch | mode和首次完成键不被重看改写；不假迁移 | 原生隔离偏好suite；未运行 |
| 未完成操作 | 剂量确认/保存/提醒同步、设置号码草稿、设置sheet确认取消 | 不离开/不清pending/不自动save/不重放；取消返回原draft | 最小guard tests＋真实UI，必须先owner交接 |
| 任务选择 | 默认与主动选择、timer、开合、AX、处理后刷新、任务移除 | 同一task ID/logical key、不会误换药；只一个确认owner | 纯状态＋真实普通iPhone/Duo；未运行 |
| 剂量事务 | 确认取消/成功/保存失败/双击/旧回调/undo | 原有一次commit与保存后副作用；失败无成功、取消零写、任务/log数量正确 | 复用现有Elder/Today/fixture回归；不重写业务测试 |
| 视觉信息层级 | 普通iPhone默认、Duo展开、最大AX；长名/剂量/RTL；暗色 | 核对区有用途、无重复卡/截字/系统栏遮挡；照片符号不冒充真实包图 | 相同合成源实际截图与审图；网页/源审不代替 |
| 空态/加载/失败 | 无计划/全完成/无开放；真实fetch失败；初始加载 | 一处真实空态；未加载/失败不显示无任务；有可达重试 | hosted/UI真实failure注入；未运行 |
| 启动 | 冷启、tour完成/skip、后台、store open失败/重试失败/成功 | 桥与260/840等待消失；维护/恢复/Watch/LiveActivity保留；无卡住busy | 差异白名单＋既有Recovery/Integrity tests＋设备measure |
| demo | 隔离五药、重复seed、restart、UUID碰撞、seed失败/invalid参数、Release | 主库/主偏好不动、身份正确、不重复、不自动exit、不吞成功错误、不触发外部服务 | hosted隔离store＋fixtureUI、Release构建；未运行 |
| 无障碍 | AX5、VoiceOver顺序/焦点、减少动态、颜色对比/按钮触控 | 完整可读/可达、状态不只颜色、取消焦点回原控件；不硬塞两栏 | audit＋人工原生；不凭外观声称VO通过 |
| 集成与证据 | 精确candidate SHA、累计c791..HEAD、当前owner/Main差异 | 不变更冻结业务/门禁；旧失败完整保留；新tests被target发现执行 | 独立fresh-context审查＋完整exact-head CI；不沿用基线pass |

按风险选择代表组合，不跑无意义笛卡尔积。真实开合由 Device Hub 支持的操作留证；Duo模拟器不是硬件，iPad专项继续停用。冷启动可交互与卡顿只测量后报告，原三build基线不是本候选性能证据。电话/Health/Watch真实边界根据diff判必要回归，不借本项宣称交付。

## 依赖、资源与许可

使用现有SwiftUI/SwiftData/UIKit/SF Symbols与项目模块；无新第三方代码、字体、图片、模型、付费API或云服务。Core Package 无外部package依赖。官方HIG作为设计依据、不是可复制资产许可；不搬Apple图像或文案入产品。
既有demo教育文本保留 `.demo` 和源指向，不将DailyMed搜索页包装成已核确切说明书；如需要新第三方说明书、照片或历史外部asset，先核授权/来源，未知则只影响该asset路径并停止。

已通过web工具读取官方DocC JSON（普通HTML需JS；Linux直接HTTP被拒绝，未绕改配置）：

- [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)：标准容器/安全区、状态与功能连续、内屏可展示额外层级；不据此编造尺寸/API。
- [Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)：简短可选，跳过后不重复、可从帮助重看。
- [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)：明确结果按钮和取消，说明简洁；模式二次确认来自用户要求。
- [Launching](https://developer.apple.com/design/human-interface-guidelines/launching)：系统启动屏与onboarding不同，优先尽快可交互并恢复上下文。

## 停止、回滚与发布边界

停止相关切片：未推送owner交叉未确认；要更改冻结事务/cleanup/生命周期、数据库schema或初始化安全时序；新API未经实际SDK证实；主库/私有demo来源不清；两阶段delete/save路径被用于真实库；新权限/费用/凭据/许可证需求；失败/取消产生状态损失或重复写；布局必须重建Today owner；原生资源不具备且不能诚实核验。

继续独立可做部分，不用无限视觉微调、不把失败变skip、不扩timeout隐藏断言、不删历史证据。源码退回独立小提交；无schema变化，保留旧偏好键；DEBUG fixture只清测试拥有的session目录，不碰主库/其他会话。未完成的审查/CI/像素/开合分别列明。

推送前向协调审查回执报累计目标文件、owner交接、准确SHA/tree、自审与真实通过/失败/未运行；完整保留基线与失败证据。只有候选代码/技术说明与DraftPR在本需求可授权范围，不Ready/merge/release。协调审查回执已指定源码检查环境为#163唯一生产集成者，允许小切片本地commit后独审、集中一次必要原生验证；独审反馈前不push。当前P2只整合模式确认、真实首启选择、入口迁移与新适老路径的最小护栏；详细边界见validation.md。Duo排版与五药隔离尚未实现；P1原证据继续保留。
