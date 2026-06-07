# API 配置与数据源计划

## 设计原则

- 网络只增强演示，不阻断主流程。
- 默认使用本地演示数据。
- 不上传用户身份、病史、服药记录或健康数据。
- API 返回内容只做说明和提示，不做诊断、处方或剂量计算。

## openFDA Drug Label

- Endpoint：https://api.fda.gov/drug/label.json
- 用途：获取药品标签中的 warnings、do_not_use、ask_doctor、ask_doctor_or_pharmacist、stop_use、dosage_and_administration、adverse_reactions、drug_interactions。
- 当前实现：OpenFDADrugLabelProvider。
- v1 策略：查不到或网络失败时使用 DemoDrugLabelProvider。

## RxNorm

- Endpoint：https://rxnav.nlm.nih.gov/REST/Prescribe/rxcui.json
- 官方功能：findRxcuiByString。
- 参数：name、search。
- 当前实现：RxNormDrugNameNormalizer。
- v1 策略：用于英文药品名标准化，不用于中国药品说明书判断。

## RxClass

- Endpoint：https://rxnav.nlm.nih.gov/REST/rxclass/class/byRxcui.json
- 官方功能：getClassByRxNormDrugId。
- 参数：rxcui。
- 当前实现：RxClassDrugClassProvider。
- v1 策略：用于药品类别解释，不作为药物相互作用判断依据。

## DailyMed

- 当前未接入。
- 后续用途：补充美国药品标签来源。
- 接入前需要再次核对官方 endpoint 与字段。

## 中国药品数据

- 当前没有确认可直接用于比赛 App 的权威开放说明书 API。
- 国家医保药品耗材追溯信息查询不等于本 App 可以判断药品真伪或医保销售记录。
- v1 不承诺中国药品条码直接匹配说明书。

## 豆包 Ark Responses API

- 当前用途：AI 助手对话、风险提示可读化、OCR/条码导入草稿复核提示和复诊沟通建议。
- Responses endpoint：`https://ark.cn-beijing.volces.com/api/v3/responses`。
- 鉴权方式：请求头 `Authorization: REDACTED_SECRET <API_KEY>`。
- 内容类型：请求头 `Content-Type: application/json`。
- 当前默认模型：`doubao-seed-2-0-lite-260428`。
- 当前请求方式：非流式 `POST`；body 包含 `model` 和 `input`，文本以 `input_text` 发送。
- 当前响应读取：优先读取 `output_text`，否则读取 `output[].content[].text` 作为 AI 助手回复；App 不把模型输出写成诊断、处方或剂量调整。
- 密钥策略：演示阶段通过启动环境 `ARK_API_KEY` 注入并写入 iOS Keychain；不得写入源码、文档、测试、构建日志、截图文字或可静态读取的 App 资源。
- 请求数据策略：只有用户在 AI 助手授权后，才把已授权范围内的用药记录、药品信息、风险卡片、说明书摘要或导入草稿拼入请求；请求审计只记录供应商、模型、请求类型和共享范围。
- 失败策略：未配置密钥、鉴权失败、限流、网络失败或响应为空时，显示清晰失败提示，并保留本地演示流程。
- 已完成项：真实请求冒烟测试通过；App 聊天页已展示模型返回原文。

## 百川医疗大模型备用适配

- 文档页：https://platform.baichuan-ai.com/docs/medical
- 当前用途：AI 助手对话、风险提示可读化、OCR/条码导入草稿复核提示和复诊沟通建议。
- Chat endpoint：`https://api.baichuan-ai.com/v1/chat/completions`。
- 鉴权方式：请求头 `Authorization: REDACTED_SECRET <API_KEY>`。
- 内容类型：请求头 `Content-Type: application/json`。
- 当前备用模型：`Baichuan-M3-Plus`；供应商和凭据配置隐藏在后台，不在前端暴露给用户手动选择。
- 当前请求方式：非流式 `POST`；body 包含 `model`、`messages`、`stream=false`、`temperature`、`top_p`、`top_k`、`max_tokens` 和 `metadata`。
- 当前响应读取：读取 `choices[0].message.content` 作为 AI 助手回复；不把模型输出写成诊断、处方或剂量调整。
- 密钥策略：真实密钥只允许通过启动环境或 Keychain 写入；不得写入源码、文档、测试、构建日志、截图文字或可静态读取的 App 资源。
- 请求数据策略：只有用户在 AI 助手授权后，才把已授权范围内的用药记录、药品信息、风险卡片、说明书摘要或导入草稿拼入请求；请求审计只记录供应商、模型、请求类型和共享范围。
- 失败策略：未配置密钥、鉴权失败、限流、网络失败或响应为空时，显示清晰失败提示，并保留本地演示流程。
- 未完成项：文件上传、流式输出、真实频率限制 UI、模型返回内容越界拦截和端到端真实请求冒烟测试。

## 网络失败策略

- 搜索失败：显示本地演示数据或提示手动录入。
- 字段缺失：只展示可确认字段。
- 数据源不适配：中国药品和美国标签不混用为医疗判断。
- 用户确认：所有自动生成的提醒草案必须由用户确认。
