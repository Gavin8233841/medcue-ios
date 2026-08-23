# Codex Full Skill And Plugin Recovery Prompt

> 历史恢复材料：其中版本、路径和插件清单可能已经变化。执行任何安装或工作区外
> 修改前，必须先读取当前工具帮助、核对精确路径并取得相应授权。当前 Xcode 与
> 工作区边界见 `TOOLING_AND_PLUGIN_PLAN.md`。

用途：重启 Codex、插件列表丢失、skills 没暴露、或者新线程没有当前对话历史时，把下面提示词复制给 Codex，让它快速恢复本机 Codex 的竞赛工程能力集。

## 当前项目约定

- Stitch 已在 2026-06-10 被用户明确弃用。
- 恢复插件和检查可用性时，不再把 Stitch、Stitch MCP Local、`stitch-skills`、Google Cloud token、`gcloud` 作为目标或阻塞项。
- Xcode 项目、构建和 Simulator 使用 `/Applications/Xcode.app` 内 Xcode 27 Beta 5 自带的原生 MCP；旧 Build iOS Apps/XcodeBuildMCP 已卸载，不恢复、不调用。
- 如果本机仍残留 Stitch 配置、插件缓存或 skills，可以保留；不要为了 Stitch 继续排障、重装或要求用户补充认证。

## 复制给 Codex 的提示词

