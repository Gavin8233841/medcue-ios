# Issue #64 解决接力文档

## Issue 概述

**Issue 链接**: https://github.com/Gavin8233841/medcue-ios/issues/64
**标题**: 优化 GitHub CI 运行时间以应对项目文件增长
**目标**: 将 Full lane CI 运行时间从 60 分钟降至 15-30 分钟（减少 30-50%）

---

## 项目背景信息

### 仓库信息
- **GitHub 仓库**: https://github.com/Gavin8233841/medcue-ios
- **本地路径**: `<PROJECT_ROOT>`
- **项目类型**: iOS 应用（Swift + Xcode）
- **项目规模**:
  - 214 个 Swift 文件（163 iOS app + 51 Swift Core）
  - 项目总大小约 106MB
  - 1952 个源代码文件

### 当前 CI 架构

**主要配置文件**: `.github/workflows/native-verification.yml`

**CI 流程结构**:
```
1. classify job (ubuntu-24.04, 5分钟)
   ↓
2. 三个并行 lane（根据变更类型选择一个）:
   - docs lane (ubuntu-24.04, 5分钟) - 仅文档变更
   - broker lane (ubuntu-24.04, 5分钟) - 仅 AI broker 变更
   - full lane (macos-26, 60分钟) ⚠️ 需优化
   ↓
3. aggregate job (ubuntu-24.04, 5分钟) - 汇总结果
```

**Full lane 执行步骤**:
1. Git diff 检查
2. Source package 验证
3. Swift Core 测试 (串行)
4. iOS 单元测试 (串行)
5. iOS UI 测试 (串行)
6. Main App Release 构建
7. Watch Simulator Debug 构建
8. watchOS Device Release 构建

### 关键脚本
- `tools/native-verification-classifier.sh` - 变更分类逻辑
- `tools/verify-native.sh` - 本地验证入口脚本（531 行）
- `tools/ios-preflight-check.sh` - iOS 预检查
- `tools/swift-source-size-check.sh` - Swift 源码大小检查

---

## 优化方案详解

### 优先级 1: 快速见效（建议先实施）

#### 1.1 实现 Swift Package Manager 缓存

**文件**: `.github/workflows/native-verification.yml`
**插入位置**: `full` job 中，在 "Check out exact source" 步骤之后

```yaml
      - name: Cache Swift packages
        uses: actions/cache@v4
        with:
          path: |
            .codex-local/native-verification/swift-core/cache
            .codex-local/native-verification/source-packages
          key: ${{ runner.os }}-spm-${{ hashFiles('**/Package.resolved', 'swift-core/Package.swift') }}
          restore-keys: |
            ${{ runner.os }}-spm-
```

**预期收益**: 节省 8-12 分钟（Swift 包下载和编译时间）

#### 1.2 实现测试并行化

**当前问题**:
- Swift Core 测试、iOS 单元测试、iOS UI 测试串行执行
- 总耗时约 15-20 分钟

**优化方案**: 将 full job 拆分为测试矩阵

**实施位置**: `.github/workflows/native-verification.yml`

需要修改的结构：
```yaml
# 将现有的 full job 拆分为两个 job：
# 1. full-build (构建产物)
# 2. full-test (并行测试，依赖 full-build)

full-build:
  name: Full Native Build
  needs: classify
  if: ${{ needs.classify.outputs.lane == 'full' }}
  runs-on: macos-26
  timeout-minutes: 30
  steps:
    # ... 只执行构建步骤，生成 artifacts

full-test:
  name: Full Native Tests (${{ matrix.test-suite }})
  needs: [classify, full-build]
  if: ${{ needs.classify.outputs.lane == 'full' }}
  runs-on: macos-26
  timeout-minutes: 25
  strategy:
    fail-fast: false
    matrix:
      test-suite: [swift-core, ios-unit, ios-ui]
  steps:
    # 根据 matrix.test-suite 运行对应测试
```

**预期收益**: 节省 10-15 分钟（测试并行执行）

#### 1.3 实现 Xcode 模块缓存

**插入位置**: 同 1.1，在缓存步骤区域

```yaml
      - name: Cache Xcode module cache
        uses: actions/cache@v4
        with:
          path: |
            .codex-local/native-verification/module-cache/clang
            .codex-local/native-verification/module-cache/swift
          key: ${{ runner.os }}-xcode-modules-${{ hashFiles('ios-app/**/*.swift', 'swift-core/**/*.swift', '**/Package.resolved') }}
          restore-keys: |
            ${{ runner.os }}-xcode-modules-
```

**预期收益**: 节省 5-8 分钟（模块编译时间）

### 优先级 2: 中等收益（后续实施）

#### 2.1 优化 classifier 支持细粒度构建

**文件**: `tools/native-verification-classifier.sh`

**当前逻辑**:
- 只要涉及 `ios-app/*` 或 `swift-core/*` 就进入 full lane
- full lane 会执行所有构建和测试

