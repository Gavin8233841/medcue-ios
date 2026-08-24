# GitHub Issue 健康度审计工具

## 概述

`audit-github-issues.py` 是一个只读的 GitHub Issue 健康度审计工具，用于分析仓库的 Issue 管理状态。

**特性**：
- ✅ 只读操作，不修改任何 GitHub 远端状态
- ✅ Windows 兼容
- ✅ 生成结构化 Markdown 报告
- ✅ 默认失败关闭（网络/权限错误时明确报告）
- ✅ 包含独立测试 fixture

## 系统要求

- Python 3.7+
- [GitHub CLI (gh)](https://cli.github.com/) 已安装并认证
- 目标仓库的读取权限

## 安装

1. 安装 GitHub CLI：
   ```bash
   # Windows (使用 winget)
   winget install GitHub.cli
   
   # 或下载安装包
   # https://github.com/cli/cli/releases
   ```

2. 认证 GitHub CLI：
   ```bash
   gh auth login
   ```

3. 验证安装：
   ```bash
   gh auth status
   ```

## 使用方法

### 基本用法

```bash
python tools/audit-github-issues.py --repo owner/name
```

### 示例

```bash
# 审计 medcue-ios 仓库
python tools/audit-github-issues.py --repo Gavin8233841/medcue-ios

# 保存报告到文件
python tools/audit-github-issues.py --repo Gavin8233841/medcue-ios > audit-report.md
```

## 审计内容

工具会生成包含以下部分的报告：

### 1. 📋 标签覆盖率
- 任意标签覆盖率
- 优先级标签覆盖率（P0、P1、P2、P3、priority:*）
- 类型标签覆盖率（type:bug、type:feature 等）
- 无标签 Issues 列表

**重要**：工具会区分"有任意标签"和"分类完整"，后者需要同时有优先级和类型标签。

### 2. 📝 标题前缀分类
- 按标题前缀分组统计（如 [P1]、【P2】、Feature: 等）
- 列出每类的具体 Issue 编号

### 3. 👤 负责人覆盖率
- 已指派负责人的 Issues 比例
- 未指派负责人的 Issues 列表

**说明**："已阻塞"标签不是负责人机制的替代。

### 4. 🔗 最近 10 个已合并 PR 的 Issue 引用
- 按 GitHub 合并时间排序
- 区分自动关闭语义（Closes/Fixes/Resolves）和普通关联（Refs/Supports/Related）
- 标注是否有 Issue 引用

### 5. 🚧 阻塞依赖分析
- 统计带"已阻塞"（state:blocked）标签的 Issues
- 解析正文中的依赖关系
- 检测已关闭的依赖
- 检测循环依赖
- 标注未命名阻塞原因的 Issues

**限制**：无法从 API 获取"阻塞标签首次添加时间"，无法计算精确阻塞时长。

### 6. 🎯 Milestone 覆盖率
- 已纳入 Milestone 的 Issues 比例
- Milestone 分布统计
- 未纳入 Milestone 的 Issues 列表

## 认证边界

工具通过 `gh CLI` 调用 GitHub REST API，使用的认证范围取决于 `gh auth login` 时授予的权限。

**需要的最小权限**：
- `repo:read` - 读取仓库 Issues、PRs、标签、Milestones

**不需要的权限**：
- 写入权限（工具是只读的）
- 工作流权限
- 包权限

## 失败行为

工具采用"默认失败关闭"策略：

- **网络错误**：立即报告并退出（exit code 1）
- **权限错误**：立即报告并退出（exit code 1）
- **API 限流**：报告错误信息和限流状态
- **解析错误**：报告具体的解析失败位置
- **超时**：API 调用超时后报告并退出

**不会**生成看似完整但实际数据不完整的报告。

## 测试

工具包含独立的测试 fixture，不依赖在线 GitHub 状态：

```bash
# 运行测试
python tools/test-issue-audit.py
```

测试覆盖：
- 标签审计（包括优先级/类型区分）
- 标题前缀提取
- 负责人统计
- Issue 引用提取（区分自动关闭和普通关联）
- 阻塞依赖解析
- 循环依赖检测
- Milestone 统计
- API 错误处理

## 数据来源和限制

### 数据来源
- GitHub REST API v3
- 通过 `gh api` 命令调用
- 使用分页获取完整数据

### 已知限制

1. **阻塞时长**：无法从 API 获取标签添加时间，无法计算精确阻塞时长
2. **Issue Form 字段**：目前不解析 Issue Form 的具体字段（可在未来扩展）
3. **历史数据**：只分析当前状态，不分析历史变化趋势
4. **API 限流**：受 GitHub API 速率限制约束（认证用户：5000 请求/小时）
5. **大型仓库**：Issues 数量超过数百个时，API 调用可能较慢

### 数据准确性

报告生成时会标注：
- 生成时间（UTC）
- 查询范围（仓库名）
- Open Issues 总数

所有统计数据基于生成时刻的快照，不是实时数据。

## 脱敏规则

工具不会读取、输出或保存：
- 用药记录
- 健康信息
- 密钥或 token
- 设备标识符
- 私有路径
- 本地数据库内容

工具只处理 GitHub 公开 API 可访问的元数据：
- Issue 标题、编号、状态
- 标签名称
- 负责人用户名（公开信息）
- PR 标题和引用关系
- Milestone 名称

## 故障排查

### gh CLI 未认证
```
❌ 审计失败: gh CLI 未认证。请运行: gh auth login
```
**解决**：运行 `gh auth login` 并按提示完成认证。

### 权限不足
```
❌ 审计失败: API 调用失败 /repos/owner/name/issues: HTTP 404
```
**解决**：确认仓库名称正确，且你有读取权限。

### API 超时
```
❌ 审计失败: API 调用超时 /repos/owner/name/issues
```
**解决**：检查网络连接，或稍后重试。

### gh CLI 未安装
```
❌ 审计失败: gh CLI 未安装。请从 https://cli.github.com/ 安装
```
**解决**：安装 GitHub CLI。

## 示例输出

```markdown
# GitHub Issue 健康度审计报告

**生成时间**: 2026-08-24T10:00:00+00:00
**仓库**: Gavin8233841/medcue-ios
**Open Issues 总数**: 30

---

## 📋 标签覆盖率

- **任意标签覆盖率**: 25/30 (83.3%)
- **优先级标签覆盖率**: 20/30 (66.7%)
- **类型标签覆盖率**: 18/30 (60.0%)

**无标签 Issues** (5 个):
#51, #52, #55, #56, #57

**说明**: 优先级和类型标签是分类完整性的关键指标，"有任意标签"不等于"分类完整"。

---

## 👤 负责人覆盖率

- **已指派负责人**: 9/30 (30.0%)

**未指派负责人的 Issues** (21 个):
#1, #2, #3, #4, #5, ...

---
```

## 与 GitHub Actions 的关系

本工具是**独立的命令行工具**，不是 GitHub Action。

未来可以选择：
1. 保持为手动运行的审计工具
2. 集成到 GitHub Actions 定期运行
3. 添加为 PR 检查的一部分

这些决策应基于实际使用经验和重复性问题的频率。

## 开发和贡献

工具位于 `tools/audit-github-issues.py`，遵循项目的可信工具验证规范。

**修改工具时必须**：
1. 更新测试（`tools/test-issue-audit.py`）
2. 运行测试验证
3. 在真实仓库上运行验证输出
4. 更新本文档
5. 通过 exact-head CI 验证

## 许可和使用

本工具是 medcue-ios 项目的一部分，遵循项目的整体许可。

仅用于 GitHub Issue 治理和项目管理，不涉及医疗数据或用户隐私。