```text
请在当前项目中恢复并验证 Codex 的全部竞赛工程 skills 和插件。不要删除、清理、归档、重置任何文件或线程历史。不要执行 rm -rf、git clean、git reset --hard、git checkout -- . 或任何递归/通配符删除。不要把 $HOME/.codex/config.toml 改成只读。

项目路径：
/Users/Admin/Developer/MedCue/appcontest-2026-prep

目标：
1. 恢复并验证 Codex 插件：ShipSwift、Product Design、GitHub、Google Drive、Figma、Gmail、Browser、Computer Use、Documents、Spreadsheets、Presentations、LaTeX、Expo；Xcode 使用原生 MCP。
2. 恢复并验证 GitHub skills：mattpocock/skills 的 10 个竞赛工程推进技能、GSAP skills、Understand Anything skills。
3. 恢复并验证本地 skill：software-cup-a3-web-stack。
4. 所有安装动作都先检查目标目录是否已存在；已存在就只验证，不覆盖。
5. 最后汇报哪些插件和 skills 已可见、哪些需要重启或新线程刷新。
6. Stitch 已弃用，不要恢复、修复或验证 Stitch 相关插件和 MCP。

先运行：

cd /Users/Admin/Developer/MedCue/appcontest-2026-prep
which codex
codex plugin --help
codex plugin marketplace list
codex plugin list

恢复插件 marketplace：

codex plugin marketplace add $HOME/.codex/.tmp/bundled-marketplaces/openai-bundled || true
codex plugin marketplace add $HOME/.cache/codex-runtimes/codex-primary-runtime/plugins/openai-primary-runtime || true
codex plugin marketplace add $HOME/.codex/.tmp/marketplaces/role-specific-plugins || true

恢复插件：

codex plugin add browser@openai-bundled || true
codex plugin add computer-use@openai-bundled || true
codex plugin add latex@openai-bundled || true
codex plugin add documents@openai-primary-runtime || true
codex plugin add spreadsheets@openai-primary-runtime || true
codex plugin add presentations@openai-primary-runtime || true
codex plugin add shipswift@personal || true
codex plugin add product-design@personal || true
codex plugin add product-design@role-specific-plugins || true
codex plugin add github@openai-curated || true
codex plugin add google-drive@openai-curated || true
codex plugin add figma@openai-curated || true
codex plugin add gmail@openai-curated || true
codex plugin add expo@openai-curated || true

验证插件必须显示 installed, enabled：

codex plugin list | rg 'shipswift|product-design|github|google-drive|figma|gmail|browser|computer-use|documents|spreadsheets|presentations|latex|expo'
rg -n 'shipswift|product-design|github|google-drive|figma|gmail|documents|spreadsheets|presentations|expo' $HOME/.codex/config.toml

恢复 mattpocock/skills 的 10 个竞赛工程推进技能。先检查这些目录：

ls -ld \
  $HOME/.codex/skills/diagnose \
  $HOME/.codex/skills/grill-with-docs \
  $HOME/.codex/skills/improve-codebase-architecture \
  $HOME/.codex/skills/prototype \
  $HOME/.codex/skills/tdd \
  $HOME/.codex/skills/to-issues \
  $HOME/.codex/skills/to-prd \
  $HOME/.codex/skills/teach \
  $HOME/.codex/skills/handoff \
  $HOME/.codex/skills/grill-me

如果上述任一目录缺失，使用 Codex 自带安装器从精确 GitHub 路径安装。不要覆盖已存在目录：

python3 $HOME/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo mattpocock/skills \
  --path \
    skills/engineering/diagnose \
    skills/engineering/grill-with-docs \
    skills/engineering/improve-codebase-architecture \
    skills/engineering/prototype \
    skills/engineering/tdd \
    skills/engineering/to-issues \
    skills/engineering/to-prd \
    skills/productivity/teach \
    skills/productivity/handoff \
    skills/productivity/grill-me \
  --dest $HOME/.codex/skills

恢复 GSAP skills。先检查这些目录；缺失时再安装：

ls -ld \
  $HOME/.codex/skills/gsap-core \
  $HOME/.codex/skills/gsap-timeline \
  $HOME/.codex/skills/gsap-scrolltrigger \
  $HOME/.codex/skills/gsap-plugins \
  $HOME/.codex/skills/gsap-utils \
  $HOME/.codex/skills/gsap-react \
  $HOME/.codex/skills/gsap-performance \
  $HOME/.codex/skills/gsap-frameworks

如果缺失，安装：

python3 $HOME/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo greensock/gsap-skills \
  --path \
    skills/gsap-core \
    skills/gsap-timeline \
    skills/gsap-scrolltrigger \
    skills/gsap-plugins \
    skills/gsap-utils \
    skills/gsap-react \
    skills/gsap-performance \
    skills/gsap-frameworks \
  --dest $HOME/.codex/skills

恢复 Understand Anything skills。GitHub 仓库为 Egonex-AI/Understand-Anything，skill 路径在 understand-anything-plugin/skills。先检查：

ls -ld \
  $HOME/.codex/skills/understand \
  $HOME/.codex/skills/understand-chat \
  $HOME/.codex/skills/understand-dashboard \
  $HOME/.codex/skills/understand-diff \
  $HOME/.codex/skills/understand-domain \
  $HOME/.codex/skills/understand-explain \
  $HOME/.codex/skills/understand-knowledge \
  $HOME/.codex/skills/understand-onboard

如果缺失，安装：

python3 $HOME/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo Egonex-AI/Understand-Anything \
  --path \
    understand-anything-plugin/skills/understand \
    understand-anything-plugin/skills/understand-chat \
    understand-anything-plugin/skills/understand-dashboard \
    understand-anything-plugin/skills/understand-diff \
    understand-anything-plugin/skills/understand-domain \
    understand-anything-plugin/skills/understand-explain \
    understand-anything-plugin/skills/understand-knowledge \
    understand-anything-plugin/skills/understand-onboard \
  --dest $HOME/.codex/skills

恢复 ShipSwift 本地辅助 skills。先检查：

ls -ld \
  $HOME/.codex/skills/add-component \
  $HOME/.codex/skills/build-feature \
  $HOME/.codex/skills/explore-recipes

如果缺失，从 ShipSwift 插件缓存或源目录定点复制，不覆盖已存在目录。优先使用：

$HOME/.codex/plugins/cache/personal/shipswift/1.0.2/skills

其次使用：

$HOME/plugins/shipswift/skills

恢复本地 A3 skill。先检查：

test -f $HOME/.codex/skills/software-cup-a3-web-stack/SKILL.md
test -f $HOME/.codex/skills/software-cup-a3-web-stack/references/resources.md

如果缺失，从项目备份恢复：

/Users/Admin/Developer/MedCue/appcontest-2026-prep/docs/codex-local-skills/software-cup-a3-web-stack/SKILL.md
/Users/Admin/Developer/MedCue/appcontest-2026-prep/docs/codex-local-skills/software-cup-a3-web-stack/references/resources.md

验证所有本地 skills：

find $HOME/.codex/skills -maxdepth 2 -name SKILL.md -type f -print | sort
rg -n '^name:|^description:' \
  $HOME/.codex/skills/diagnose/SKILL.md \
  $HOME/.codex/skills/grill-with-docs/SKILL.md \
  $HOME/.codex/skills/improve-codebase-architecture/SKILL.md \
  $HOME/.codex/skills/prototype/SKILL.md \
  $HOME/.codex/skills/tdd/SKILL.md \
  $HOME/.codex/skills/to-issues/SKILL.md \
  $HOME/.codex/skills/to-prd/SKILL.md \
  $HOME/.codex/skills/teach/SKILL.md \
  $HOME/.codex/skills/handoff/SKILL.md \
  $HOME/.codex/skills/grill-me/SKILL.md \
  $HOME/.codex/skills/software-cup-a3-web-stack/SKILL.md

验证插件 skills 数量：

find $HOME/.codex/plugins/cache/personal/shipswift -maxdepth 5 -type f -name SKILL.md -print
find $HOME/.codex/plugins/cache/personal/product-design -maxdepth 5 -type f -name SKILL.md -print
验证其他 MCP 和 prompt 暴露：

codex mcp list
codex mcp list | rg -v 'xcodebuildmcp'
codex debug prompt-input '验证插件和技能恢复' > [HISTORICAL_TEMP_PATH_REDACTED]
rg -n 'ShipSwift|Product Design|GitHub|Google Drive|Documents|Spreadsheets|Presentations|software-cup-a3-web-stack|diagnose|tdd|prototype|understand|gsap' [HISTORICAL_TEMP_PATH_REDACTED]

最后汇报：
1. 哪些插件 installed, enabled。
2. mattpocock 10 个 skills 是否都有 SKILL.md。
3. GSAP 和 Understand Anything skills 是否都有 SKILL.md。
4. software-cup-a3-web-stack 是否恢复。
5. ShipSwift recipe MCP 是否可见；如果当前线程看不到但配置已恢复，说明当前线程没有热加载，需要重启 Codex 或开新线程。
6. Xcode 27 beta 原生 MCP 是否可用；如果当前线程仍显示旧 xcodebuildmcp，只说明工具表尚未刷新，不要调用它。
7. Stitch 已弃用，明确说明本次未把 Stitch 作为恢复或修复目标。
8. 明确说明没有删除、归档、重置或破坏任何对话历史。
```

