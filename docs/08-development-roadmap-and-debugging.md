# 开发顺序与调试路径

## 当前阶段

已切到新 Mac 接力。SwiftPM 核心包和 SwiftUI iOS App 工程均已建立；当前重点是把演示/占位能力逐步改成可交互流程，并保持所有外部 API 都有离线演示路径。

## 新 Mac 环境状态

- 项目路径：`REDACTED_HOME_PATH`。
- Xcode：已安装 Xcode 26.5，Build version 17F42。
- Xcode 内置 Swift：Apple Swift 6.3.2。
- Command Line Tools：已存在。
- 当前系统默认 `xcode-select -p` 仍指向 `/Library/Developer/CommandLineTools`，直接运行 `swift` 会使用 Apple Swift 6.0。
- 由于全局切换 Xcode 需要管理员密码，当前测试命令使用 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` 临时指定 Xcode。
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
- 主界面走 Apple 健康式信息架构，五 Tab 为：今日、药品、AI 助手、风险、设置。
- 首次启动已接入可跳过的配置引导，第一页保留小日历摆动，后续页面改为一次性推入式教程；第二页突出从右上角加号添加药品、扫描药名、规格剂型选择和照片/库存非必填。
- 药品页已合并记录入口，并改成健康式概览，集中展示药品数、待处理任务、药盒低量和今日完成率；记录入口固定展示最近 60 天示例记录、周历、月历和每日详情；药品卡片可进入详情，详情展示用户确认药品照片、疗程、说明书摘要、风险、副作用和修改入口。药品分组使用三张状态卡展示正在服用、服用中断和归档药物，中文状态标签已改为防挤压布局。
- 药品“服用中断”已从表面分组升级为本地可复核分类：疗程结束或历史 14 天无完成记录时归到中断复核，详情页显示原因并由用户确认后才写入状态；不会自动给出停药或处方建议。
- 药品详情已支持从相册选择药品照片、真机拍照上传入口、编辑药品照片、疗程起止日期、多个提醒时间、剂量单位和来源说明；减少提醒时间时保留旧记录并标记原因，不直接抹掉历史。
- 药品页已接入药盒库存提醒，卡片显示药盒低量状态，详情页支持填写和更新药盒剩余量，估算结果只用于提醒用户核对实物。
- 记录页已接入本周折叠日历、月历展开和可点开的单日记录详情。
- 今日页已支持完成后移出待办、已处理折叠区、横滑撤销/归档/详情、外用类“已使用”文案、全部服用后的绿色完成态，并把底部提示改为天气与环境用药关注，避免与风险页重复。
- 今日页天气与环境关注已从静态演示改为真实逻辑：默认显示本地通用提醒，不打断首屏；用户点“允许天气提醒”后请求定位并通过 WeatherKit 读取今日天气，再结合本机药品信息生成用药相关环境提醒。天气失败或未授权时保留本地兜底。
- 风险页已改成更严格的严重程度置顶：只直接展示禁忌或相互作用中最优先的 1 条，多余严重项折叠；三类竖排总览、二级分组详情和单条警示详情已接入，免责说明放在页面底部。

## 阶段 4：iOS 能力接入

- SwiftData：已用于持久化药品、用药计划、今日任务、风险卡片、服药操作日志、AI 授权和 AI 聊天记录。
- UserNotifications / AlarmKit：已接通知权限请求、稍后提醒安排和 iOS 26+ iPhone 闹钟提醒分支；闹钟未授权或系统不支持时自动退回推送通知。
- ActivityKit / WidgetKit：已接入 `MedicationReminderLiveActivityExtension`。App 声明 `NSSupportsLiveActivities = true`，今日页会在用药时间前后 5 分钟内尝试启动实况状态；用户标记已服用、忽略、撤销、归档后结束对应实况状态。扩展包含锁屏、灵动岛紧凑态、展开态和最小态展示。
- Vision：已接入本机 OCR、药盒条码图片识别和真机相机扫码，识别结果必须进入待确认草稿；添加页已拆成手动、医嘱/OCR、药盒条码三入口。
- HealthKit：已接入授权请求、读取指标范围说明和 HealthKit entitlement；首版只做用药相关提示准备，不读取数据用于诊断或处方决策。
- HealthKit 授权请求已增加本地持久完成态；授权请求完成后设置页会显示已完成/可重新请求状态，避免用户误以为权限流程没有生效。
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
- 药品库存估算和低库存提醒。
- 医疗 AI 供应商无关接口和授权范围校验。
- 医疗 AI 请求提示构造和安全边界保留。
- 风险三类分组。
- 添加药品三入口工作流。
- 服药操作历史和撤销时间窗。
- App 层 AI 授权、Keychain 凭据读取、聊天记录和请求审计。
- 首启引导、聊天式 AI、风险二级详情、周/月历记录和药盒库存界面已通过 iOS 构建验证。
- 首启引导第一页已接入通知权限请求入口；后续页面再承接 HealthKit、AI 数据共享和备份相关授权。
- Apple 账号与 iCloud 备份准备页已通过 iOS 构建验证；未配置 CloudKit 容器前不会云同步。
- 医疗 AI 直连请求、错误脱敏和豆包真实请求冒烟已通过验证。
- Live Activities / 灵动岛扩展已通过 iPhone 17 Pro Simulator Debug build，真机上仍需检查锁屏、灵动岛紧凑态和展开态展示。
- 真机签名与实况状态测试步骤已整理到 `docs/13-iphone-signing-and-live-activity-test.md`。

最新一次 Windows SwiftPM 测试结果：16 个测试全部通过。
最新一次新 Mac SwiftPM 测试结果：50 个测试全部通过。
最新一次 iPhone 17 Pro Simulator Debug 构建结果：通过；若遇到 Xcode entitlements 并发打包提示，使用 `-jobs 1` 串行构建可稳定通过。

## 新 Mac 测试命令

若全局 `xcode-select` 尚未切到 Xcode，使用：

```zsh
cd REDACTED_HOME_PATH
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift test
```

若之后手动完成全局切换，可直接使用：

```zsh
cd REDACTED_HOME_PATH
swift test
```

## iOS App 构建命令

```zsh
cd REDACTED_HOME_PATH
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj \
  -scheme MedicationAdherenceApp \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

