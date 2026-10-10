# #163 首页布局独立切片

> Historical implementation/design record, 2026-10-10. Stage labels identify evidence boundaries, not ancestors of this public-preparation branch. Original source/evidence mappings are retained separately. Current acceptance and publication status are in [plan.md](plan.md); no historical result proves this public revision passed.

基于 `implementation-stage-03` / tree `implementation-stage-03-tree`。精确候选HEAD以本切片commit/source-package manifest为准。没有推送、merge、release或Mac操作。

## 结果与状态契约

完整模式有活动任务且实际容器达到668×360、字号非AX时，左侧只选择，右侧核对药名、真实本次剂量/时间/状态及资料，并承接唯一原动作。两个有界ScrollView并列；右侧动作safeAreaInset占实际空间。显式选择事件只滚右侧到身份顶部，左侧滚动保留；同一行再次选择也回顶部。首次默认不抢VoiceOver，显式选择请求身份焦点，确认出现由原内联标题接焦点。字体、窗口与计时刷新不写业务状态。

普通iPhone/AX回到原就地操作行；长药名自然换行。选择/确认任务由单栏ScrollViewReader定位；无活动任务时一处全宽真实空/完成态，所选已处理上下文只读，原已处理/归档入口仍承担其动作。下一提醒只去除与当前核对项的重复；天气、忽略摘要、失败、帮助、归档、撤销保留。撤销banner改为底部safeAreaInset，避免覆盖右侧动作。

`TodayContentView`新增一个浏览selection，原Query、服务、pending、inFlight、undo及事务仍是唯一owner。引用用task UUID＋medication UUID定位，logical key用于核对确认；普通浏览允许同UUID延迟后key更新，pending必须匹配原UUID与原key。不存在/不确定时不向同key新记录接旧确认。加载失败优先真实fetchError；不编造Query重试，失败页明确重新打开应用核对。

**没有修改P2模式状态契约，也没有迁移原剂量pending所有者。** 新confirmationReference只是展示锚点，无kind、保存或确认执行器；全部动作仍调用原TodayScreenActions。宽窄切换只换内部呈现，timer/initialLoad/cleanup/弹框仍挂持续外层Screen。宏文件由原生验证负责人修复；首页未擅自整合云端historical-reference-63。

## 精确文件边界与分工

| 路径 | 本切片改动/owner |
| --- | --- |
| Views/TodayView.swift | 源码检查环境仅selection State和完整模式呈现参数8行；initialTodayLoad至EOF保持mode-navigation-test-stage字节相同，#138动作状态冻结 |
| Views/TodayScreen.swift | 源码检查环境布局/只读选择接线、真实loading/error、完成呈现和undo安全区；ElderTodayScreenActions至EOF及外层lifecycle字节相同 |
| 新 Views/TodayTaskWorkspaceView.swift | 源码检查环境纯浏览策略＋选择/核对/失效/提醒呈现；不持有Query/ModelContext/服务/事务 |
| Views/TodayDoseTimelineViews.swift | 源码检查环境抽取同一三动作/确认呈现组件、保留callback/禁用/语义ID，原行默认样式；确认标题AX焦点与长药名换行 |
| project.pbxproj | 源码检查环境只加BuildFile/FileReference/Views/App Sources各1行、2唯一ID；需#73/#160交集的独立精确审查 |
| 新 Tests/TodayTaskSelectionTests.swift | 源码检查环境10个策略行为测试；所有mutating调用在宏外执行，避免已知#require编译问题 |
| 新 UITests/TodayTaskWorkspaceUITests.swift | 源码检查环境3个原生旅程定义；沿用真实TabBar/Toolbar严格导航，无CI更改 |
| ExperienceModeTransitionTests.swift | **Mac唯一owner，保持mode-navigation-test-stage文件不变**；回传补丁后协调者授权云端串行整合 |
| Root/fixture/seeder/schema/Core/CI/tools/旧Duo证据 | 不写；历史五药导入独立后续切片 |

没有新增框架、网络接口、图片、字体或许可来源；复用项目组件与SwiftUI/SwiftData。没有安装或付费行为。

## 验收矩阵与真实证据

