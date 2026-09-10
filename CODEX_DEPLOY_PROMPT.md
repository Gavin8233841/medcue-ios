# Codex 部署提示词：Pre-Commit 语法审查系统

请帮我在本地仓库部署 Pre-Commit 语法审查系统。

## 背景

项目已经建立了双层 CI 前语法审查流程：
- **本地层**：Git pre-commit hook（0.5秒，自动运行）
- **云端层**：GitHub Actions quick-syntax job（30秒，强制检查）

目的是在代码提交到 CI 之前捕获常见语法错误，避免浪费 40 分钟的 CI 时间。

## 部署任务

### 1. 拉取最新代码

确保本地仓库是最新的：
```bash
git pull origin main
```

### 2. 安装 Pre-commit Hook

运行安装脚本：
```bash
bash tools/install-hooks.sh
```

### 3. 验证安装

测试 hook 是否正常工作：
```bash
# 创建一个带行尾空格的测试文件
echo "test content " > test-trailing.txt
git add test-trailing.txt

# 尝试提交（应该被拦截）
git commit -m "test"

# 清理测试文件
git reset HEAD test-trailing.txt
rm test-trailing.txt
```

如果看到类似以下错误，说明安装成功：
```
❌ Found trailing whitespace
Fix with: git diff --cached --name-only | xargs sed -i 's/[ \t]*$//'
```

## 检查内容

系统会在每次 `git commit` 前自动检查：

1. **行尾空格** - 使用 `git diff --check`
2. **绝对路径** - 禁止 Windows/Unix 系统绝对路径
3. **文件路径白名单** - 只允许提交特定目录的文件
4. **JavaScript 语法** - 自动检查 `.js` 文件
5. **JSON 格式** - 自动检查 `.json` 文件

## 关键文件

- `tools/install-hooks.sh` - Hook 安装脚本
- `tools/run-pre-commit-checks.sh` - 核心检查脚本
- `tools/pre-commit-checks.json` - 检查规则配置
- `.git/hooks/pre-commit` - 安装后生成的 hook 文件
- `docs/pre-commit-checks.md` - 完整文档
- `docs/collaborator-setup-prompt.md` - 详细部署指南

## 常见问题处理

### 问题1：发现行尾空格
**自动修复**：
```bash
git diff --cached --name-only | xargs sed -i 's/[ \t]*$//'
git add .
git commit -m "message"
```

### 问题2：发现绝对路径
**手动修复**：将文件中的系统绝对路径替换为 `<PROJECT_ROOT>`

### 问题3：文件不在白名单
**解决方法**：
- 移动到 `docs/` 目录，或
- 添加到 `.gitignore`（如果是临时文件）

## 跨平台兼容性

脚本支持：
- ✅ Windows (Git Bash)
- ✅ macOS
- ✅ Linux

## 预期结果

部署成功后：
- 每次 `git commit` 自动运行检查（0.5秒）
- 有问题时显示错误和修复建议
- 通过检查后才能提交
- 可以用 `git commit --no-verify` 绕过（不推荐）

## 验证清单

请确认以下内容：
- [ ] `.git/hooks/pre-commit` 文件存在且可执行
- [ ] 测试提交时 hook 正常运行
- [ ] 能看到彩色输出和清晰的错误提示
- [ ] 修复错误后可以正常提交

完成部署后，你的开发流程将自动获得语法检查保护，避免 CI 失败浪费时间。
