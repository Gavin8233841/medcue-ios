# MedicationAdherenceApp

SwiftUI iOS App 工程。默认中文展示名为“用药跟踪”，英文兼容名为 `MedCue`。工程使用本地 Swift Package `../../swift-core` 接入 `MedicationAdherenceCore`。

## 工程信息

- Xcode 工程：`ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj`
- Target：`MedicationAdherenceApp`
- Scheme：`MedicationAdherenceApp`
- Bundle ID：`com.gwyy.appcontest2026.medicationadherence`
- 默认中文名：用药跟踪
- 英文兼容名：MedCue
- 最低系统：iOS 17.0
- 设备：iPhone 优先，iPad 基础自适应

## 已接入能力

- SwiftUI 五 Tab 主流程：今日、药品、智能体、记录、个人；风险复核已并入药品页。
- 药品与记录分层：药品页保留健康式用药概览，四个小卡片分别进入药品总览、今日待处理、药盒管理和风险复核；记录页保留概览、日历、趋势和记录四个入口；复诊资料、Apple 健康、医疗智能体共享和应用设置集中在个人页；药品分组用三张状态卡展示正在服用、服用中断和归档药物。
- SwiftData 本地存储：药品、用户确认药品照片、用药计划、疗程时间、今日任务、风险卡片、药品库存、服药操作日志、智能体授权和智能体聊天记录。
- 本地初始数据：布洛芬、对乙酰氨基酚、人工泪液、氯雷他定、维生素 D3；内部保留说明书匹配字段，用户端不展示开发标签。
- `MedicationAdherenceCore`：
  - 风险评估聚合。
  - 说明书可读化卡片。
  - 依从性洞察。
  - 药品库存估算和低库存提醒。
  - 服药记录生成。
  - 本地通知负载规划。
  - 导入审核入口。
- UserNotifications：通知权限请求和稍后提醒安排。
- ActivityKit / WidgetKit：已接入 `MedicationReminderLiveActivityExtension`。用药时间前后 5 分钟内尝试启动实况状态；标记已服用、忽略、撤销或归档后结束。扩展提供锁屏、灵动岛紧凑态、展开态和最小态展示。
- 医疗 AI：已接入首次使用确认、授权弹窗、共享范围控制、聊天式气泡界面、底部输入栏、两列快捷入口、图片咨询入口、请求审计记录和供应商适配器；豆包 Ark Responses API 为后台默认供应商，百川适配器保留为备用，供应商和凭据配置不在前端展示。
- API 密钥：演示阶段通过启动环境或 iOS Keychain 读取，不写入源码、文档、测试或构建日志；发送失败时只展示脱敏后的错误说明，不保存原始响应、请求正文或 API 密钥。
- 添加药品：加号提供手动添加、医嘱/OCR 导入、药盒条码扫描三入口；OCR 和条码入口会生成导入复核草稿，保存前必须二次确认。
- 今日页：已服用、稍后、忽略会生成操作日志；稍后按原计划提醒时间顺延 30 分钟，离计划时间很久时会先二次确认，避免打乱服药时间线；计划时间 5 分钟后会预排升级提醒，15 分钟未操作会在 App 启动、回前台或今日页刷新时自动记录为忽略；提前 6 小时以上确认已服用会二次确认。完成后从待办区移出，已处理记录支持横滑撤销、归档和详情；全部服用后显示绿色完成态；外用或滴眼类记录显示“已使用”；底部提示改为天气与环境用药关注，不再重复风险页警示。今日页、通知按钮和实况活动按钮共用同一逻辑剂量组处理，避免真机锁屏或灵动岛操作后残留重复待处理任务；稍后只给主任务保留顺延后的系统提醒，避免重复推送。
- 药品页：已改成健康式概览，集中展示药品数、待处理任务、药盒低量和今日完成率；概览四个小卡片分别跳转到对应详情，不再整体跳到记录页。药品卡片显示药盒编号、药盒低量提示、下次任务、记录数和剩余量。详情页预留大图位置，支持用户选择药盒/药品照片、真机拍照上传入口、药盒编号备注、疗程起止、多提醒时间、剂量生效日期、剂量变化记录、来源说明和药盒库存编辑；药盒管理页按真实记录展示日均消耗和预计可用天数，估算结果只提示核对实物。
- 用药趋势仪表盘：至少 7 个有提醒日期后，按用药纪律、时间稳定、剂量变化、用药负担和健康信号五个主题展示趋势；图表使用 App 内真实提醒、记录、剂量变化、药品状态和用户授权 HealthKit 样本，未来未到期提醒不提前参与评分，不生成诊断或剂量建议。
- 记录页：首屏为概览、日历、趋势和记录四个入口；日历详情支持近 24 个月浏览，每个日期都可点开查看当天服药详情和当天生效的剂量变化，并进入记录修正。
- 个人页与应用设置：个人页集中复诊资料、Apple 健康、医疗智能体共享、账号备份和应用设置；应用设置已接入提醒、外观、PDF 导出准备和主动分享入口。未配置 CloudKit 容器前不会开始云同步，也不宣称云端端对端加密。
- 风险复核：作为药品页子模块运行，置顶警示只展示严重程度更高的禁忌或相互作用，且最多直接展示 1 条，多余严重项折叠；三类风险总览改为竖排长卡并进入二级详情；单条警示可点开查看依据和安全边界。
- Vision：已接入本机 OCR、药盒条码图片识别、真机相机扫码和智能体聊天图片文字读取；识别结果只作为待确认录入草稿或软件相关咨询上下文。
- HealthKit：已接入授权请求、读取指标范围说明、HealthKit entitlement 和近 56 天生命体征样本读取；趋势页只按时间关系和波动稳定度展示，不做诊断或处方决策。