当前验证结果：

- iPhone 17 Pro 模拟器 Debug build：通过。
- iPhone 17 Pro 模拟器 Debug build（含 MedicationReminderLiveActivityExtension）：通过。
- 2026-06-07 天气/中断逻辑更新后，SwiftPM 50 个 Swift Testing 测试全部通过；iPhone 17 Pro Simulator Debug build 通过。
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
- 根目录接力入口：`START_HERE_NEXT_CODEX.md`。新 Codex 应先读该文件，再读 `README.md`、`docs/08-development-roadmap-and-debugging.md`、`docs/11-development-todo.md` 和 `docs/16-v0.9.3-live-device-issues-handoff.md`。
- 当前 Google Drive 工具仍不支持任意 `.tar.gz` 原始文件上传；Google Doc 记录的是云端索引和校验信息，压缩包本体仍在本机路径。

## iPhone 真机签名与运行

1. 用 Xcode 打开 `REDACTED_HOME_PATH`。
2. 在左侧项目导航选择 `MedicationAdherenceApp` 工程，再选择主 App target `MedicationAdherenceApp`。
3. 打开 `Signing & Capabilities`，确认 Team 选择你的 Apple Developer Team 或个人 Apple ID Team。
4. Bundle Identifier 保持 `com.gwyy.appcontest2026.medicationadherence`；如果 Xcode 提示已被占用，再改成带你个人前缀的唯一值，同时让扩展 bundle id 自动跟随主 App 前缀。
5. 选择扩展 target `MedicationReminderLiveActivityExtension`，确认 Team 与主 App 一致，Bundle Identifier 前缀是主 App 的 Bundle Identifier。
6. 用数据线连接 iPhone，在顶部运行设备下拉菜单选择你的 iPhone。
7. 第一次真机运行若提示信任开发者，在 iPhone 的“设置 > 通用 > VPN 与设备管理”里信任对应开发者。
8. 点击 Xcode 左上角运行。启动后先完成首启通知权限，再进入今日页；在接近提醒时间前后 5 分钟内检查锁屏和灵动岛是否出现用药提醒。

更细的图形界面步骤见：`docs/13-iphone-signing-and-live-activity-test.md`。
