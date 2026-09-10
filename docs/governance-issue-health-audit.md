# GitHub Issue Health Audit Tool

## 概述

`tools/audit-issue-health.sh` 是一个只读的 GitHub Issue 健康度审计工具，用于评估仓库的 Issue 治理状态。

## 功能

- ✅ 标签覆盖率分析（总体、优先级、类型）
- ✅ 标题前缀模式统计
- ✅ 负责人分配情况
- ✅ Milestone 覆盖率
- ✅ 阻塞 Issue 依赖分析
- ✅ PR-Issue 关联检查（自动关闭 vs 普通引用）

## 使用方法

### 基本用法

```bash
# 审计默认仓库（Gavin8233841/medcue-ios）
bash tools/audit-issue-health.sh

# 审计指定仓库
bash tools/audit-issue-health.sh owner/repo

# 指定输出文件
bash tools/audit-issue-health.sh owner/repo my-audit-report.md
```

### Windows 兼容性

工具完全支持 Windows 环境：
- 使用 Git Bash 运行
- 需要安装 GitHub CLI (`gh`)
- 需要 Python 3

### 前置条件

1. **GitHub CLI**
   ```bash
   # 安装（Windows）
   # 下载：https://cli.github.com/

   # 验证
   gh --version
   ```

2. **GitHub 认证**
   ```bash
   gh auth login
   gh auth status
   ```

3. **Python 3**
   ```bash
   python3 --version
   ```

## 输出示例

报告包含以下部分：

### 1. Executive Summary
- 总 Issue 数
- 各项覆盖率（标签、优先级、类型、负责人、Milestone）
- 阻塞 Issue 数量
- 无标签/无负责人 Issue 数量

### 2. 标签分析
- 标签覆盖率详细统计
- 优先级标签（P0/P1/P2/P3）覆盖率
- 类型标签覆盖率
- 无标签 Issue 列表

### 3. 标题前缀分析
- 前缀模式分布（【P1】、[Feature] 等）
- 每种前缀的 Issue 数量和编号

### 4. 负责人分析
- 分配覆盖率
- 未分配 Issue 列表

### 5. Milestone 分析
- Milestone 覆盖率
- 各 Milestone 的 Issue 数量
- 未纳入 Milestone 的 Issue

### 6. 阻塞 Issue 分析
- 带「已阻塞」标签的 Issue
- 从 Issue body 解析的依赖关系
- 潜在的陈旧依赖

### 7. PR-Issue 关联分析
- 最近 10 个已合并 PR
- 自动关闭语义（Closes/Fixes/Resolves）
- 普通引用语义（Refs/Supports/Related）
- 无 Issue 引用的 PR

## 测试

工具包含完整的单元测试套件：

```bash
# 运行测试
python3 tools/test-audit-issue-health.py

# 测试覆盖
# - 标签覆盖率计算
# - 无标签 Issue 识别
# - 优先级标签检测
# - 负责人覆盖率
# - Milestone 覆盖率
# - 阻塞 Issue 检测
# - PR 关键词识别
# - 标题前缀提取
# - 依赖关系解析
# - 边界情况（空数据集等）
```

## 安全性

- **只读操作**：不修改任何 GitHub 状态
- **无副作用**：不创建、修改、关闭或评论 Issue
- **数据隐私**：不读取或保存健康信息、密钥或私有数据
- **认证边界**：使用 GitHub CLI 的认证机制
- **失败关闭**：网络、权限或解析失败时报告错误

## 数据限制

报告中明确说明的限制：
- Issue Form 字段完整性需要人工审查模板
- 阻塞时长无法通过 API 获取（需要 webhook/action）
- 循环依赖检测基于模式，未进行图验证
- 数据来源为 GitHub API，可能存在分页限制

## 维护

### 添加新的审计维度

编辑 `tools/audit-issue-health.sh`，在 Python 脚本部分添加：

```python
# 新的分析逻辑
new_metric = ...

# 输出到报告
print("---\n")
print("## New Metric\n")
print(f"Result: {new_metric}")
```

### 更新测试

编辑 `tools/test-audit-issue-health.py`，添加新测试：

```python
def test_new_metric(self):
    """Test new metric calculation"""
    result = calculate_new_metric(self.sample_issues)
    self.assertEqual(result, expected_value)
```

## 集成到 CI

虽然当前版本为手动运行工具，但可以集成到 CI：

```yaml
# .github/workflows/issue-health.yml
name: Issue Health Check
on:
  schedule:
    - cron: '0 0 * * 1'  # 每周一
jobs:
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - name: Run audit
        env:
          GH_TOKEN: ${{ github.token }}
        run: bash tools/audit-issue-health.sh
```

## 故障排除

### GitHub CLI 未认证
```bash
gh auth login
```

### Python 不可用
确保 Python 3 已安装：
```bash
python3 --version
# 或在 Windows 上
python --version
```

### 权限错误
确保有仓库读取权限：
```bash
gh auth status
```

## 示例输出

```markdown
# GitHub Issue Health Audit Report

**Generated**: 2026-08-25 10:00:00 UTC
**Repository**: Gavin8233841/medcue-ios

## Executive Summary

- **Total Open Issues**: 30
- **Label Coverage**: 83.3% (25/30)
- **Priority Label Coverage**: 70.0% (21/30)
- **Assignee Coverage**: 30.0% (9/30)
- **Blocked Issues**: 8

## 1. Label Analysis

### Issues Without Any Labels
- #51: Security/Broker enhancement
- #52: Quality test coverage
- #55: Accessibility verification
...

## Recommendations
1. Add labels to 5 unlabeled issues
2. Assign 21 unassigned issues
3. Review 8 blocked issues for stale dependencies
```

## 相关 Issue

- Issue #61: 建立可复核的 GitHub Issue 健康度审计

## 作者

- yzy1020

## 许可

遵循 medcue-ios 仓库许可
