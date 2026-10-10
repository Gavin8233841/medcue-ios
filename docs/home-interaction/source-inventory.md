# #163 精确源码位置与工程依赖

> Historical implementation/design record, 2026-10-10. Stage labels identify evidence boundaries, not ancestors of this public-preparation branch. Original source/evidence mappings are retained separately. Current acceptance and publication status are in [plan.md](plan.md); no historical result proves this public revision passed.

基线 `c791f11ad1a4e6fc4e7ff94554c05bec1f8c5119` / tree `051b5814a121a66742381c900a0570996a8df88f`。
下列行号均指该基线；调查只读源码，不访问用户数据库/凭据，不调用seeder或启动app。

App路径前缀为 `ios-app/MedicationAdherenceApp/MedicationAdherenceApp/`；测试为同工程目录的 `MedicationAdherenceAppTests/` 与 `MedicationAdherenceAppUITests/`。

| 边界 | 路径与基线行号 | 真实职责/风险 |
| --- | --- | --- |
| 首页owner | `Views/TodayView.swift:61–110,210–319` | TodayContentView持有Query、pending确认、interaction、服务；构造complete/elder Screen；310旧首页入口直接写mode |
| 初始加载 | `Views/TodayView.swift:324–335` | 刷新clock、加载flag、外部失败消费、既有维护与通知状态；不能因去桥删掉 |
| 清理反例 | `Views/TodayView.swift:400–430` | cleanup清pending/inFlight与反馈，模式/布局切换不能意外触发 |
| 单列首页 | `Views/TodayScreen.swift:105–205,208–294` | 单ScrollView/VStack，首页适老card；task/timer/onDisappear绑外层Screen |
| 真实section | `Views/TodayScreen.swift:378–555` | open、handled、archived、next；已有确认/撤销/归档，不可丢失 |
| 适老工具栏 | `Views/TodayScreen.swift:891–916` | 完整模式退出、设置、菜单；退出目前立即回调，无二次确认 |
| 适老空态/加载 | `Views/TodayScreen.swift:710起` | loadError/isLoading先于empty；普通模式当前未传同等fetchError/loading |
| 展示投影 | `Views/TodayDoseProjection.swift:19–151` | TodayRenderSnapshot、nextReminderTask、真实空态与elder当前任务；不另写顺序/医疗状态规则 |
| 任务行 | `Views/TodayDoseTimelineViews.swift:49起` | TimelineDoseTaskRow既有身份/反馈/确认/动作呈现，可复用純展示，不重复owner |
| 模式键/ID | `AppNavigationViews.swift:4–55` | appExperienceMode=complete/elder，与旧key保持；首启/设置/退出标识 |
| 过渡视觉 | `AppNavigationViews.swift:69–129` | 深底白药丸/白字「用药跟踪」，纯视觉onAppear动画；不是数据库初始化 |
| root模式与首启 | `AppRootView.swift:13–48,89–112,210–260,296–310` | AppStorage、setup/bridge开关、模式根、立即退出、elder设置；medication split来自PR162 |
| 首启等待 | `AppRootView.swift:328–350` | 260+840ms视觉等待；取消Task会残留completing状态，去桥一起简化 |
| demo危险路径 | `AppRootView.swift:354–367`、`Views/HelpCenterView.swift:192起` | rebuildAndExit；不对真实库执行，不与纯首启busy混用 |
| root必要维护 | `AppRootView.swift:114–148,370–435` | Watch host、LiveActivity消费、旧记录修复、提醒协调与失败重试、integrity；首启前后的路径不同 |
| fixture隔离 | `AppRootView.swift:444–739,764起` | DEBUG或DEMO+simulator；显式scenario/session/mode、独立store/suite、计数/外部替身/inspection；不自动回落真实库 |
| 设置入口 | `Views/SettingsView.swift:281` | profile进入Settings；未保存业务sheet的可达关系须原生核实 |
| 设置模式直写 | `Views/SettingsView.swift:519–564,597–615,709–717` | AppStorage、使用模式Toggle、外观交互；binding直接持久化。号码草稿与focus也在本View |
| 新用户教程 | `FirstLaunchSetupView.swift:4–20,89–159` | finish/startDemo closures，skip和最后一页finish；暂无模式问询 |
| 重看复用 | `Views/HelpCenterView.swift:171–189` | same FirstLaunchSetupView全屏展示；finish仅dismiss，必须区分purpose |
| 系统init/恢复 | `MedicationAdherenceApp.swift:19–78,81–125` | primary opener/fixture选择、schema/recovery、intent/notification安装、错误重试；不能删除或兜底成空真实首页 |
| 原药demo | `Models/DemoDataSeeder.swift:25–55,120–210` | 五稳定ID、demoData标识；seed保存、补计划/历史/risk/label/stock，非患者库导入 |
| 删除再重建 | `Models/DemoDataSeeder.swift:15–20,37–110` | 两次save中间有已提交删除；改firstLaunch键并exit，失败不是无损回滚 |
| 旧demo复用/刷新 | `Models/DemoDataSeeder.swift:213–340` | 只认isDemoContent；stableID碰撞非demo会skip，legacy按名称认demo；更新demo字段/历史 |
| 说明书样例 | `swift-core/Sources/MedicationAdherenceCore/DemoDrugLabels.swift` | bundled .demo标签，DailyMed搜索sourceURL；保留合成身份，不能声称确切说明书验证 |
| Demo scheme | `MedicationAdherenceApp.xcodeproj/xcshareddata/xcschemes/MedicationAdherenceApp-Demo.xcscheme` | 与普通bundle同ID；Demo config不是DEBUG，不意味着独立沙盒安装 |
| 既有demo测试 | `MedicationAdherenceAppTests/MedicationAdherenceAppTests.swift:52起` | explicit rebuild多次与非demo药品保存测试；不证明rebuild中间save失败安全 |
| 旧模式UI测试 | `MedicationAdherenceAppUITests/MedicationAdherenceAppUITests.swift:259–306` | 依赖首页入口和立即退出；迁移设置/确认，同时保留重启/三动作/持久化断言 |
| 旧首启UI测试 | `MedicationAdherenceAppUITests/MedicationAdherenceAppUITests.swift:982–1003` | 仅next/skip存在与一页推进，需新增首次/重看/确认取消/重启行为验收 |
| Xcode接入 | `MedicationAdherenceApp.xcodeproj/project.pbxproj:376–379,690–708,773–793` | 两test根为filesystem同步且绑定各target；AppSources仍PBXFileReference/BuildFile显式列表 |

