# START HERE - 下一位 Codex 接力说明

如果你是新的 Codex，请先读完本文件，再读 `README.md`、`docs/08-development-roadmap-and-debugging.md`、`docs/11-development-todo.md`、`docs/15-codex-handoff-v0.9.2.md`、`docs/16-v0.9.3-live-device-issues-handoff.md`、`docs/17-stage-check-20260607.md`。不要从零讨论产品方向，本项目已经进入 iOS App 打磨和实机问题修复阶段。

## 一句话说明

这是一个参加 2026 中国高校计算机大赛移动应用创新赛的 iPhone/iPad App 项目，方向是健康医疗与养老，核心产品是“用药依从性管理”：帮助用户录入药品、生成提醒、记录服药、查看风险提示、导出复诊沟通资料，并在用户授权后接入合规医疗 AI 做说明书可读化和用药记录辅助解释。

## 当前路径和工程

- 项目根目录：`REDACTED_HOME_PATH`
- Swift 核心包：`REDACTED_HOME_PATH`
- iOS 工程：`REDACTED_HOME_PATH`
- App Target：`MedicationAdherenceApp`
- Bundle ID：`com.gwyy.appcontest2026.medicationadherence`
- 当前主界面：今日、药品、AI 助手、风险、设置五个 Tab

## 绝对安全规则

- 禁止未经确认执行任何批量、递归、通配符删除。
- 禁止 `git clean`、`git reset --hard`、`git checkout -- .` 等破坏性 Git 操作。
- 不要删除目录，不要清理旧备份，不要覆盖用户已有未提交修改。
- 不要修改项目目录之外的文件，除非用户明确给出绝对路径。
- 当前 Git 状态大量文件显示未跟踪，这不代表它们可以删除；这是历史接力后的现状。
- 不确定路径、字段、Keychain 键名、JSON 路径、Bundle ID、API 字段时，先读文件或日志，不要猜。
- 不要把真实 API Key 写入源码、README、文档、测试、构建日志或 App 可静态读取的位置。
- 医疗边界：只做风险提示、依从性提醒、说明书可读化、记录整理和建议咨询医生/药师；不做诊断、处方、剂量调整或疗效判断。

## 用户和协作方式

- 用户不是 Swift 开发者，目标是尽量完全依赖 Codex 完成开发和比赛材料。
- 用户希望 Codex 主动推进实现、编译、验证和交接，不要停留在方案讨论。
- 遇到必须用户抉择的事项再问；一般工程判断直接读代码后处理。
- 用户明确不用 Expo，本项目是原生 SwiftUI + SwiftPM。

## 比赛和产品策略

- 参赛路线：启迪主线，启明保底。
- 不走启航：没有已上架或 TestFlight App。
- 初赛截止：启明/启迪为 2026-06-30 23:59。
- 初赛交付：作品说明文档必交，可选 App 效果图或宣传海报 1 张。
- 指导老师：计划由班主任挂名。
- 产品风格参考 Apple 健康：克制、清晰、老人友好、大点击区域、舒适字体和间距。

## 已完成的主要能力

