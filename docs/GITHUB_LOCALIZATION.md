# GitHub 协作界面本地化约定

[简体中文](README.zh-CN.md) · [English summary](#english-summary)

本文件记录 MedCue GitHub 协作界面的“中文优先、英文保留”约定。它只覆盖 README、文档入口、Issue、Pull Request、标签和仓库公开描述，不代表 App、Watch、Widget 或 Live Activity 已完成完整双语支持。

## 语言策略

- 面向中文团队和竞赛展示的主要阅读路径使用简体中文。
- 英文原文保留在 README、开放 Issue、重要验收标准和必要的模板说明中。
- 代码标识符、路径、Issue 编号、URL、协议值、持久化字段、跨进程标识和稳定查询值保持原样。
- 用户输入、药品名称、OCR/处方原文、包装说明、健康样本和历史对话不因界面语言而被翻译或改写。
- 医疗安全文字必须逐句保持语义；“已处理”“未响应”“已服用/使用”“跳过”和“重新打开”不能互换。

## 标签迁移表

远端标签已按下表逐项重命名并读回；表中的“当前标签”是迁移前名称，不表示旧标签仍存在。仓库模板现在只声明目标中文标签，稳定的流程控制值继续保留英文。

| 当前标签 | 目标中文标签 | 类型/用途 | 迁移决策 |
| --- | --- | --- | --- |
| `bug` | `缺陷` | 类型 | 重命名 |
| `feature` | `功能` | 类型 | 重命名 |
| `technical-debt` | `技术债务` | 类型 | 重命名 |
| `documentation` | `文档` | 类型 | 重命名 |
| `governance` | `治理` | 类型 | 重命名 |
| `needs-product-decision` | `需要产品决策` | 状态 | 重命名 |
| `platform` | `平台` | 领域 | 重命名 |
| `device-validation` | `设备验证` | 领域 | 重命名 |
| `blocked` | `已阻塞` | 状态 | 重命名 |
| `ai` | `医疗 AI` | 领域 | 重命名 |
| `release` | `发布` | 领域 | 重命名 |
| `privacy` | `隐私` | 领域 | 重命名 |
| `duplicate` | `重复` | GitHub 默认类型 | 重命名 |
| `enhancement` | `增强` | GitHub 默认类型 | 重命名 |
| `good first issue` | `适合新手` | GitHub 默认类型 | 重命名 |
| `help wanted` | `需要帮助` | GitHub 默认类型 | 重命名 |
| `invalid` | `无效` | GitHub 默认类型 | 重命名 |
| `question` | `问题` | GitHub 默认类型 | 重命名 |
| `wontfix` | `不处理` | GitHub 默认类型 | 重命名 |
| `P0` | `P0` | 优先级 | 保持稳定 |
| `P1` | `P1` | 优先级 | 保持稳定 |
| `P2` | `P2` | 优先级 | 保持稳定 |
| `state:in-progress` | `state:in-progress` | 协作租约 | 保持稳定 |
| `execution:windows-capable` | `execution:windows-capable` | 执行环境 | 保持稳定 |

不删除标签、不创建同义重复标签。标签名称变更后，必须同步检查 Issue Form 的 `labels` 字段、流程文档中的精确引用以及 GitHub 搜索链接。稳定标签保留英文是为了避免把流程控制值变成仅供展示的翻译文本。

## Issue 与 Pull Request

- 新 Issue 使用中文优先标题和正文，并在正文中保留英文对应内容。
- 开放 Issue 逐项翻译；关闭 Issue 的原文不覆盖，只在确有协作价值时追加中文摘要。
- 翻译时不得改写验收条件、风险分类、Issue/PR 链接、源码路径或协议名称。
- 所有示例继续使用合成或已清理的数据，不得加入真实用药记录、健康信息、设备标识符、密钥或绝对路径。

## 远端迁移记录与后续约定

1. 在仓库分支中更新 README、中文文档入口、Issue Form、Pull Request 模板和本约定。
2. 通过 Pull Request 评审模板字段、标签目标名和医疗/隐私术语。
3. 本轮已合并后逐个更新标签名称和描述，并在每一步读回；标签颜色与 Issue/PR 关联保持不变。
4. 仅翻译无指派且不含敏感内容的开放 Issue #18、#19；协作者负责的 #5、#35、#20–#23 不改标题、正文、指派人或状态，含敏感部署凭据记录的 #16 不改正文。
5. 只为需要协作的关闭 Issue 增加中文摘要，不覆盖英文历史正文。
6. 仓库简介已更新并回读；Topics 因未确认可接受的精确词条，保持不变。
7. 运行旧标签搜索、模板标签存在性、Issue 数量、标签分布、链接和敏感信息检查。

任何远端写入出现超时或返回不确定时，先只读查询目标对象；没有确认前不得重试或执行反向操作。

## English summary

This document defines a Chinese-first, English-preserved GitHub collaboration surface. Human-facing labels may be renamed to Chinese, while workflow-stable values such as `P0`, `P1`, `P2`, `state:in-progress`, and `execution:windows-capable` remain unchanged. Code identifiers, paths, URLs, protocol values, persisted fields, cross-process identifiers, and user/source content remain byte-for-byte or semantically stable.

The remote human-facing label migration is complete: labels were renamed one by one, colors and associations were read back, and stable workflow values remain English. Issue translation remains selective: #18 and #19 were translated while collaborator-owned and sensitive Issues were preserved. This does not claim complete bilingual support for the app or its companion bundles.
