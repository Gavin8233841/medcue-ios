# Codex 插件恢复提示词

用途：当 Codex App 插件列表丢失、旧线程看不到 Build iOS Apps / ShipSwift / Product Design / GitHub 等插件时，把下面提示词复制给当前 Codex 线程，用于快速恢复插件配置并保留对话历史。

```text
请在当前项目中快速恢复 Codex 插件，不要删除、清理、归档、重置任何文件或线程历史。

项目路径：
$HOME/Desktop/appcontest-2026-prep

目标：
1. 恢复 Codex App 插件列表。
2. 优先恢复 build-ios-apps。
3. 恢复 ShipSwift、Product Design、GitHub、Browser、Computer Use、办公三件套等插件。
4. 验证插件已安装、已启用、MCP/skills 已暴露。
5. 不要把 $HOME/.codex/config.toml 改成只读。之前只读会干扰 Codex App 同步，导致插件再次消失。
6. 不要新建线程、归档线程或丢弃当前对话历史。若当前旧线程无法热加载插件，只说明需要重新开一轮或同目录分叉，不要主动破坏历史。

请依次执行并检查：

cd $HOME/Desktop/appcontest-2026-prep

codex plugin marketplace add $HOME/.codex/.tmp/bundled-marketplaces/openai-bundled
codex plugin marketplace add $HOME/.cache/codex-runtimes/codex-primary-runtime/plugins/openai-primary-runtime
codex plugin marketplace add $HOME/.codex/.tmp/marketplaces/role-specific-plugins

codex plugin add browser@openai-bundled
codex plugin add computer-use@openai-bundled
codex plugin add build-ios-apps@openai-curated
codex plugin add shipswift@personal
codex plugin add product-design@personal
codex plugin add product-design@role-specific-plugins
codex plugin add github@openai-curated
codex plugin add latex@openai-bundled
codex plugin add documents@openai-primary-runtime
codex plugin add spreadsheets@openai-primary-runtime
codex plugin add presentations@openai-primary-runtime
codex plugin add google-drive@openai-curated
codex plugin add figma@openai-curated
codex plugin add gmail@openai-curated
codex plugin add expo@openai-curated

然后验证：

codex plugin list
codex mcp list
codex debug prompt-input '验证插件恢复'

必须确认：
- build-ios-apps@openai-curated 显示 installed, enabled
- shipswift@personal 显示 installed, enabled
- product-design、github、browser、computer-use、documents、spreadsheets、presentations 均显示 installed, enabled
- codex mcp list 中有 xcodebuildmcp、shipswift、computer-use、node_repl
- prompt-input 中能看到 Build iOS Apps、ShipSwift、Product Design、GitHub、Documents、Spreadsheets、Presentations 等插件上下文

额外验证 ShipSwift：
直接确认 ShipSwift MCP 暴露 listRecipes、searchRecipes、getRecipe。若当前线程看不到这些工具，但 codex debug prompt-input 能看到 ShipSwift，说明旧线程没有热加载插件，需要用户新开一轮或同目录分叉。

额外验证 Build iOS：
确认 xcodebuildmcp 可用，并能列出 iOS Simulator、build、test、screenshot、snapshot-ui 等工具。

最后汇报：
1. 已恢复哪些插件。
2. build-ios-apps 是否可用。
3. ShipSwift recipe 工具是否可用。
4. 当前线程是否需要重开一轮加载插件。
5. 明确说明没有删除、归档或破坏任何对话历史。
```

备注：
- 不建议将 `$HOME/.codex/config.toml` 改成只读。Codex App 会同步插件和运行时状态，强行只读可能导致插件列表再次异常。
- 已经运行中的旧线程通常不会热加载新插件工具；新回合、新线程或同目录分叉更容易拿到恢复后的插件上下文。