- `swift-core`：纯 SwiftPM 核心逻辑包，不直接依赖 SwiftUI、SwiftData、UserNotifications、Vision、HealthKit。
- 核心测试：最近记录为 46 个 Swift Testing 测试通过。
- iOS App：iPhone 17 Pro / iPad Pro 模拟器 Debug build 通过。
- 2026-06-07 阶段检查：SwiftPM 46 个测试通过；修复 `MedicationsView.swift` 中 `.paused` 误用为 `.interrupted` 后，iPhone 17 Pro Simulator Debug build 通过。
- 2026-06-07 继续推进：连续打卡统计、HealthKit 授权完成态、5 个演示药品中文化、药品页服药记录入口简化、用药概览跳转、PDF 报告视觉第一版、今日页局部动画和灵动岛展开态安全区收敛已完成并通过 iOS 构建。
- 数据模型：药品、计划、今日任务、风险卡片、服药操作日志、AI 授权、AI 聊天记录、药盒库存。
- 示例数据：最近 60 天、5 个演示药品的服药任务，包含少量漏服、延后和修正记录。
- 今日页：待服药、已服用、稍后、忽略、已处理折叠、横滑撤销/归档/详情、全部完成绿色反馈。
- 药品页：健康式概览、药品分组、药品卡片、药品详情、药盒低量、服药记录入口。
- 记录页：折叠时周历，展开时月历，每天可点开查看服药详情并修正。
- 风险页：严重风险置顶收敛、三类风险总览、二级详情和单条详情。
- AI 助手：聊天式界面、首次确认弹窗、授权范围、最多展示近 5 次对话、归档历史、两列快捷问题、图片咨询入口。
- 外部模型：豆包 Ark Responses API 为后台默认供应商，百川医疗大模型保留为备用适配器。前端不显示配置。
- iOS 能力：通知、iOS 26+ AlarmKit 分支、HealthKit 准备、ActivityKit/WidgetKit 实况状态扩展、Sign in with Apple 和 iCloud 备份准备页。
- 导出：设置页已有服药记录生成、纯文本预览和 PDF 导出入口。

## 最近必须知道的已改但需验证内容

上一轮已经修改 `ios-app/MedicationAdherenceApp/MedicationAdherenceApp/Views/MedicationsView.swift`：

- 药品页新增更明确的 `Section("服药记录")`。
- 服药记录入口可进入 `RecordsView`。
- 药品分组三张状态卡做了固定高度和中文防挤压处理。
- 药品卡里的多个状态标签增加了宽度约束。

用户随后指出的药品 Tab 服药记录入口蓝色背景框问题已处理：当前入口只保留日历 icon、天数和核心数字，仍需继续做实际手感复核。

## 用户最新实机反馈和下一步最高优先级

用户在 iPhone 实机部署和界面检查后指出以下问题。下一位 Codex 应优先处理这些，而不是继续扩展新功能：

1. 今日 Tab 下撤销已完成服药时动画不自然，卡顿明显。已移除整页 List 全局动画并改为局部短动画，仍需实机复核。
2. iPhone 实机部署时医疗 AI 无法调用。
3. 灵动岛 UI 存在安全区问题。已先收敛展开态字号、边距和单行缩放，仍需真机复核。
4. HealthKit 授权完成后，授权选项没有消失或转为完成态。已增加持久完成态，仍需真机授权流程复核。
5. 所有写入的药品名称和展示内容需要改为中文。5 个演示药品已中文化，仍需继续扫全 App 残余英文。
6. 记录页面连续成功打卡天数不正常。核心算法已修复并新增测试。
7. 药品 Tab 下服药记录入口的蓝色背景框多余，只保留数字和日历 icon。已简化。
8. 用药概览卡片需要改为可交互跳转。已跳转记录页。
9. PDF 导出功能设计不理想，需要参考用户提供图片中的排版和可视化效果。已完成第一版报告式 PDF，仍可继续视觉打磨。

## 建议执行顺序

1. 先读代码，不猜字段：重点看 `TodayView.swift`、`RecordsView.swift`、`MedicationsView.swift`、`SettingsView.swift`、AI provider/Keychain 相关文件、Live Activity extension。
2. 跑 iOS 构建，确认当前代码能编译。
3. 复核今日撤销动画：局部动画已改，下一步重点看实机手感，必要时引入撤销提示条或延迟重排。
4. 复核记录连续打卡统计：核心算法已修，确认 UI 文案是否符合用户预期。
5. 继续扫药品中文化：演示药品已中文化，继续处理残余用户可见英文。
6. 复核药品页：服药记录入口和用药概览跳转已改，继续看实际手感。
7. 复核 HealthKit 授权完成态：代码已写入本地状态，仍需真机权限流程确认。
8. 排查实机医疗 AI：从 Keychain/启动环境变量读取、供应商适配器、网络请求、错误脱敏、真机网络权限逐项查证；不要把 Key 写入源码。
9. 真机复核灵动岛安全区：代码已收敛布局，仍需在锁屏、紧凑态、展开态看实际效果。
10. 继续打磨 PDF 报告视觉：第一版报告式 PDF 已完成，可继续提高图表化和排版质感。
11. 跑 `swift test` 和 iOS build，必要时截图留证。
12. 更新本文档、`docs/08-development-roadmap-and-debugging.md`、`docs/11-development-todo.md`。