| 项目 | 本切片证据 | 原生门禁/缺口 |
| --- | --- | --- |
| 首个真实open默认、手动选择稳定、重复选中回顶部事件、timer不抢 | 新纯策略测试定义；浏览策略源审 | 尚未编译执行；UI需实际焦点/滚动证据 |
| 延迟key改变仍同UUID、busy拒绝选择、旧UUID/换药/不确定pending不接新动作 | 新纯策略测试定义 | 需真实确认/异步保存中交错；两药past fixture没有future多任务确认 |
| 宽屏双栏／AX单栏、身份和剂量可见、唯一动作、滴眼保留“已使用” | 新UI两药选择、future取消确认、AX future取消确认；前后task/log/help/save/schedule快照相同断言 | 三项均未运行；宽屏专项在窄视口明确skip，宽视口缺布局直接失败，无TabBar/第5项假设 |
| 左低位行选择后右侧回身份、两个滚动位置独立 | 有界兄弟ScrollView、右侧scrollTo实现；UI先滚右侧再切药 | **现有两药没有长列表；未实证左列表底部选择**。需要独立合成压力fixture或原生真实可控列表，不把两药测试称为该项通过 |
| 窄→宽→AX的同owner、pending/undo连续，实际开合 | 外层lifecycle、剂量函数尾段字节保持；浏览预算策略测试 | 尚无实际开合/动态字体跨布局证据，UI重新启动AX不证明运行中连续性 |
| 初始loading/失败不当空态、全完成/忽略、已处理归档undo | 新加载策略测试；代码复用原投影与动作 | 尚无Query故障注入/UI完成实测；重新打开只是现有恢复建议，不声称新retry能力 |
| 独立构建/测试、AX5/VoiceOver/暗色/RTL/减少动态、系统栏与触控 | 云端diff check、1400行检查和保护范围字节比较通过 | 本机无Swift/Xcode/plutil，不可替代Mac原生验证；阈值和长名/确认卡空间仍须校准 |

恢复后的本机证据：`git status`读取成功；首页文件新增/改写成功；随后`git diff --check`退出0、源码预算脚本退出0，最大TodayScreen1368行；只加四行PBX反向去除后与mode-navigation-test-stage完全相同。原保存仓库不写。静态证据不是编译/测试pass。

已知上游门禁：mode-navigation-test-stage原生build-for-testing exit65，八处#require宏编译错误，**执行0测试**。该失败原证据保留；Mac正在唯一修复，当前首页snapshot仍带mode-navigation-test-stage宏文件，不能称可运行原生测试包。独立云端historical-reference-63不推送、不整合、不再覆盖P2 retained evidence 。

## 停止条件与下一步

先对本切片做精确新鲜源审，尤其PBX登记、内联确认语义和唯一动作。Mac补丁回传后另次串行整合，再聚焦hosted策略与3项UI；不得把基线PR162 CI或静态检查记作此HEAD原生通过。

668×360是候选预算，不是Apple规定或Duo实测。长名/较大非AX字号/确认卡挤占身份或按钮时，校准预算或纯呈现结构；不得缩字、裁剪、删除断言或扩大超时掩盖。

原pending只有logical key。若确认期间任务跨日/消失，新布局拒绝将其附到同key另一个UUID；失效页不调用旧任务动作。**此时可能没有现有可达取消入口，是原生命周期边界，未修#19。** 若审查/原生反例要求解除该pending，停止相关验收并精确交接owner/事务依赖，不能在布局中私自写pending或引入第二套取消契约。

重建Today owner、改剂量/cleanup/#138、schema/迁移、主库/standard、外部副作用、系统导航根、工具/CI门禁或五药rebuild均超本切片。历史五药仍只规划安全隔离导入；本提交不导入真实库、不把两药fixture冒称旧demo。


## 独审随后确认的 Required

本文件描述adaptive-home-stage历史候选，原快照不变。独审确认目标失效会锁死且单列按key会接替代UUID；此边界未被产品接受。后续明确授权窄取消与共同有效性修复，详见[confirmation-recovery-review.md](confirmation-recovery-review.md)，不得把此处旧边界描述当验收通过。
