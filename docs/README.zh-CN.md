# MedCue 文档索引

[简体中文](README.zh-CN.md) · [English](README.md)

本索引用于避免把历史记录误当作当前工程事实。文档不一致时，应按以下权威顺序处理，并用准确源码版本和测试核对重要结论。

## 权威顺序

1. `../CONTEXT.md`：产品上下文、当前发布范围、目标行为、语言和安全不变量。
2. 源码、测试、已提交配置和准确版本证据：实现实际做了什么。
3. `PROJECT_STATUS.md`：当前已验证的工程状态和主要风险。
4. `ARCHITECTURE.md` 与 `TEST_STRATEGY.md`：预期工程边界。
5. `DEVELOPMENT_WORKFLOW.md` 与 `../AGENTS.md`：交付流程和协作规则。
6. 已接受的 ADR：具体持久架构决策及其后果。
7. 下方列出的运行与历史资料。

生成的摘要、知识图谱、模型评估、聊天记录和交接文档只能用于导航，不能覆盖上述来源。

## 当前文档

| 文档 | 用途 |
| --- | --- |
| `PROJECT_STATUS.md` | 当前基线、阻塞项、技术债务和产品决策 |
| `ARCHITECTURE.md` | 模块、状态、持久化、平台和信任边界 |
| `TEST_STRATEGY.md` | 风险到证据的验证映射 |
| `DEVELOPMENT_WORKFLOW.md` | Issue、branch、Pull Request、CI、评审和发布流程 |
| `GITHUB_LOCALIZATION.md` | 中文优先、英文保留的 GitHub 文档、模板和标签约定 |
| `SOURCE_PACKAGE_POLICY.md` | 基于准确 Git 对象的源码打包、白名单、溯源和发布检查 |
| `THIRD_PARTY_NOTICES.md` | 仅源码包的依赖、许可和署名边界 |
| `adr/` | 已接受的持久架构决策及其后果 |
| `../CONTEXT.md` | 产品上下文、发布范围、参与者、术语、不变量和平台职责 |
| `../AGENTS.md` | 仓库级协作和安全规则 |

## 运行参考

- `13-iphone-signing-and-live-activity-test.md`：历史真机脚本；使用其中的场景，但要在当前 Pull Request 中针对准确版本记录证据。
- `24-privacy-data-flow-audit-20260727.md`：详细隐私审计证据；事实变化时以 `PROJECT_STATUS.md` 为准。
- `25-token-broker-deployment-prerequisites-20260727.md`：Broker 部署和账号前置；操作前核对真实 CloudBase 状态。
- `openai-image-local-api.md`：本地图像生成辅助说明。
- `watchos-support/README.md`：历史 Watch 实现和真机证据；按照当前 `PROJECT_STATUS.md` 重新验证。

## 历史证据

仓库中仍保留从 `01-...` 到 `25-...` 的编号规划、策略、快照、加固、依赖图和架构资料，用于审计和上下文参考。它们不是当前 backlog，可能包含只在当时成立的陈述。

`11-development-todo.md` 是冻结的历史记录。仓库不包含 `../PROJECT_UPDATE_LOG.md`、已移除的 Watch 交接/开发日志文件或隐私清理后的迁移资产和占位符。不要根据猜测或原始输入重建这些缺失材料。新工作进入 GitHub Issue；验证和评审证据进入 Pull Request；持久架构决策进入 ADR。

## 维护规则

只有在所属事实发生变化时才更新当前文档。优先链接已有证据，而不是在多个文件复制状态。只有当新文档有清晰的唯一归属并能避免重复错误时，才新增永久文档。