## 常用验证命令

SwiftPM 测试：

```zsh
cd REDACTED_HOME_PATH
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift test
```

iOS 构建：

```zsh
cd REDACTED_HOME_PATH
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj \
  -scheme MedicationAdherenceApp \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  CODE_SIGNING_ALLOWED=NO \
  -jobs 1 \
  build
```

## 重要文档索引

- `README.md`：项目总览。
- `docs/08-development-roadmap-and-debugging.md`：环境、构建、阶段、备份索引。
- `docs/09-api-configuration.md`：外部 API 策略，豆包和百川适配。
- `docs/11-development-todo.md`：当前待办和风险清单。
- `docs/13-iphone-signing-and-live-activity-test.md`：真机签名和灵动岛测试。
- `docs/15-codex-handoff-v0.9.2.md`：上一轮完整接力。
- `docs/16-v0.9.3-live-device-issues-handoff.md`：最新实机问题接力。
- `docs/17-stage-check-20260607.md`：无法使用 iOS builder 插件时做的阶段性检查，记录当前构建、测试、代码风险和明天推进顺序。
- `ios-app/MedicationAdherenceApp/README.md`：iOS App 工程说明。

## 备份和云端索引

- 本地备份目录：`REDACTED_HOME_PATH`
- 最新完整源码备份：`backups/appcontest-2026-prep-v0.9.2-codex-handoff-before-new-api-source-20260605-230635.zip`
- v0.9.2 SHA-256：`52315d9e995ba5e8fb89d73a7d84aa2def7ae9460986a63f5a80ee352f10c78c`
- 最新接力文档备份：`backups/appcontest-2026-prep-v0.9.3-live-device-issues-handoff-docs-20260606-1313.zip`
- v0.9.3 接力文档备份 SHA-256：`c37330997535503ab5f596efa277ec175adf07ce890ec6bc42f7ded1fe251d17`
- Google Drive 备份索引：`https://docs.google.com/document/d/1QcCIeRAt9rVuA2gtVu6A8FIt0d_Z-Z2-cRxbDUwuUSY`
- 当前 Google Drive 工具只写入云端索引，不支持直接上传 `.zip` 或 `.tar.gz` 原始文件；压缩包本体在本机备份目录。

## 可直接复制给新 Codex 的启动提示

```text
请在 REDACTED_HOME_PATH 继续这个中国高校计算机大赛移动应用创新赛项目。先读取 START_HERE_NEXT_CODEX.md、README.md、docs/08-development-roadmap-and-debugging.md、docs/11-development-todo.md、docs/16-v0.9.3-live-device-issues-handoff.md。不要从零讨论产品方向，不要删除、回滚或清理任何文件。当前项目是原生 SwiftUI + SwiftPM，用药依从性 App，五 Tab 为今日、药品、AI 助手、风险、设置。2026-06-07 已完成第一批实机反馈修复：连续打卡统计、HealthKit 完成态、演示药品中文化、药品页服药记录入口简化、用药概览跳转、PDF 报告视觉第一版、今日页局部动画和灵动岛展开态安全区收敛。下一步优先做：真机复核今日撤销手感、排查实机医疗 AI 无法调用、真机复核灵动岛安全区、继续扫残余英文、继续打磨 PDF 和前端细节。先跑 iOS 构建和必要的 SwiftPM 测试，再逐项修复并更新接力文档。
```
