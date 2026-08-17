# MedCue Token Broker 部署前置（2026-07-27）

> 状态：已被替代。本文件保留部署前的检查过程；Broker 已完成竞赛/Beta 部署与真机非医疗联调。当前契约见 `cloudfunctions/medcue-ai-broker/README.md`，当前风险见 `docs/PROJECT_STATUS.md` 与 `docs/24-privacy-data-flow-audit-20260727.md`。不要按本文“尚未部署”的步骤判断现状。

本文冻结部署输入、安全不变量和验收门。`cloudfunctions/medcue-ai-broker` 已实现并以测试固定一个非流式 v1 契约；尚未部署、尚未接入 iOS Release，不能写成上线完成。

## 当前实现契约

- 单一路径：`POST /v1/respond`，请求头为 `Authorization: REDACTED_SECRET <client-token>` 与 `Content-Type: application/json`。
- 请求体仅允许 `request_id`（canonical UUID）和 `prompt`（1 至 12000 字符）；整体最多 32768 bytes。
- 响应为 `{ "request_id": "...", "answer": "..." }`。不接受客户端指定 provider、endpoint 或 model。
- 上游固定为现有豆包 Responses endpoint，服务端从 `ARK_API_KEY` 与 `ARK_MODEL` 环境变量读取密钥和模型；这些值不得写入源码、iOS 设置或聊天。
- 未授权、无效输入、超限、上游 401/403/429/5xx、网络失败和超时均返回稳定的无敏感正文错误。
- 当前短期去重与限流是函数实例内实现，避免同一热实例的重试重复计费；跨实例强幂等尚未实现，不得声称全局 exactly-once。

## 当前客户端事实

- Release 客户端目前只允许两个固定 HTTPS provider endpoint，并拒绝 provider/endpoint 不匹配、URL 用户凭据、查询参数装饰和跨 endpoint 重定向。
- 豆包与百川 adapter 当前在设备端构造 provider 请求，并从受控注入或 Keychain 获取 provider 密钥。
- 请求在发送前经过用户授权范围校验；响应必须匹配 request ID，经医疗 Guard 处理并成功提交 SwiftData 后才能显示。
- Debug 仍允许绝对自定义 endpoint，用于本地联调；Release allowlist 在引入 Broker 前必须显式更新并补回归测试。

## 需要用户提供的部署输入

1. 腾讯云服务器的操作系统、CPU 架构、公网访问方式，以及一个权限受限的部署账号。不要在聊天中粘贴密码、私钥或 provider Token；应通过本机 SSH 配置、云端密钥管理或一次性受控注入提供。
2. 最终域名和 DNS 控制权，以及 TLS 证书方案。正式 App 不接受明文 HTTP，也不应直接依赖裸 IP。
3. 需要代理的 provider、模型和账号归属，以及对应服务端密钥的安全注入方式和轮换负责人。
4. 预期用户规模、单用户请求频率和可接受月度成本，用于确定限流、并发、超时和配额。
5. 是否有账号体系或设备证明机制。没有确认前，不把设备标识当作鉴权方案，也不采集稳定设备标识。
6. 法务/隐私要求：允许记录哪些运维字段、日志保留时长、日志访问人员、地域和删除流程。
7. 远端代码仓库与 CI 平台选择，以及部署、回滚、签名和秘密管理权限。

## 必须先对齐的接口契约

在实现服务端或改客户端前，应通过一份版本化契约明确以下内容：

- Broker 的单一 HTTPS endpoint 与 API 版本策略。
- 客户端鉴权方式、凭据有效期、刷新/撤销流程及重放保护。
- 请求与响应字段的精确名称、类型、必填性、最大长度和兼容规则。
- request ID 的生成方、透传规则和幂等语义。
- 允许的医疗上下文字段，以及默认不上传的字段。
- 流式或非流式响应方式、超时、取消、错误码和限流响应。
- Broker 到 provider 的模型映射、失败转译和是否允许 provider fallback。

这些内容必须来自确认后的服务端契约或实际联调结果，不能从现有 provider JSON 结构推导为 Broker 契约。

## 服务端安全不变量

- provider 密钥只存在于云端秘密管理或受限运行环境，不进入源码、镜像层、构建日志、客户端包或普通应用日志。
- TLS 终止后仍执行客户端鉴权、请求大小限制、内容类型校验、速率限制、并发限制和超时。
- 默认不记录 prompt、药名、剂量、计划、对话正文、HealthKit 数据、位置、Token、Authorization 或完整 provider 响应。
- 运维日志只保留最小字段，例如脱敏 request ID、时间、HTTP 状态、耗时、provider 类别、模型类别和错误类别；保留期必须由用户确认。
- 禁止任意上游 URL、开放代理、自动跨域重定向和客户端选择任意模型。
- 部署必须有健康检查、滚动更新或可回退版本、密钥轮换、异常率与限流告警。

## 客户端接入顺序

1. 先冻结并测试 Broker 契约，建立测试 adapter；现有 `MedicalAIClient` interface 保持不变。
2. 新增 Broker adapter，并补 HTTPS allowlist、禁止重定向、超时、取消、错误转译、request ID 与空响应测试。
3. Release 默认切到 Broker；直连 provider 仅在明确的开发配置下保留，且不得携带到 Release 产物。
4. 更新隐私数据流、用户授权文案、App Store Connect collected data 答案和运维手册。
5. 在测试环境完成限流、并发、超时、密钥轮换和日志脱敏演练后，再切正式域名。

## 当前部署流程

1. 已通过 CloudBase MCP 创建独立 HTTP 函数 `medcue-ai-broker`，使用 `Nodejs18.15`、端口 `9000` 与 `scf_bootstrap`；默认 HTTPS gateway 为 `https://gyy787891-d3ge5n8nlcaaf87e7.service.tcloudbase.com/medcue-ai-broker`。
2. 发布者仅在 CloudBase 函数环境变量中填写 `ARK_API_KEY` 和 `ARK_MODEL`；不要粘贴到聊天、仓库、Xcode Build Setting 或 iOS 包。
3. 配置函数网络权限允许调用，再以应用层 Bearer 校验限制访问；这个静态 client token 只能作为竞赛/低流量过渡措施，不等同于 App Attest 或用户身份。
4. 真实请求健康检查与日志抽检通过后，才新增 iOS Broker adapter 和 Release HTTPS allowlist。

CloudBase MCP 当前无法读取该函数日志，因此日志抽检必须在控制台或可用日志工具中实际完成；不能以 MCP 调用失败替代验收。

## 完成验收

- 客户端 Release 包和源码包均不含 provider 密钥。
- Broker 不能被未授权调用、重放或用作任意上游代理。
- 日志抽检不含医疗正文、Token、Authorization、设备标识和完整响应。
- provider 401/403/429/5xx、Broker 超时、客户端取消和重复 request ID 均有确定行为。
- 客户端自动测试、`tools/verify-native.sh`、服务端测试和部署健康检查全部通过。
- App Store 隐私答案、用户授权文案和实际生产数据流一致。
