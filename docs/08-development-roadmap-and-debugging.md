# 开发顺序与调试路径

## 当前阶段

已切到新 Mac 接力。SwiftPM 核心包和 SwiftUI iOS App 工程均已建立；当前重点是把演示/占位能力逐步改成可交互流程，并保持所有外部 API 都有离线演示路径。

## 新 Mac 环境状态

- 项目路径：`$HOME/Desktop/appcontest-2026-prep`。
- 主线 Xcode：`/Applications/Xcode-beta.app`，Xcode 27.0 beta，Build version 27A5194q。
- 主线 Developer 目录：`/Applications/Xcode-beta.app/Contents/Developer`。
- 主线 Swift：Apple Swift 6.4。
- 备用 Xcode：`/Applications/Xcode.app`，Xcode 26.5，Build version 17F42；仅在 Xcode 27 beta 明确不可用时作为回退。
- 当前系统默认 `xcode-select -p` 已切到 `/Applications/Xcode-beta.app/Contents/Developer`，直接运行 `swift`、`xcodebuild`、`xcrun simctl` 和 `xcrun devicectl` 均应来自 Xcode 27 beta。
- 后续主线开发不要在命令或插件配置中写死 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`；如确需回退 Xcode 26.5，必须在当次命令中显式说明回退原因。
- 根目录 `.git` 已用非破坏性 `git init` 补齐，`git status` 可用；当前是重新初始化后的本地仓库，文件显示为未跟踪，未执行清理、回滚或破坏性操作。

## 阶段 1：核心模块

- 路径：swift-core。
- 已实现 SwiftPM library。
- 目标：所有关键业务规则先能通过 SwiftPM 测试，再接入 SwiftUI iOS 工程。
- 不直接引用 Apple 平台框架。
- SwiftPM 平台声明：macOS 12、iOS 15，用于匹配当前异步 URLSession API 和后续 iOS App 最低平台。

## 阶段 2：轻量 API

- openFDA Drug Label：说明书字段。
- RxNorm：药品名标准化和 RxCUI。
- RxClass：药品类别解释。
- 所有网络功能必须有离线演示数据 fallback。
- v1 不自建后端。

## 阶段 3：SwiftUI App

- 已创建 SwiftUI iOS App 工程：`ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj`。
- Target：`MedicationAdherenceApp`。
- Scheme：`MedicationAdherenceApp`。
- Bundle ID：`com.gwyy.appcontest2026.medicationadherence`。
- 先适配 iPhone，iPad 已通过基础构建验证。
- 主界面走 Apple 健康式信息架构，五 Tab 为：今日、药品、智能体、记录、个人。风险复核已并入药品页子模块，设置已下调到个人页的应用设置。
- 首次启动已接入可跳过的横向教程，不在首启页集中请求系统权限；权限改为用户首次激活对应功能时先显示 App 内说明，再触发系统授权。
- 药品页改成健康式概览，集中展示药品数、待处理任务、药盒低量和风险复核；四个小卡片分别进入药品总览、今日待处理、药盒管理和风险复核。记录 Tab 首屏保留概览、日历、趋势、记录四个入口；日历入口以周历预览展示，点击进入月历详情。药品卡片可进入详情，详情展示用户确认药品照片、疗程、说明书摘要、风险、副作用、剂量变化记录和修改入口。药品分组使用折叠摘要展示正在服用、服用中断和归档药物，中文状态标签已改为防挤压布局。
- 药品“服用中断”已从表面分组升级为本地可复核分类：疗程结束或历史 14 天无完成记录时归到中断复核，详情页显示原因并由用户确认后才写入状态；不会自动给出停药或处方建议。
- 药品详情已支持从相册选择药品照片、真机拍照上传入口、编辑药品照片、药盒编号、疗程起止日期、多个提醒时间、剂量单位、剂量生效日期和来源说明；添加/编辑页会建议用户在药盒上手写同一编号并拍摄药盒或药品实物，提醒和记录中可用该照片辅助核对；修改剂量时写入旧剂量、新剂量、生效日期和备注，未来未完成任务跟随新剂量，历史已完成记录不被重写。
- 药品页已接入药盒库存提醒，卡片显示药盒低量状态，详情页支持填写和更新药盒剩余量。药盒管理页会基于真实已服用/修正记录显示日均消耗、预计可用天数和记录天数；数据不足时只提示继续记录与核对实物，不生成假估算。
- 用药趋势仪表盘已接入核心模型和记录页趋势详情：至少 7 个有提醒日期后才生成趋势，主题包括用药纪律、时间稳定、剂量变化、用药负担和健康信号。每个主题会展示透明公式摘要、模型权重、近 7 天 vs 前 7 天周期对比、近 7 天线性斜率/方向强度、数据置信度、证据覆盖和主要贡献因素；曲线点选后可查看当日计划/完成/稍后/忽略以及当日公式组件拆解，并对剂量变化、归档/中断和授权健康样本显示事件标记。模型会结合剂量变化、药品类型、录入来源和生命周期状态作为解释上下文；未来未到期提醒和系统停用的旧未来提醒不提前参与评分。该模型参考 PDC/PQA 的覆盖天数思想，但当前没有处方取药或理赔数据，所以明确限定为“基于提醒记录的用药趋势”，不代表疗效或处方建议。健康信号主题会在用户授权后读取近 56 天 HealthKit 样本，并按同类指标近期中位数和波动幅度做非诊断性稳定度估计。
- 记录页已重构为四入口信息架构：概览、日历、趋势和记录。日历详情继续支持近 24 个月浏览和可点开的单日记录详情；剂量变化会在周历/月历日期上显示标记，并在日期详情中说明从哪天开始生效。
- 个人页已成为长期数据与账号中心：复诊资料、Apple 健康、医疗智能体共享范围、账号备份和应用设置均在个人页进入；原设置页下调为应用设置二级页。
- 今日页已支持完成后移出待办、已处理折叠区、横滑撤销/归档/详情、外用类“已使用”文案、全部服用后的绿色完成态，并把底部提示改为天气与环境用药关注，避免与风险页重复。
- 今日页天气与环境关注已从静态演示改为真实逻辑：默认显示本地通用提醒，不打断首屏；用户点“允许天气提醒”后请求定位并通过 WeatherKit 读取今日天气，再结合本机药品信息生成用药相关环境提醒。天气失败或未授权时保留本地兜底。
- 风险页已改成更严格的严重程度置顶：只直接展示禁忌或相互作用中最优先的 1 条，多余严重项折叠；三类竖排总览、二级分组详情和单条警示详情已接入，免责说明放在页面底部。
- 用户导入说明书的核心解析已支持中文内联章节：同一行连续出现 `【禁忌】`、`【注意事项】`、`【药物相互作用】`、`【不良反应】` 等标题时会拆成独立章节，风险卡依据只取对应章节短片段，不再把整篇说明书塞进单张卡片。

## 阶段 4：iOS 能力接入

- SwiftData：已用于持久化药品、用药计划、今日任务、风险卡片、服药操作日志、智能体授权和智能体聊天记录。
- UserNotifications / AlarmKit：已接通知权限请求、添加/编辑用药计划后的本地提醒排程、稍后 30 分钟重排、前台通知展示和 iOS 26+ iPhone 闹钟提醒分支；闹钟未授权或系统不支持时自动退回推送通知。重排提醒会按 `dose.<taskID>` 显式取消旧 pending request 后再添加新 request。
- ActivityKit / WidgetKit：已接入 `MedicationReminderLiveActivityExtension`。App 声明 `NSSupportsLiveActivities = true`，今日页会在用药时间前后 5 分钟内尝试启动实况状态；用户标记已服用、忽略、撤销、归档后结束对应实况状态。扩展包含锁屏、灵动岛紧凑态、展开态和最小态展示；锁屏和灵动岛展开态已加入“已服用”“稍后”入口，通过自定义 URL 唤醒主 App 后写入 SwiftData 操作日志并同步提醒。
- Vision：已接入本机 OCR、药盒条码图片识别和真机相机扫码，识别结果必须进入待确认草稿；添加页已拆成手动、医嘱/OCR、药盒条码三入口。当前用户端暂时只开放手动添加，OCR 和条码入口保留为灰色锁定入口。
- HealthKit：已接入授权请求、读取指标范围说明、HealthKit entitlement 和近 56 天心率、血压、血氧、体温、血糖样本读取；首版只做用药趋势时间关系和稳定度展示，不读取数据用于诊断或处方决策。
- HealthKit 授权请求已增加本地持久完成态；授权请求完成后设置页会显示已完成状态和刷新入口，避免用户误以为权限流程没有生效。
- 医疗 AI：已完成供应商无关接口、App 层首次确认弹窗、授权弹窗、聊天式界面、两列快捷入口、图片咨询入口和 Keychain 凭据读取；豆包 Ark Responses API 已接入为后台默认供应商，并使用用户授权数据构造请求提示。未取得 Keychain 密钥时不会联网发送用药数据；发送提示词约束 100 字以内纯文字，模型回复按原文展示。
- 数据导出：设置页已接入“生成服药记录”入口，支持纯文本预览、按近 60 天时间段展开漏服/延后节点，并可由用户主动导出 PDF。
- 数据导出 PDF 已从纯文本绘制升级为报告式版式，包含顶部摘要、关键指标、完成率进度条、当前药品、异常节点和需沟通风险。
- Apple 账号与 iCloud：设置页已接入 Sign in with Apple 按钮、iCloud 登录状态检测和同步偏好开关；当前只做本机标记与偏好记录。SwiftData 自动 iCloud 同步仍需开发者 Team、iCloud capability、CloudKit 容器和签名配置。

## Xcode 工程触发条件

出现以下任一条件时进入 SwiftUI iOS 工程：

- 需要创建或打开 Xcode 工程。
- 需要测试本地通知。
- 需要测试 HealthKit 权限。
- 需要连接 iPhone 或 iPad 真机。
- 需要提交 TestFlight 或 App Store。

## iPad 与 iPhone 角色

- iPhone 17 Pro Max：首要真机测试设备。
- iPad Pro：轻量 Swift Playground 验证和后续大屏检查。
- iPad Swift Playground 不作为完整工程调试环境。

## Windows 测试状态

当前 `swift-core` 已通过 SwiftPM 测试。测试覆盖：

- 固定本地时间提醒。
- 固定间隔提醒。
- 服药记录统计。
- 风险关键词提取。
- 用户导入中文说明书的整行标题、冒号标题和 `【章节】正文` 内联标题拆分。
- 药品风险评估聚合卡片。
- 离线药品说明 fallback。
- RxNorm 和 RxClass 基础数据结构。
- 通知负载规划。
- 时区变化复核。
- 计划变更确认规则。
- 就诊摘要生成。
- 药品导入审核。
- 处方药、OCR、用户说明书来源复核。
- 病症和饮食注意的说明书文字复核。
- 说明书可读化展示卡片。
- 依从性连续记录和漏服洞察。
- 用药趋势不足一周、改善、下降和平稳判断，以及用药纪律、时间稳定、剂量变化、用药负担、健康信号五主题拆分、透明公式摘要、近 7 天 vs 前 7 天周期对比、近期斜率方向、置信度、贡献因素说明、趋势点当日拆解和曲线事件标记。
- 剂量变化记录、周/月历标记和趋势解释上下文。
- 药品库存估算、低库存提醒、预计可用天数和消耗数据不足提示。
- 医疗 AI 供应商无关接口和授权范围校验。
- 医疗 AI 请求提示构造和安全边界保留。
- 风险三类分组。
- 添加药品三入口工作流。
- 服药操作历史和撤销时间窗。
- App 层智能体授权、Keychain 凭据读取、聊天记录和请求审计。
- 首启引导、聊天式 AI、风险二级详情、周/月历记录和药盒库存界面已通过 iOS 构建验证。
- 首启引导不再集中放置权限请求入口；通知、HealthKit、相机、定位、AI 数据共享等权限跟随用户首次激活对应功能时请求。
- Apple 账号与 iCloud 备份准备页已通过 iOS 构建验证；未配置 CloudKit 容器前不会云同步。
- 医疗 AI 直连请求、错误脱敏和豆包真实请求冒烟已通过验证。
- Live Activities / 灵动岛扩展已通过 iPhone 17 Pro Simulator Debug build，真机上仍需检查锁屏、灵动岛紧凑态、展开态展示，以及“已服用”“稍后”入口是否能稳定唤醒 App 并写入记录。已按 Apple ActivityKit/WidgetKit 结构保留 Widget Extension、锁屏、紧凑、展开和最小态。
- 真机签名与实况状态测试步骤已整理到 `docs/13-iphone-signing-and-live-activity-test.md`。
- 真机前本地预检脚本已整理到 `tools/ios-preflight-check.sh`。该脚本只检查工程配置、权限说明、Live Activity URL scheme、HealthKit/App Group entitlement、AI secrets 是否可随包注入和当前验收文档路径；不会连接实体 iPhone，也不会打印密钥。

最新一次 Windows SwiftPM 测试结果：16 个测试全部通过。
最新一次新 Mac SwiftPM 测试结果：95 个测试全部通过。2026-06-11 已切换到 Xcode 27 beta；后续应先直接运行 `swift test`，确认使用 Apple Swift 6.4。
最新一次 iPhone 17 Pro Simulator Debug 构建结果：通过；若遇到 Xcode entitlements 并发打包提示，使用 `-jobs 1` 串行构建可稳定通过。若系统 DerivedData build.db 损坏，可使用项目内 `.codex-local/derived-data/MedicationAdherenceApp` 作为独立 DerivedData 路径，不删除系统缓存。

## 新 Mac 测试命令

主线使用 Xcode 27 beta：

```zsh
cd $HOME/Desktop/appcontest-2026-prep/swift-core
swift test
```

如需核对当前工具链：

```zsh
xcode-select -p
xcodebuild -version
xcrun --find xcodebuild
swift --version
```

## iOS App 构建命令

```zsh
cd $HOME/Desktop/appcontest-2026-prep
xcodebuild \
  -project ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj \
  -scheme MedicationAdherenceApp \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO \
  -jobs 1 \
  build
