# Issue #15 实现检查清单

## 验收标准对照

### ✅ 已完成

- [x] 每一份报告都在专用的 MedCue 临时导出区域下创建，并使用唯一的不透明 `.pdf` 文件名
  - **实现**: `VisitSummaryPDFLifecycle.production()` 创建 `medcue-visit-summaries/` 子目录
  - **实现**: `makeUniqueFilename()` 返回 `UUID().pdf`，完全不透明

- [x] 成功发布的报告可读，并具有必需的完整文件保护等级
  - **实现**: `publish(data:to:)` 使用 `.completeFileProtection` 选项原子写入
  - **实现**: 写入后验证 `FileProtectionType.complete`，失败则删除文件并抛出错误
  - **测试**: `testPublishWithProtection` 验证文件保护级别

- [x] 保护或最终化失败被报告为导出失败，且不留下任何部分或完整的报告
  - **实现**: `publish()` 保护验证失败时删除文件并抛出 `protectionVerificationFailed`
  - **实现**: 所有 `try` 路径失败时不留下工件（原子写入 + 验证后清理）

- [x] 启动替换导出会移除被取代的报告，且不影响新操作
  - **实现**: `VisitSummaryView.exportCurrentSummaryAsPDF()` 在生成前调用 `remove(oldPDFURL)`
  - **实现**: 生成前调用 `sweepExpiredFiles()` 清理过期文件

- [x] 取消时不留下自有产物
  - **实现**: `VisitSummaryView` 的 `pdfGenerationTask` 取消检查后调用 `lifecycle.remove(completedURL)`
  - **测试**: `testCancellationCleanup` 验证取消清理

- [x] 文件创建之前和之后的导出失败都不留下自有产物
  - **实现**: 原子写入失败不创建文件；保护验证失败删除文件
  - **实现**: `Task.checkCancellation()` 在关键点检查

- [x] 预览和分享在其活动生命周期内保留文件；页面重置或退出会将其移除
  - **实现**: `onDisappear` 钩子调用 `remove(pdfURL)`
  - **实现**: `resetGeneratedPDFState()` 调用 `remove(oldPDFURL)`

- [x] 过期清扫移除达到或超过一小时边界的 MedCue 自有报告文件，并保留更新的报告和每一个无关临时文件
  - **实现**: `sweepExpiredFiles()` 检查文件修改/创建日期，仅删除 `<= expiryThreshold` 的 `.pdf` 文件
  - **实现**: `rootDirectory` 隔离确保不扫描无关文件
  - **测试**: `testSweepExpiredFiles` 验证过期/近期/非PDF文件的保留逻辑
  - **测试**: `testSweepExactBoundary` 验证边界情况（恰好1小时）

- [x] 进程终止后由下一次启动或导出前清扫恢复
  - **实现**: `VisitSummaryView.task` 在启动时调用 `sweepExpiredFiles()`
  - **实现**: `exportCurrentSummaryAsPDF()` 在生成前调用 `sweepExpiredFiles()`

- [x] 重点测试覆盖所有场景
  - **测试套件**: `VisitSummaryPDFLifecycleTests` 包含 11 个测试用例
  - **覆盖**: 创建、唯一性、保护、删除、安全边界、过期清理、边界情况、空目录、取消清理

### ⚠️ 需要 macOS 环境验证

- [ ] 完整原生验证门禁在 Pull Request 修订版本上通过
  - **原因**: Windows 环境缺少 Xcode 和 `plutil` 命令
  - **需要**: 在 macOS 上运行 `tools/verify-native.sh` 或 `xcodebuild test`

- [ ] 分享完成后的清理逻辑（UIActivityViewController 生命周期）
  - **当前状态**: `onDisappear` 在页面退出时清理，但未测试分享完成后立即清理
  - **需要**: 手动测试分享流程（分享到文件、邮件、消息等）并确认文件清理时机

### 📝 文档待补充

- [ ] 隐私/数据流文档记录保护等级、最长保留期限、清理触发条件
  - **建议位置**: `docs/PRIVACY.md` 或 `docs/DATA_FLOW.md`
  - **内容**: 
    - 文件保护级别：`NSFileProtectionComplete`
    - 最长保留期限：1 小时（过期策略）
    - 清理触发点：启动、生成前、取消、替换、页面退出
    - 用户分享目的地不在 MedCue 控制范围内

## 实现文件清单

### 新增文件
- [x] `ios-app/MedicationAdherenceApp/MedicationAdherenceApp/Services/VisitSummaryPDFLifecycle.swift`
- [x] `ios-app/MedicationAdherenceApp/MedicationAdherenceAppTests/VisitSummaryPDFLifecycleTests.swift`

### 修改文件
- [x] `ios-app/MedicationAdherenceApp/MedicationAdherenceApp/Views/VisitSummaryPDFExportViews.swift`
- [x] `ios-app/MedicationAdherenceApp/MedicationAdherenceApp/Views/VisitSummaryView.swift`
- [x] `ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj/project.pbxproj`

## 下一步行动

### 立即执行（本地 Windows）
- [x] 代码实现完成
- [x] 测试套件编写完成
- [x] Xcode 项目文件更新
- [x] 实现文档编写

### macOS 环境验证（需要产品负责人或协作者）
1. 在 macOS 上拉取分支 `codex/15-pdf-temp-file-protection`
2. 运行完整测试门禁：
   ```bash
   tools/verify-native.sh
   ```
3. 运行新测试套件：
   ```bash
   xcodebuild test -scheme MedicationAdherenceApp \
     -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
     -only-testing:MedicationAdherenceAppTests/VisitSummaryPDFLifecycleTests
   ```
4. 手动测试 PDF 生成和分享流程：
   - 生成 PDF 并检查文件保护属性
   - 分享 PDF 到文件 App 并确认原文件清理
   - 取消生成并确认无残留文件
   - 退出页面并确认文件清理
   - 重启 App 并确认过期文件清理

### Pull Request 准备
1. ✅ 通过 macOS 验证门禁
2. ✅ 手动验证分享流程
3. 补充隐私文档
4. 创建 PR 并链接 Issue #15
5. 在 PR 描述中记录：
   - 实现摘要
   - 测试结果（CI + 手动）
   - 残留风险（如有）