**优化目标**:
- 新增 `swift-core-only` lane
- 新增 `watch-only` lane

**实施步骤**:
1. 修改 `native-verification-classifier.sh` 第 172-200 行的分类逻辑
2. 在 `native-verification.yml` 中新增对应的 lane job
3. 更新 `aggregate` job 的验证逻辑

**预期收益**: 针对特定变更类型，节省 10-20 分钟

#### 2.2 实现 DerivedData 部分缓存

**挑战**: DerivedData 包含中间构建产物，体积大且变化频繁

**方案**: 只缓存稳定的预编译框架

```yaml
      - name: Cache prebuilt frameworks
        uses: actions/cache@v4
        with:
          path: |
            .codex-local/native-verification/*/products/*/Build/Intermediates.noindex
          key: ${{ runner.os }}-frameworks-${{ hashFiles('**/Package.resolved') }}
          restore-keys: |
            ${{ runner.os }}-frameworks-
```

**预期收益**: 节省 3-5 分钟

### 优先级 3: 长期优化（可选）

#### 3.1 依赖预编译策略

**方案**: 创建独立的 workflow 定期预编译依赖

**新文件**: `.github/workflows/prebuild-dependencies.yml`

```yaml
name: Prebuild Dependencies
on:
  schedule:
    - cron: '0 2 * * 0'  # 每周日凌晨 2 点
  workflow_dispatch:

jobs:
  prebuild:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v5
      - name: Build Swift packages
        run: |
          swift build --package-path swift-core -c release
      - name: Upload prebuilt cache
        uses: actions/upload-artifact@v4
        with:
          name: swift-dependencies-${{ github.sha }}
          path: .build/
          retention-days: 14
```

**预期收益**: 节省 3-5 分钟

#### 3.2 评估 GitHub Large Runner

**当前**: `macos-26` 标准 runner（3 核 CPU）
**升级**: `macos-26-xlarge`（12 核 CPU）

**成本**: 约 10 倍（但可能缩短 40-50% 的运行时间）

**建议**: 先实施优先级 1-2 的优化，评估后再决定是否升级

---

## 实施路线图

### 第一阶段（立即实施，预计 1-2 天）
- [ ] 实现 Swift Package Manager 缓存（1.1）
- [ ] 实现 Xcode 模块缓存（1.3）
- [ ] 测试验证缓存生效
- [ ] 观察 3-5 次 CI 运行，确认稳定性

**预期收益**: 减少 13-20 分钟

### 第二阶段（短期实施，预计 3-5 天）
- [ ] 设计测试并行化方案（1.2）
- [ ] 拆分 full job 为 build + test matrix
- [ ] 处理 artifacts 共享
- [ ] 更新 aggregate job 逻辑
- [ ] 全面测试并行执行

**预期收益**: 额外减少 10-15 分钟

### 第三阶段（中期优化，预计 1 周）
- [ ] 分析历史变更模式
- [ ] 设计细粒度 lane 分类（2.1）
- [ ] 实现 swift-core-only 和 watch-only lane
- [ ] 实现 DerivedData 部分缓存（2.2）

**预期收益**: 针对特定场景额外减少 10-20 分钟

### 第四阶段（长期优化，按需）
- [ ] 评估依赖预编译收益（3.1）
- [ ] 评估 Large Runner 成本效益（3.2）

---

## 技术注意事项

### 缓存键设计原则
1. **必须包含**:
   - `Package.resolved` 哈希（Swift 依赖版本）
   - 操作系统标识 `${{ runner.os }}`

2. **可选包含**:
   - Swift 源文件哈希（触发重建）
   - Xcode 版本（如果会变化）

3. **缓存失效策略**:
   - 使用 `restore-keys` 提供回退匹配
   - 缓存大小限制：单个缓存 10GB，仓库总计 10GB

### 并行测试的前提条件
- ✅ 测试间无共享状态（已确认，每个测试套件独立）
- ✅ 测试不依赖执行顺序
- ⚠️ 需要确保 artifacts 正确共享给测试 job

### 现有保护机制（不要破坏）
- Git credentials 清理（第 123-128 行）
- 符号链接安全检查（`assert_symlinks_contained`）
- 敏感文件检查（`assert_no_sensitive_artifacts`）
- Full-tree 验证（main 分支推送必须完整验证）

---

## 验证清单

### 功能验证
- [ ] docs lane 仍然正常工作（5 分钟内完成）
- [ ] broker lane 仍然正常工作（5 分钟内完成）
- [ ] full lane 所有测试通过
- [ ] 缓存命中时构建时间显著减少
- [ ] 缓存未命中时构建仍然成功
- [ ] 并行测试全部通过且无竞态条件

