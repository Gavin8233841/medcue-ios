# Issue #15: PDF 临时文件保护 - 实现总结

## 实现内容

### 1. 新增 `VisitSummaryPDFLifecycle` 服务
- **位置**: `ios-app/MedicationAdherenceApp/MedicationAdherenceApp/Services/VisitSummaryPDFLifecycle.swift`
- **职责**: 管理就诊摘要 PDF 的完整生命周期，包括创建、保护、清理

**核心能力**:
- 生成不透明的唯一文件名（UUID.pdf），避免暴露用户信息
- 强制应用 `NSFileProtectionComplete` 文件保护
- 验证文件保护是否成功应用
- 原子写入 + 保护验证的组合操作
- 定时清理超过 1 小时的过期文件
- 拒绝删除非自有目录的文件（安全边界）

**API 设计**:
```swift
struct VisitSummaryPDFLifecycle {
    func ensureRootDirectory() throws
    func makeUniqueFilename() -> String
    func publish(data: Data, to targetURL: URL) throws -> URL
    func remove(_ url: URL) -> Bool
    func sweepExpiredFiles() -> Int
}
```

### 2. 修改 `VisitSummaryPDFExporter`
- **修改**: 从接受 `targetURL` 改为接受 `lifecycle` 参数
- **行为变化**:
  - 生成唯一不透明文件名（不再包含"复诊资料"和时间戳）
  - 通过 `lifecycle.publish()` 确保文件保护
  - 自动验证保护级别，失败则删除文件并抛出错误

### 3. 修改 `VisitSummaryView`
**新增生命周期管理点**:
- **启动时**: 清理过期 PDF（`pdfLifecycle.sweepExpiredFiles()`）
- **生成前**: 清理过期文件 + 删除旧 PDF
- **取消时**: 删除已生成但被取消的 PDF 工件
- **离开页面时**: 删除当前 PDF
- **重置状态时**: 删除旧 PDF

**文件名变化**:
- 旧: `复诊资料-<timestamp>.pdf`（暴露用户意图和时间信息）
- 新: `<UUID>.pdf`（完全不透明，无信息泄漏）

### 4. 新增测试套件 `VisitSummaryPDFLifecycleTests`
- **位置**: `ios-app/MedicationAdherenceApp/MedicationAdherenceAppTests/VisitSummaryPDFLifecycleTests.swift`
- **覆盖场景**:
  - 创建受保护的根目录
  - 生成唯一不透明文件名
  - 发布时强制文件保护并验证
  - 删除自有文件
  - 拒绝删除非自有目录的文件（安全测试）
  - 清理过期文件并保留近期文件
  - 边界情况：恰好在过期阈值的文件
  - 空目录和不存在目录的清理行为
  - 取消后的工件清理

**测试策略**:
- 使用注入的 `fileManager` 和 `clock` 以支持时间控制
- 每个测试使用独立的临时目录（UUID 隔离）
- 测试后自动清理临时文件

## 隐私和安全改进

### 之前的问题
1. **文件名信息泄漏**: `复诊资料-<timestamp>.pdf` 暴露用户意图和生成时间
2. **无文件保护**: 未设置 `NSFileProtectionComplete`，设备解锁时文件可读
3. **无生命周期管理**: PDF 永久留在临时目录，进程终止后无清理
4. **无取消清理**: 取消生成后文件残留

### 现在的保护
1. **不透明文件名**: 使用 UUID，无法从文件名推断内容或用户身份
2. **完整文件保护**: `NSFileProtectionComplete` 确保设备锁定时文件不可读
3. **保护验证**: 写入后验证保护级别，失败则删除文件并报错
4. **自动清理**: 启动时/生成前清理超过 1 小时的文件
5. **取消清理**: 任务取消或被替代时立即删除工件
6. **离开清理**: 用户离开页面时删除当前 PDF
7. **安全边界**: 拒绝删除非自有目录的文件

## 发布门禁符合性

### 已满足的要求
- ✅ PDF 临时文件受 `NSFileProtectionComplete` 保护
- ✅ 文件名不透明，不泄漏用户信息
- ✅ 进程终止后的清理（启动时 sweep）
- ✅ 取消/替换时的清理
- ✅ 离开页面时的清理
- ✅ 有界的保留时间（1 小时过期策略）
- ✅ 测试覆盖：生命周期、保护验证、清理策略、安全边界

### 已添加到项目
- ✅ `VisitSummaryPDFLifecycle.swift` 已添加到主 target
- ✅ `VisitSummaryPDFLifecycleTests.swift` 已添加到测试 target
- ✅ Xcode project.pbxproj 已更新（通过 Python 脚本）

## 验证状态

### Windows 环境限制
- ❌ `tools/verify-native.sh` 缺少 `plutil` 命令（macOS 工具）
- ❌ `xcodebuild test` 无输出（Windows 环境无 Xcode）
- ❌ `swift test` 命令不可用

### 需要 macOS 环境验证
```bash
# 在 macOS 上运行完整门禁
tools/verify-native.sh

# 或者运行快速检查
tools/verify-native.sh --quick

# 或者只运行新测试套件
xcodebuild test -scheme MedicationAdherenceApp \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -only-testing:MedicationAdherenceAppTests/VisitSummaryPDFLifecycleTests
```

## 残留工作

### 必需（当前 PR 范围内）
1. **macOS 构建验证**: 在 Xcode 环境中编译确认无语法错误
2. **测试套件运行**: 验证所有测试通过
3. **集成测试**: 手动生成 PDF 并检查：
   - 文件保护级别是否为 Complete
   - 离开页面后文件是否被删除
   - 启动时过期文件是否被清理

### 可选（后续优化）
1. **CI 自动化**: 将文件保护验证添加到发布扫描门禁
2. **性能测量**: 大量 PDF 生成场景下的清理性能
3. **设备验证**: 真机上验证锁屏状态下文件保护有效性

## 修改统计

```
 .../project.pbxproj                                |  6 +++++
 .../Services/VisitSummaryPDFLifecycle.swift        | 150 ++++++++++++++++++
 .../Views/VisitSummaryPDFExportViews.swift         | 30 ++--
 .../Views/VisitSummaryView.swift                   | 31 +++-
 .../Tests/VisitSummaryPDFLifecycleTests.swift      | 180 +++++++++++++++++++++
 5 files changed, 390 insertions(+), 7 deletions(-)
```

## 下一步

**本地工作完成，等待 macOS 环境验证**：
1. 在 macOS 上拉取此分支
2. 运行 `tools/verify-native.sh --quick`
3. 手动测试 PDF 生成和清理行为
4. 确认文件保护级别（可通过 Xcode 或 `xattr` 工具检查）
5. 通过后创建 Pull Request，链接 Issue #15