demo历史Git提交：`83319a1` controlled demo build path (#26)，`d7a48a8` elder milestone (#78)，`5da792d` risk-card identity (#115)；这些是安全现有历史，不导入历史原数据库或未归一化refs。协调审查回执只读回执已确认用户历史demo就是这套五药；旧验收用内存库，没有可复用持久库。后续复用种子而不是复制真实/历史数据库。

依赖结论：新增tests无需PBX；新增App helper不自动编译。P1纯purpose小类型位于已接入的FirstLaunchSetupView，不改PBX。TodayScreen基线1393行，仅余7行预算，后续布局应合理拆分；用户允许精确必要PBX登记并独审，与#73/#160不合并、不覆盖。不向swift-core塞UI状态以规避owner。

源码检查环境无Swift/Xcode原生编译工具，未执行应用/fixtures或原生测试。P1新增两项真实隔离UI旅程，待独立Mac线程集中运行。官方DocC源码已通过web工具读取；仓库技能目录未发现；未安装任何工具/依赖。可低成本核验的是HEAD/tree、dirty状态、累计文件边界、JSON/Markdown与diff，不是Swift类型检查或真实Duo体验。

## P2 候选位置（原调查基线保留）

- AppNavigationViews：纯UI模式请求/确认/取消策略、来源标识、环境回调及按host显示的系统确认。无新第三方依赖。
- AppRoot：唯一模式偏好写入者、真实首次选择完成键、scene离活跃取消、设置和退出最终复核。初始化/fixture尾部不变。
- FirstLaunchSetupView：FirstLaunchExperienceModeView，完整/适老/稍后三项；返回引导不完成首次。教程purpose跳过此选择。
- SettingsView：显示与操作入口、读取现有mode键，发请求而不写；保存号码基线仅用于草稿比较，电话号码持久化方法不搬迁。
- TodayView：仅新增适老设置/退出callback guard与独立说明；initialTodayLoad起的所有业务/cleanup/事务函数与精确base字节一致。
- TodayScreen：删原首页入口；适老本地taskPendingSkip/help确认/照片sheet/有效undo机会复核；剂量动作实现不变。
- Tests/ExperienceModeTransitionTests：7项行为测试；UITests/ExperienceModeUITests：8项隔离场景；P1两项与旧入口测试保留并迁移。测试target由既有同步目录接入，PBX不改；原生发现与执行尚未证实。