### 安全验证
- [ ] 不缓存敏感信息（AISecrets.plist 等）
- [ ] Git credentials 仍然被正确清理
- [ ] 符号链接安全检查仍然生效
- [ ] 构建产物中无禁止文件（.gguf, .sqlite, .env.local 等）

### 性能验证
- [ ] 记录优化前基线时间（最近 10 次 CI 运行）
- [ ] 记录优化后时间（连续 10 次 CI 运行）
- [ ] 计算实际节省时间和百分比
- [ ] 监控缓存命中率（目标 >70%）

---

## 可能遇到的问题及解决方案

### 问题 1: 缓存大小超限
**症状**: actions/cache 警告缓存过大
**解决**: 排除 DerivedData 中的日志和索引文件

```yaml
path: |
  .codex-local/native-verification/swift-core/cache
  !.codex-local/native-verification/swift-core/cache/**/Logs
```

### 问题 2: 并行测试失败
**症状**: 单独运行通过，并行运行失败
**解决**: 检查共享资源（如模拟器、端口、临时文件）

### 问题 3: 缓存恢复后构建失败
**症状**: 缓存恢复后编译错误
**解决**: 添加更精确的缓存键，包含编译器版本

```yaml
key: ${{ runner.os }}-xcode-${{ steps.xcode-version.outputs.version }}-${{ hashFiles(...) }}
```

### 问题 4: aggregate job 逻辑不匹配
**症状**: 优化后 aggregate job 报错
**解决**: 同步更新 aggregate job 的 needs 和验证逻辑

---

## 关键文件清单

### 需要修改的文件
1. `.github/workflows/native-verification.yml` (454 行) - 主要修改
2. `tools/native-verification-classifier.sh` (215 行) - 可选，优先级 2
3. `tools/verify-native.sh` (531 行) - 可能需要小幅调整

### 需要参考的文件
1. `ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj/project.pbxproj`
2. `swift-core/Package.swift`
3. `Package.resolved` (如果存在)

### 测试验证文件
1. `.github/ISSUE_TEMPLATE/bug.yml` - 了解项目 issue 模板
2. 历史 CI 运行记录 - Actions 页面

---

## 命令速查

### 本地测试缓存路径
```bash
cd "<PROJECT_ROOT>"

# 检查当前 verification root 设置
grep -n "VERIFY_NATIVE_ROOT" tools/verify-native.sh

# 手动清理本地缓存（测试缓存失效场景）
rm -rf .codex-local/native-verification/swift-core/cache
rm -rf .codex-local/native-verification/source-packages
```

### GitHub CLI 命令
```bash
# 查看最近的 CI 运行
gh run list --workflow=native-verification.yml --limit 10

# 查看特定运行的详情
gh run view <run-id>

# 下载运行日志
gh run download <run-id>

# 更新 issue
gh issue edit 64 --add-label "state:in-progress"
```

### 测试 classifier 脚本
```bash
cd "<PROJECT_ROOT>"

# 模拟 PR 变更分类
bash tools/native-verification-classifier.sh \
  --base <base-commit-sha> \
  --head <head-commit-sha> \
  --event pull_request \
  --ref refs/pull/64/merge \
  --forced false
```

---

## 成功标准

### 量化指标
- **主要目标**: Full lane 平均运行时间从 60 分钟降至 **30 分钟以下**
- **缓存命中率**: 连续推送时 >70%
- **稳定性**: 连续 20 次 CI 运行成功率 >95%

### 质量指标
- 所有现有测试通过
- 不引入新的安全风险
- 不降低验证覆盖率
- 代码审查通过

---

## 接力清单

### 移交给 Sonnet 5 的任务
- [x] 完整的问题背景和上下文
- [x] 详细的优化方案和代码示例
- [x] 分阶段的实施路线图
- [x] 验证清单和成功标准
- [x] 常见问题和解决方案
- [x] 关键命令和文件路径

### 开始前的准备
1. 阅读本文档全文（约 15 分钟）
2. 浏览 issue #64: https://github.com/Gavin8233841/medcue-ios/issues/64
3. 检查本地仓库状态：`cd "<PROJECT_ROOT>" && git status`
4. 查看最近 5 次 CI 运行记录，建立基线
5. 确认 GitHub CLI 认证状态：`gh auth status`

### 建议的首次任务
**从优先级 1 的第一个任务开始**：实现 Swift Package Manager 缓存

1. 创建功能分支：`git checkout -b optimize-ci-caching`
2. 备份原文件：`cp .github/workflows/native-verification.yml .github/workflows/native-verification.yml.backup`
3. 在 full job 中添加 SPM 缓存步骤（见 1.1 章节）
4. 提交并推送：触发 CI 验证
5. 观察 Actions 运行日志，确认缓存创建和恢复

---

**文档版本**: v1.0
**创建时间**: 2026-08-24
**创建者**: Claude Opus 5 (Background Job)
**目标执行者**: Claude Sonnet 5

祝顺利！如有疑问，请参考本文档或查阅项目原始文件。