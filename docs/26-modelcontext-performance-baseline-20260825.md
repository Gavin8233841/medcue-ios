# ModelContext 性能基准与测量（2026-08-25）

关联 Issue: [#8 - ModelContext 性能测量](https://github.com/Gavin8233841/medcue-ios/issues/8)
关联 PR: TBD

## 背景

根据 `docs/22-architecture-hardening-todo-20260726.md` 第 86 行的要求：

> 对 ModelContext 的查询/保存测量主线程耗时；只有证据显示阻塞时才调整执行模型。

本文档记录 ModelContext 性能测量基础设施的实现、测试结果和性能基准。

## 实现内容

### 1. 性能测量基础设施

新增 `ModelContextPerformanceMetrics.swift`，提供：

- `measureFetch(operation:execute:)` - 测量 fetch 操作性能
- `measureSave(operation:execute:)` - 测量 save 操作性能
- `measureDelete(operation:execute:)` - 测量 delete 操作性能
- `measureOperation(name:operation:execute:)` - 测量通用操作性能

所有测量使用 `OSSignposter` 记录 Signpost intervals，可在 Instruments 中可视化分析。

**性能阈值**：
- 单次操作超过 100ms 会记录 warning 日志
- Delete cascade 操作阈值为 150ms
- Batch 操作阈值为 200ms

### 2. 集成到现有命令

已将性能测量集成到以下命令类：

#### MedicationInventoryCommand
- `inventory-fetch-all-stocks` - 获取所有库存记录
- `inventory-upsert-stock` - 更新或插入库存

#### MedicationProfileCommand
- `profile-fetch-medication-by-id` - 按 ID 获取药品
- `profile-update-medication` - 更新药品资料
- `profile-update-photo` - 更新药品照片

#### MedicationPlanCommand（已有基础）
- `plan.save` - 计划保存（第 64 行）
- `plan.reconcile` - 任务协调（第 202 行）

### 3. 性能测试套件

新增 `ModelContextPerformanceTests.swift`，包含 8 个性能测试：

1. **fetchSingleMedication** - 单个药品查询 < 100ms
2. **fetchMultipleMedications** - 20 个药品查询 < 100ms
3. **saveSingleMedication** - 单个药品保存 < 100ms
4. **saveMedicationWithPlan** - 药品 + 计划保存 < 100ms
5. **fetchTasksByPlanID** - 按计划 ID 查询任务 < 100ms
6. **deleteMedicationCascade** - 级联删除 < 150ms
7. **complexQueryWithPredicates** - 复杂谓词查询 < 100ms
8. **batchInsert** - 批量插入 50 个药品 < 200ms

## Simulator 基准结果

### 测试环境
- 平台：Windows 11 + iOS Simulator
- 测试方法：`swift test` hosted tests
- 存储：内存模式 (`isStoredInMemoryOnly: true`)

### 预期结果
所有 8 项测试应在 Simulator 环境通过，验证：
- 基础 fetch/save/delete 操作在无负载情况下满足性能要求
- 性能测量基础设施正常工作
- Signpost intervals 正确记录

### 真机验证需求（待用户执行）

以下场景需要在真机使用 Instruments 验证：

1. **Release 构建性能**
   - 工具：Instruments - os_signpost
   - 指标：P50/P95 延迟、主线程阻塞时间
   - 场景：药品详情 → 疗程编辑 → 保存

2. **真实数据负载**
   - 数据量：20+ 药品，每个药品 10+ 任务
   - 持久化：真实 SQLite 存储（非内存模式）
   - 操作：today 视图加载、复诊资料生成

3. **并发操作**
   - 场景：后台任务 + 用户交互
   - 监控：Hangs、Hitches、内存峰值

4. **长时间运行**
   - 场景：连续使用 30 分钟
   - 监控：内存泄漏、查询性能退化

## 调整执行模型的条件

根据架构治理清单要求，只有以下证据显示阻塞时才调整执行模型：

### 触发条件
1. **主线程阻塞**：单次 ModelContext 操作在主线程持续 > 200ms
2. **用户可感知卡顿**：Frame drop > 16.67ms (60 FPS)
3. **频繁超时**：> 10% 的操作超过 100ms 阈值

### 不触发调整的情况
- Simulator 测试通过但无真机证据
- 偶发的性能警告（< 5% 操作）
- 内存模式测试的理论性能

### 可选调整方案
如果满足触发条件，考虑：
1. 将查询移到后台 context + detached task
2. 使用 `ModelActor` 隔离持久化操作
3. 添加查询结果缓存（已有 `RevisionSnapshotCache`）
4. 优化 FetchDescriptor 的 predicate 和 sortBy

## 退出条件

- [x] 创建 `ModelContextPerformanceMetrics` 基础设施
- [x] 集成到至少 3 个现有命令类
- [x] 新增 8 项性能测试
- [ ] 本地 hosted tests 全部通过（待验证）
- [ ] CI 远端测试通过
- [ ] 更新 `docs/22-architecture-hardening-todo-20260726.md` 第 86 行状态
- [ ] 真机 Instruments 基准数据（需要用户执行，不阻塞 PR 合并）

## 后续工作

1. **Issue #8 剩余部分**：真机性能数据采集与分析
2. **监控集成**：考虑添加性能指标持久化，用于长期趋势分析
3. **自动化报警**：如果 P95 超过阈值，在 CI 中标记（需要真机 CI runner）

## 参考

- [Apple - Measuring Performance with Signposts](https://developer.apple.com/documentation/os/logging/measuring_performance_with_signposts)
- [SwiftData Performance Best Practices](https://developer.apple.com/documentation/swiftdata/optimizing-performance)
- 项目已有 Signpost 实现：`MedicationPlanCommand.swift:46-49`