```

当前验证结果：

- iPhone 17 Pro 模拟器 Debug build：通过。
- iPhone 17 Pro 模拟器 Debug build（含 MedicationReminderLiveActivityExtension）：通过。
- 2026-06-07 提醒核心补强后，App 启动、添加药品、编辑疗程均会生成未来 30 天滚动用药任务；本地通知按最近 60 个未来待处理任务安排。模拟器中点击“稍后”后，布洛芬从 08:00 延后到 22:30 并显示“30 分钟后”；重新启动 App 后未重复生成 08:00 任务。通知授权弹窗可正常触发，允许后设置页显示“已安排 60 个提醒”。
- 2026-06-07 第三轮提醒核验后，批量重排会同步清理旧 pending notification request 和对应 AlarmKit 闹钟；跨天“稍后 30 分钟”仍保留在今日页待处理列表，避免深夜操作后记录消失；今日完成率文案改为“已按计划完成”，和“今日已处理”撤销区分开。模拟器复核个人页设置显示“通知权限已开启 · 已安排 60 个提醒”，药品添加弹层中 OCR/条码入口为灰色锁定且不可交互。
- 2026-06-07 外部交叉核查来源：Apple UserNotifications `UNNotificationRequest`、`pendingNotificationRequests()`、`removePendingNotificationRequests(withIdentifiers:)`；Apple AlarmKit `AlarmManager`、`requestAuthorization()`、`schedule(id:configuration:)`、`cancel(id:)`、`stop(id:)`；Apple WidgetKit `ActivityConfiguration` 与 `DynamicIsland`；GitHub 上的 SwiftUI 本地通知和 ActivityKit 示例仅用于确认结构，不替换当前实现。
- 2026-06-07 连续达标/动画/初始数据迁移更新后，SwiftPM 52 个 Swift Testing 测试全部通过；iPhone 17 Pro Simulator Debug build 通过。
- 2026-06-07 药品页概览四入口、药盒增强和用药趋势模型更新后，SwiftPM 58 个 Swift Testing 测试全部通过；iPhone 17 Pro Simulator Debug build 通过。
- 2026-06-07 剂量修改记录闭环更新后，SwiftPM 60 个 Swift Testing 测试全部通过；药品详情可编辑剂量生效日期，记录页周历/月历显示剂量变化标记，趋势模型纳入剂量变化解释上下文。
- 2026-06-08 用药趋势仪表盘更新后，SwiftPM 68 个 Swift Testing 测试全部通过；趋势模型纳入药品类型、来源、生命周期状态、授权 HealthKit 健康信号稳定度，并过滤未来未到期提醒和系统停用旧未来提醒。
- 2026-06-08 药品详情照片位和药盒编号 UI 精修后，SwiftPM 68 个 Swift Testing 测试全部通过；iPhone 17 Pro Simulator Debug build/run 通过，药品卡片、详情页和手动添加页已抽查照片入口与药盒编号展示。
- 2026-06-08 用药趋势周期对比和置信度更新后，SwiftPM 69 个 Swift Testing 测试全部通过；iPhone 17 Pro Simulator Debug build/run 通过，个人页“用药趋势”详情已抽查到数据质量、周期对比、数据置信度和主要贡献因素。
- 2026-06-08 用药趋势透明公式更新后，SwiftPM 70 个 Swift Testing 测试全部通过；五个主题均输出可展示的公式摘要和权重假设，继续限定为自我管理趋势，不生成诊断、处方或疗效判断。
- 2026-06-08 用药趋势点选拆解更新后，SwiftPM 70 个 Swift Testing 测试全部通过；每个趋势点携带当日公式组件，前端点选后可查看当日拆解。
- 2026-06-08 用药趋势生命周期事件更新后，SwiftPM 71 个 Swift Testing 测试全部通过；药品状态从正在服用、中断、归档之间变化时会写入 SwiftData 事件，并作为用药负担趋势的状态变化时间点。
- 2026-06-08 用药趋势曲线事件标记更新后，SwiftPM 72 个 Swift Testing 测试全部通过；iPhone 17 Pro Simulator Debug build 通过，曲线会把剂量变化、归档/中断和授权健康样本作为可见事件点，点选详情显示“当日事件”。
- 2026-06-08 用药趋势近期斜率信号更新后，SwiftPM 73 个 Swift Testing 测试全部通过；iPhone 17 Pro Simulator Debug build 通过，模型会在近 7 天 vs 前 7 天之外额外输出近 7 天线性斜率和方向强度，前端显示“近期走势”。
- 2026-06-09 中文说明书内联章节解析更新后，SwiftPM 95 个 Swift Testing 测试全部通过；iPhone 17 Pro Simulator Debug build/run 通过，用户导入说明书中的 `【禁忌】`、`【注意事项】`、`【药物相互作用】` 等同一行章节会拆成独立风险依据。
- iPad Pro 13-inch (M5) 模拟器 Debug build：通过。
- iPhone 17 Pro 模拟器可安装并启动。
- 2026-06-07 反馈修复后启动截图：`artifacts/ios-app-20260607-post-fixes.png`。
- 2026-06-07 天气权限和药品分组复核截图：`artifacts/ios-app-20260607-weather-lifecycle-pass.png`。
- 首屏截图：`artifacts/ios-app-home.png`。
- 本轮改造后截图：`artifacts/ios-app-after-ai-tabs.png`。
- Vision/HealthKit 改造后启动截图：`artifacts/ios-app-after-vision-healthkit.png`。
- 库存/复诊摘要改造后启动截图：`artifacts/ios-app-after-stock-visit-summary.png`。
- 百川医疗 AI 配置截图：`artifacts/ios-app-after-baichuan-ai.png`。
- 首启引导截图：`artifacts/ios-app-onboarding-frontend-pass.png`。
- v0.8 深色首启优化截图：`artifacts/ios-app-v0.8-onboarding-dark-ai-polish.png`。
- 聊天式 AI 截图：`artifacts/ios-app-ai-chat-frontend-pass.png`。
- 风险页重排截图：`artifacts/ios-app-risks-frontend-pass.png`。
- 账号与备份截图：`artifacts/ios-app-account-backup-frontend-pass.png`。
- 药品页健康式概览截图：`artifacts/ios-app-medications-health-style-pass.png`。
- 药品详情照片入口截图：`artifacts/ios-app-medication-detail-photo-pass.png`。
- 首启教程第一页截图：`artifacts/onboarding-tutorial-page1-v09-compact-after-wait.png`。
- 首启教程第二页截图：`artifacts/onboarding-tutorial-page2-add-medication-v09-polished.png`。

## Google Drive 交接

- 交接说明 Google Doc：https://docs.google.com/document/d/1n6BxF8tqUjZgbYcldqkxzjdR-CvwupxhqmhwfVGF-wI
- 可还原压缩包 base64 Google Doc：https://docs.google.com/document/d/1jddUhU0AHTX9pfOF_yNeIzUds4txZE9C8c-9atigcn8
- 本地压缩包：`artifacts/appcontest-ios-handoff-20260604-v2.zip`
- 本地 base64 文本：`artifacts/appcontest-ios-handoff-20260604-v2.zip.base64.txt`
- v0.9 源码备份索引 Google Doc：https://docs.google.com/document/d/1EtID-bSJEQ7mf3uM8aNKE229TMcg3T7xR-YPK6LL41Q
- v0.9 本地源码压缩包：`backups/appcontest-2026-prep-v0.9-live-activity-ui-records-source-20260605-1601.tar.gz`
- v0.9 SHA-256：`988d38ed761b593cb847f91d1e0723bf51bbfb166a58badbaffffb0862647ea7`
- v0.9 最新源码备份索引 Google Doc：https://docs.google.com/document/d/1QcCIeRAt9rVuA2gtVu6A8FIt0d_Z-Z2-cRxbDUwuUSY
- v0.9 最新本地源码压缩包：`backups/appcontest-2026-prep-v0.9-final-ui-records-liveactivity-20260605-2212.tar.gz`
- v0.9 最新 SHA-256：`806daddcb22b4c2a81097b17200178c689b1dc357378d0ed9c6c3846fc9e0d81`
- v0.9.1 最新本地源码压缩包：`backups/appcontest-2026-prep-v0.9.1-onboarding-ai-final-20260605-2250.tar.gz`
- v0.9.1 最新 SHA-256：`c4c4b3624b35c9ecbf3c5b6560fbf6689924b7f33ce696f5c230bc6e7c1e1b24`
- v0.9.1 备份索引已追加到同一个 Google Doc：https://docs.google.com/document/d/1QcCIeRAt9rVuA2gtVu6A8FIt0d_Z-Z2-cRxbDUwuUSY
- v0.9.2 接力提示文档：`docs/15-codex-handoff-v0.9.2.md`
- v0.9.2 正式本地源码备份：`backups/appcontest-2026-prep-v0.9.2-codex-handoff-before-new-api-source-20260605-230635.zip`
- v0.9.2 正式备份文件清单：`backups/appcontest-2026-prep-v0.9.2-codex-handoff-before-new-api-source-20260605-230635-filelist.txt`
- v0.9.2 正式备份大小：34 MB；ZIP 完整性测试：通过；文件数：181。
- v0.9.2 SHA-256：`52315d9e995ba5e8fb89d73a7d84aa2def7ae9460986a63f5a80ee352f10c78c`
- 注意：`backups/appcontest-2026-prep-v0.9.2-codex-handoff-before-new-api-20260605-230635.tar.gz` 和 `backups/appcontest-2026-prep-v0.9.2-codex-handoff-before-new-api-source-20260605-230635.tar.gz` 是归档工具卡住后中止留下的半成品，不作为正式备份使用。
- v0.9.3 实机问题接力文档：`docs/16-v0.9.3-live-device-issues-handoff.md`
- v0.9.3 已记录待修问题：今日撤销动画卡顿、实机医疗 AI 无法调用、灵动岛安全区、HealthKit 授权完成态、药品中文化、连续打卡统计、药品页记录入口背景简化、概览卡片可交互跳转和 PDF 导出报告视觉重设计。
- 根目录项目修改更新操作日志：`PROJECT_UPDATE_LOG.md`。继续工作时应先读该文件，再读 `README.md`、`docs/08-development-roadmap-and-debugging.md`、`docs/11-development-todo.md` 和 `docs/16-v0.9.3-live-device-issues-handoff.md`。
- 2026-06-07 今日页动效补漏：标记完成/忽略保留按钮确认小特效，并通过已处理汇总条、迁移快照小条和提交后展开隐藏跨分组重排；撤销时先淡化目标行，再同时折叠已处理区与待处理区，提交后展开待处理区。Build iOS Apps `build_sim`、`build_run_sim` 和今日页 UI 快照已通过，仍需 iPhone 实机最终确认手感。
- 当前 Google Drive 工具仍不支持任意 `.tar.gz` 原始文件上传；Google Doc 记录的是云端索引和校验信息，压缩包本体仍在本机路径。
- 2026-06-07 提醒核心补强：滚动任务生成、授权后重排程、pending notification request 计数和“稍后 30 分钟”重启稳定性已在 iPhone 17 Pro 模拟器验证。仍需真机验证锁屏响铃、勿扰/静音、AlarmKit 闹钟和灵动岛展示。

## iPhone 真机签名与运行

1. 用 Xcode 打开 `$HOME/Desktop/appcontest-2026-prep/ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj`。
2. 在左侧项目导航选择 `MedicationAdherenceApp` 工程，再选择主 App target `MedicationAdherenceApp`。
3. 打开 `Signing & Capabilities`，确认 Team 选择你的 Apple Developer Team 或个人 Apple ID Team。
4. Bundle Identifier 保持 `com.gwyy.appcontest2026.medicationadherence`；如果 Xcode 提示已被占用，再改成带你个人前缀的唯一值，同时让扩展 bundle id 自动跟随主 App 前缀。
5. 选择扩展 target `MedicationReminderLiveActivityExtension`，确认 Team 与主 App 一致，Bundle Identifier 前缀是主 App 的 Bundle Identifier。
6. 用数据线连接 iPhone，在顶部运行设备下拉菜单选择你的 iPhone。
7. 第一次真机运行若提示信任开发者，在 iPhone 的“设置 > 通用 > VPN 与设备管理”里信任对应开发者。
8. 点击 Xcode 左上角运行。启动后先完成首启教程，再进入今日页；通知、HealthKit、相机、定位和 AI 数据共享权限应在首次使用相关功能时请求。在接近提醒时间前后 5 分钟内检查锁屏和灵动岛是否出现用药提醒。

更细的图形界面步骤见：`docs/13-iphone-signing-and-live-activity-test.md`。
连接实体 iPhone 前可先运行：`./tools/ios-preflight-check.sh`。
