# 协作者部署提示词 - Pre-Commit 语法审查系统

## 🎯 任务目标

在你的本地仓库中部署 Pre-Commit 语法审查系统，防止 CI 因语法错误而浪费时间。

## 📋 部署步骤

### 1. 拉取最新代码

```bash
cd <PROJECT_ROOT>
git pull origin main
```

### 2. 安装 Pre-commit Hook

运行以下命令安装本地检查 hook：

```bash
bash tools/install-hooks.sh
```

你应该看到类似输出：
```
📦 Installing pre-commit hook...
✅ Pre-commit hook installed successfully
🎉 Setup complete!
```

### 3. 验证安装

测试 hook 是否正常工作：

```bash
# 创建一个测试文件（带行尾空格）
echo "test content " > test-file.txt
git add test-file.txt
git commit -m "test"
```

应该会看到错误提示：
```
❌ Found trailing whitespace
Fix with: git diff --cached --name-only | xargs sed -i 's/[ \t]*$//'
```

然后清理测试文件：
```bash
git reset HEAD test-file.txt
rm test-file.txt
```

### 4. 完成

从现在开始，每次 `git commit` 都会自动运行语法检查。

## 🔍 系统说明

### 检查内容

系统会自动检查以下问题（每次 commit 前）：

1. **行尾空格** - CI 必检项
2. **绝对路径** - 禁止 `C:\`, `D:\`, `/Users/`, `/home/` 等
3. **文件路径白名单** - 只能提交允许目录的文件
4. **JavaScript 语法** - 自动检查 `.js` 文件
5. **JSON 格式** - 自动检查 `.json` 文件

### 运行时机

- **自动运行**：每次 `git commit` 时
- **手动运行**：`bash tools/run-pre-commit-checks.sh`
- **绕过检查**：`git commit --no-verify`（不推荐）

### 时间开销

- ✅ 本地检查：**0.5 秒**（几乎无感知）
- ✅ 云端安全网：**30 秒**（后台运行）
- ❌ 不使用系统：**40 分钟**（CI 失败重跑）

## 🛠️ 常见场景

### 场景1：发现行尾空格

```bash
❌ Found trailing whitespace
Fix with: git diff --cached --name-only | xargs sed -i 's/[ \t]*$//'
```

**解决方法**：
```bash
# 自动修复所有暂存文件的行尾空格
git diff --cached --name-only | xargs sed -i 's/[ \t]*$//'

# 重新提交
git add .
git commit -m "your message"
```

### 场景2：发现绝对路径

```bash
❌ Found absolute local paths (C:\, D:\, /Users/, /home/)
Replace with <PROJECT_ROOT> placeholder
```

**解决方法**：
手动打开文件，将绝对路径替换为 `<PROJECT_ROOT>`。

例如：
```diff
- cd D:\桌面\medcue\medcue-ios
+ cd <PROJECT_ROOT>
```

### 场景3：文件不在白名单

```bash
❌ File not in allowlist: .claude/plans/my-plan.md
Hint: Work files should be in docs/ or added to .gitignore
```

**解决方法**：
```bash
# 选项1：移动到 docs/
git mv .claude/plans/my-plan.md docs/my-plan.md

# 选项2：添加到 .gitignore（如果是临时文件）
echo ".claude/plans/" >> .gitignore
git reset HEAD .claude/plans/my-plan.md
```

### 场景4：JavaScript/JSON 语法错误

```bash
❌ JavaScript syntax error in: cloudfunctions/medcue-ai-broker/index.js
```

**解决方法**：
根据错误提示修复代码语法错误。

## 🌍 跨平台兼容性

系统支持：
- ✅ **Windows** - Git Bash / MSYS2 / Cygwin
- ✅ **macOS** - 原生 Terminal / iTerm2
- ✅ **Linux** - 所有主流发行版

## ⚙️ 高级功能

### 查看配置

检查规则配置文件：
```bash
cat tools/pre-commit-checks.json
```

### 临时禁用检查

如果确实需要绕过检查（极少数情况）：
```bash
git commit --no-verify -m "message"
```

**注意**：云端 GitHub Actions 仍会检查，只是延迟到推送后。

### 重新安装 Hook

如果 hook 被意外删除：
```bash
bash tools/install-hooks.sh
```

## 🔄 CI 集成说明

本系统与 CI 的关系：

```
你的提交流程：
1. git commit → 本地 hook 检查（0.5秒）→ 通过
2. git push → GitHub Actions quick-syntax job（30秒）→ 通过
3. 然后才运行完整 CI（40分钟）

如果步骤1或2失败，你只浪费了几秒到30秒，而不是40分钟。
```

## 📚 详细文档

完整文档：`docs/pre-commit-checks.md`

## ❓ 故障排除

### Hook 没有运行

检查是否正确安装：
```bash
ls -la .git/hooks/pre-commit
cat .git/hooks/pre-commit
```

如果文件不存在或不可执行，重新运行：
```bash
bash tools/install-hooks.sh
```

### Windows 上 sed 命令失败

确保使用 **Git Bash**（不是 PowerShell 或 CMD）：
```bash
# 检查当前 shell
echo $SHELL
# 应该显示类似 /usr/bin/bash
```

### Python/Node.js 检查被跳过

如果系统提示某些检查被跳过，是因为缺少依赖：
- Node.js 检查需要安装 Node.js
- 配置管理需要 Python 3

这不影响核心检查（行尾空格、绝对路径、白名单）。

## 🤝 协作约定

团队所有成员都应：
1. ✅ 安装本地 hook
2. ✅ 不使用 `--no-verify` 绕过检查
3. ✅ 发现新的 CI 错误时，及时添加到检查规则

## 📞 获取帮助

如有问题：
1. 查看 `docs/pre-commit-checks.md`
2. 联系项目维护者
3. 查看 GitHub Actions 日志中的 "Quick Syntax Gate ⚡" job

---

**部署完成后请回复确认，确保系统正常工作。谢谢！**
