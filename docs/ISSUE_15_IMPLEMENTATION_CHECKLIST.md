# Issue #15 实现检查清单

当前实现与验证以 PR #60 的最新 HEAD 和 CI 为准；下列代码项需要在该提交完成验证后才算验收通过。

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

- [x] 预览和分享期间保留文件，消费者结束后清理
  - **实现**: 预览与系统分享各持有独立租约；完成、取消或界面消失均释放一次，删除延至最后一个租约结束
  - **测试**: 租约测试覆盖延期删除、重复完成回调和新旧导出隔离

- [x] 过期清扫移除达到或超过一小时边界的 MedCue 自有报告文件，并保留更新的报告和每一个无关临时文件
  - **实现**: `sweepExpiredFiles()` 检查文件修改/创建日期，仅删除 `<= expiryThreshold` 的 `.pdf` 文件
  - **实现**: `rootDirectory` 隔离确保不扫描无关文件
  - **测试**: `testSweepExpiredFiles` 验证过期/近期/非PDF文件的保留逻辑
  - **测试**: `testSweepExactBoundary` 验证边界情况（恰好1小时）

- [x] 进程终止后由下一次启动或导出前清扫恢复
  - **实现**: `VisitSummaryView.task` 在启动时调用 `sweepExpiredFiles()`
  - **实现**: `exportCurrentSummaryAsPDF()` 在生成前调用 `sweepExpiredFiles()`

- [x] 重点测试覆盖主要失败与所有权边界
  - **测试套件**: `VisitSummaryPDFLifecycleTests` 使用隔离根目录、注入的写入/属性失败和发布后取消点
  - **覆盖**: 保护、部分写入清理、属性检查失败、过期边界、无关文件保留、预览/分享租约及替换

### ⚠️ 待精确提交验证

- [ ] 完整原生验证门禁在 Pull Request 修订版本上通过
  - **需要**: 在当前 HEAD 完成聚焦测试、完整 `tools/verify-native.sh` 与 CI

- [ ] Simulator 分享完成与取消的界面检查
  - **需要**: 观察活动完成前文件仍在，活动返回后自有临时文件被清理

### 📝 隐私说明

- [x] `docs/24-privacy-data-flow-audit-20260727.md` 记录 `NSFileProtectionComplete`、一小时过期阈值、清理触发点和外部分享边界。过期清理发生在下一次启动页面或导出前，不声称进程终止后恰好一小时自动删除。

## 实现文件清单

### 新增文件
- [x] `ios-app/MedicationAdherenceApp/MedicationAdherenceApp/Services/VisitSummaryPDFLifecycle.swift`
- [x] `ios-app/MedicationAdherenceApp/MedicationAdherenceAppTests/VisitSummaryPDFLifecycleTests.swift`

### 修改文件
- [x] `ios-app/MedicationAdherenceApp/MedicationAdherenceApp/Views/VisitSummaryPDFExportViews.swift`
- [x] `ios-app/MedicationAdherenceApp/MedicationAdherenceApp/Views/VisitSummaryView.swift`
- [x] `ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj/project.pbxproj`

## 下一步行动

### 当前下一步

在 macOS 上运行聚焦测试及完整门禁，修正失败后提交精确 HEAD；运行 Simulator 分享与预览检查，并在 PR #60 记录实际结果。物理设备文件保护行为仍属 #17 发布证据边界。