## 构建命令

当前主线工具链为 `/Applications/Xcode-beta.app`，Xcode 27.0 beta。系统默认 `xcode-select -p` 应指向 `/Applications/Xcode-beta.app/Contents/Developer`；`/Applications/Xcode.app` 的 Xcode 26.5 只作为回退保留。

```zsh
cd REDACTED_HOME_PATH
xcodebuild \
  -project ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj \
  -scheme MedicationAdherenceApp \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO \
  -jobs 1 \
  build
```

## 当前验证

- iPhone 17 Pro 模拟器 Debug build：通过。
- iPhone 17 Pro 模拟器 Debug build（含 MedicationReminderLiveActivityExtension）：通过。
- iPad Pro 13-inch (M5) 模拟器 Debug build：通过。
- `swift-core` Swift Testing：86 个测试通过。
- iPhone 17 Pro 模拟器可安装并启动。
- 2026-06-10 最新提醒口径：今日页、通知按钮和实况活动的“稍后”统一按原计划提醒时间顺延 30 分钟；离计划时间很久时，今日页会先显示药物行内二次确认卡。
- 首屏截图：`artifacts/ios-app-home.png`。
- 本轮改造后截图：`artifacts/ios-app-after-ai-tabs.png`。
- Vision/HealthKit 改造后启动截图：`artifacts/ios-app-after-vision-healthkit.png`。
- 库存/复诊摘要改造后启动截图：`artifacts/ios-app-after-stock-visit-summary.png`。
- 百川医疗 AI 配置截图：`artifacts/ios-app-after-baichuan-ai.png`。
- 首启引导截图：`artifacts/ios-app-onboarding-frontend-pass.png`。
- 首启教程截图：`artifacts/onboarding-tutorial-page1-v09-compact-after-wait.png`、`artifacts/onboarding-tutorial-page2-add-medication-v09-polished.png`。
- 聊天式 AI 截图：`artifacts/ios-app-ai-chat-frontend-pass.png`。
- 风险页重排截图：`artifacts/ios-app-risks-frontend-pass.png`。
- 账号与备份截图：`artifacts/ios-app-account-backup-frontend-pass.png`。
- 药品页健康式概览截图：`artifacts/ios-app-medications-health-style-pass.png`。
- 药品详情照片入口截图：`artifacts/ios-app-medication-detail-photo-pass.png`。

## 真机运行

1. 用 Xcode 打开 `ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj`。
2. 选择主 App target `MedicationAdherenceApp`，在 `Signing & Capabilities` 中设置你的 Team。
3. 选择 `MedicationReminderLiveActivityExtension` target，确认 Team 与主 App 一致，Bundle Identifier 前缀跟随主 App。
4. 连接 iPhone，在 Xcode 顶部设备菜单选择你的 iPhone。
5. 点击运行。首次安装后按 iPhone 提示信任开发者，并在 App 首启第一页开启通知权限。
6. 测试灵动岛/实况状态时，把某个今日任务时间调到当前时间前后 5 分钟内，回到今日页等待触发；标记已服用或忽略后，实况状态应自动结束。
