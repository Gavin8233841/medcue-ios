# Pre-Commit Syntax Checks

## 概述

本仓库使用双层语法审查系统，在代码提交到 CI 之前捕获常见错误：

- **方案1（本地）**：Git pre-commit hook，在 `git commit` 时自动运行（0.5秒）
- **方案3（云端）**：GitHub Actions quick-syntax job，在 CI 开始时快速检查（30秒）

## 快速开始

### 安装本地 Hook

```bash
cd <PROJECT_ROOT>
bash tools/install-hooks.sh
```

安装后，每次 `git commit` 会自动运行检查。

### 手动运行检查

```bash
# 在提交前手动测试
bash tools/run-pre-commit-checks.sh
```

## 当前检查项

| 检查项 | 说明 | 修复方法 |
|--------|------|----------|
| Trailing Whitespace | 行尾空格 | `git diff --cached --name-only \| xargs sed -i 's/[ \\t]*$//'` |
| Absolute Paths | 绝对路径（系统特定路径） | 替换为 `<PROJECT_ROOT>` |
| Allowlist Paths | 文件必须在允许的目录 | 移到 `docs/` 或添加到 `.gitignore` |
| JavaScript Syntax | JS 语法错误 | 修复语法错误 |
| JSON Syntax | JSON 格式错误 | 修复 JSON 格式 |

## 跨平台支持

脚本支持以下平台：
- ✅ Windows (Git Bash / MSYS2 / Cygwin)
- ✅ macOS
- ✅ Linux

## 绕过检查（不推荐）

```bash
git commit --no-verify
```

**注意**：绕过本地检查后，云端 quick-syntax job 仍会拦截错误。

## 添加新检查

当 CI 出现新的语法错误时，可以快速添加到本地审查：

```bash
# 示例：添加密钥检查
bash tools/add-check.sh \
  "secret-keys" \
  "Secret Keys" \
  "sk-[A-Za-z0-9]{20,}" \
  "Remove API keys from code"
```

然后手动更新 `tools/run-pre-commit-checks.sh` 实现该检查逻辑。

## 架构

```
开发者提交流程：
┌─────────────┐     ┌──────────────────┐     ┌─────────────┐     ┌────────────────┐
│ git commit  │ --> │ Pre-commit Hook  │ --> │  git push   │ --> │ Quick Syntax   │
│             │     │ (本地 0.5s)      │     │             │     │ (云端 30s)     │
└─────────────┘     └──────────────────┘     └─────────────┘     └────────────────┘
                           ↓ 失败                                       ↓ 失败
                    ❌ 阻止提交                                   ❌ 快速失败 PR
                    立即修复，无损耗                              避免 40 分钟 full lane
```

## 文件说明

- `tools/pre-commit-checks.json` - 检查规则配置（可扩展）
- `tools/run-pre-commit-checks.sh` - 核心检查脚本
- `tools/install-hooks.sh` - Hook 安装脚本
- `tools/add-check.sh` - 添加新检查的工具
- `.github/workflows/native-verification.yml` - 包含 quick-syntax job

## 故障排除

### Hook 未运行

```bash
# 重新安装
bash tools/install-hooks.sh

# 检查 hook 是否可执行
ls -la .git/hooks/pre-commit
```

### Windows 上 sed 命令失败

Git Bash 自带 sed，如果失败：
1. 确认使用 Git Bash（不是 PowerShell 或 CMD）
2. 或手动删除行尾空格

### Python/Node.js 检查被跳过

某些检查需要：
- Node.js (JavaScript/JSON 语法检查)
- Python 3 (配置管理)

如果未安装，相关检查会被跳过（不影响其他检查）。

## 维护

### 更新检查规则

1. 编辑 `tools/pre-commit-checks.json`
2. 更新 `tools/run-pre-commit-checks.sh` 实现逻辑
3. 更新 `.github/workflows/native-verification.yml` 中的 quick-syntax job
4. 提交更改

### 禁用某个检查

在 `tools/pre-commit-checks.json` 中设置 `"enabled": false`。

## CI 集成

GitHub Actions 的 `quick-syntax` job 在所有其他 job 之前运行：

```yaml
jobs:
  classify: ...

  quick-syntax:  # 快速语法检查（30秒）
    needs: classify
    runs-on: ubuntu-24.04
    timeout-minutes: 2
    # ... 运行相同的检查

  docs:
    needs: [classify, quick-syntax]  # 依赖 quick-syntax
    # ...
```

如果 quick-syntax 失败，后续所有 job 都会被跳过，节省 CI 时间。

## 效率收益

| 场景 | 无预检查 | 使用本系统 | 节省时间 |
|------|----------|------------|----------|
| 语法错误提交 | 40 分钟（full lane 失败） | 0.5 秒（本地拦截） | 99.98% |
| 绕过本地检查 | 40 分钟（full lane 失败） | 30 秒（云端拦截） | 98.75% |
| 正常提交 | 40 分钟（正常 CI） | 0.5s + 40 分钟 | 无影响 |

## 支持

如有问题，请联系项目维护者或查看：
- `.git/hooks/pre-commit` - 实际运行的 hook
- CI 日志中的 "Quick Syntax Gate" job