## 当前已确认的能力集快照

插件已启用：

- `shipswift@personal`
- `product-design@personal`
- `product-design@role-specific-plugins`
- `github@openai-curated`
- `google-drive@openai-curated`
- `figma@openai-curated`
- `gmail@openai-curated`
- `browser@openai-bundled`
- `computer-use@openai-bundled`
- `documents@openai-primary-runtime`
- `spreadsheets@openai-primary-runtime`
- `presentations@openai-primary-runtime`
- `latex@openai-bundled`
- `expo@openai-curated`

Xcode 工具当前约定：

- 旧 Build iOS Apps/XcodeBuildMCP 已卸载，不恢复、不调用。
- 使用 `/Applications/Xcode.app` 内 Xcode 27 Beta 5 自带原生 MCP；外部 Agent 开关需在 Xcode Settings > Intelligence 中保持 `Always`。
- `xcode-select` 已指向 `/Applications/Xcode.app/Contents/Developer`；命令行 fallback 直接使用当前选中的 Xcode，不写死旧下载路径。
- 如果旧线程仍显示 `mcp__xcodebuildmcp`，视为尚未刷新的旧工具表；重启或新开线程后不应再出现，不要调用旧工具。

Stitch 状态：

- 用户已在 2026-06-10 明确弃用 Stitch。
- 后续恢复插件时不需要恢复、验证或修复 Stitch、Stitch MCP Local、`stitch-skills`、Google Cloud token 或 `gcloud`。
- 若本机仍保留 Stitch 相关配置或缓存，可以原样保留；它们不再是本项目的可用性要求。

本地 `~/.codex/skills` 已确认：

- `diagnose`
- `grill-with-docs`
- `improve-codebase-architecture`
- `prototype`
- `tdd`
- `to-issues`
- `to-prd`
- `teach`
- `handoff`
- `grill-me`
- `software-cup-a3-web-stack`
- `add-component`
- `build-feature`
- `explore-recipes`
- `gsap-core`
- `gsap-timeline`
- `gsap-scrolltrigger`
- `gsap-plugins`
- `gsap-utils`
- `gsap-react`
- `gsap-performance`
- `gsap-frameworks`
- `understand`
- `understand-chat`
- `understand-dashboard`
- `understand-diff`
- `understand-domain`
- `understand-explain`
- `understand-knowledge`
- `understand-onboard`

## 重要提醒

- 已打开的旧线程通常不会热刷新刚安装的插件和 skills。
- `codex plugin list` 显示 `installed, enabled` 代表配置层已恢复。
- 新线程、重启 Codex、或同目录分叉后更容易拿到最新插件和 skills 列表。
- 不要把 `$HOME/.codex/config.toml` 改成只读。Codex App 需要写入插件和运行时状态，只读会增加插件再次丢失的风险。
