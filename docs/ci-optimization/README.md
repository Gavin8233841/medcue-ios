# CI 优化项目文档

## 概述

本目录包含 GitHub Actions CI 优化的相关文档和实施计划。

## 相关 Issue

- **Issue #64**: [优化 GitHub CI 运行时间以应对项目文件增长](https://github.com/Gavin8233841/medcue-ios/issues/64)

## 文档清单

### 1. `issue-64-handoff.md` - 完整接力文档

**用途**: 提供给后续开发者的完整实施指南

**包含内容**:
- 项目背景和当前 CI 架构分析
- 详细的优化方案（3 个优先级，7 个具体措施）
- 分阶段实施路线图（4 个阶段）
- 验证清单和成功标准
- 常见问题解决方案
- 关键命令和文件清单

**目标读者**: 负责实施 CI 优化的开发者（推荐使用 Sonnet 5 模型）

---

## 快速开始

### 如果你是接手此优化任务的开发者

1. **阅读接力文档** (15 分钟)
   ```bash
   cd docs/ci-optimization
   # 在编辑器中打开 issue-64-handoff.md
   ```

2. **了解当前状态**
   - 查看 [Issue #64](https://github.com/Gavin8233841/medcue-ios/issues/64)
   - 查看最近的 CI 运行：`gh run list --workflow=native-verification.yml --limit 10`

3. **建立性能基线**
   - 记录最近 10 次 Full lane 的运行时间
   - 平均时间应该接近 60 分钟超时设置

4. **开始第一阶段实施**
   - 从 Swift Package Manager 缓存开始（最低风险，快速见效）
   - 创建分支：`git checkout -b optimize-ci-phase-1`
   - 按照 `issue-64-handoff.md` 第一阶段步骤执行

---

## 预期成果

### 短期目标（第一阶段，1-2 天）
- ✅ 实现 SPM 和模块缓存
- ✅ Full lane 运行时间降至 40-47 分钟
- ✅ 缓存命中率达到 70%+

### 中期目标（第二阶段，1 周）
- ✅ 实现测试并行化
- ✅ Full lane 运行时间降至 25-35 分钟
- ✅ 所有测试套件稳定运行

### 长期目标（第三、四阶段，按需）
- ✅ 实现细粒度 lane 分类
- ✅ 针对特定变更类型进一步优化
- ✅ Full lane 最终运行时间降至 15-30 分钟

---

## 关键指标追踪

### 运行时间（分钟）

| 阶段 | Full Lane | Docs Lane | Broker Lane | 目标 |
|------|-----------|-----------|-------------|------|
| 基线 | ~60 | ~5 | ~5 | - |
| 第一阶段后 | 40-47 | ~5 | ~5 | <50 |
| 第二阶段后 | 25-35 | ~5 | ~5 | <35 |
| 第三阶段后 | 15-30 | ~5 | ~5 | <30 |

### 缓存效率

| 缓存类型 | 目标命中率 | 预期节省时间 |
|---------|-----------|-------------|
| Swift Packages | >80% | 8-12 分钟 |
| Xcode Modules | >70% | 5-8 分钟 |
| DerivedData (可选) | >60% | 3-5 分钟 |

---

## 维护说明

### 当添加新的依赖时
- 确保缓存键包含 `Package.resolved` 哈希
- 第一次运行会因缓存未命中而较慢，这是正常的
- 后续运行应该恢复到优化后的速度

### 当修改 CI 配置时
- 测试所有三个 lane（docs/broker/full）
- 确保 aggregate job 的逻辑保持同步
- 保持安全检查机制不被破坏

### 当遇到缓存问题时
- 检查 Actions 日志中的缓存命中/未命中信息
- 必要时手动清除缓存：Settings → Actions → Caches
- 参考 `issue-64-handoff.md` 的"可能遇到的问题"章节

---

## 相关资源

- [GitHub Actions Cache 文档](https://docs.github.com/en/actions/using-workflows/caching-dependencies-to-speed-up-workflows)
- [Xcode Build Performance](https://developer.apple.com/documentation/xcode/improving-build-efficiency-with-build-performance-analysis)
- [项目 CI 配置](../../.github/workflows/native-verification.yml)

---

**最后更新**: 2026-08-24  
**负责人**: 待分配  
**状态**: 📝 规划完成，等待实施