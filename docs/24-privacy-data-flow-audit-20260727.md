# MedCue 隐私数据流核对（2026-07-27）

本文件记录当前源代码能够证明的数据流。App Store Connect 的 collected data 答案、服务器日志策略和第三方服务后台保留策略不在仓库内，必须由发布者在对应后台逐项核验，不能由本地代码推定为已完成。

| 数据类别 | 触发与授权 | 设备内处理与存储 | 系统或设备间流向 | 云端流向 | 当前结论 |
| --- | --- | --- | --- | --- | --- |
| 相机与照片 | 用户主动选择照片或打开相机；相机使用 `NSCameraUsageDescription` | 图片数据交给 Vision 文本/条码识别；药品照片仅在用户保存后写入 SwiftData；识别任务可取消且旧结果被 generation gate 拒绝 | PhotosPicker/UIImagePickerController 由系统提供选择界面 | 图片本身不由 Vision pipeline 上传。智能体图片问题会先在设备上 OCR，只有用户再次发送且选择在线智能体时，识别出的文字才进入在线请求 | 本地识别边界已由代码和测试固定 |
| HealthKit | 用户主动请求 Apple 健康读取授权；使用 `NSHealthShareUsageDescription` 与 HealthKit entitlement | 读取最近 56 天授权范围内的生命体征，形成内存趋势摘要和本地复诊资料；当前 `MedicalAIRequest` 不包含 HealthKit 样本 | 通过 HealthKit 系统框架读取 | 当前代码不把 HealthKit 样本加入在线 AI 请求 | App Store collected data 仍需发布者核验 |
| 位置与天气 | 用户主动允许使用位置；使用 `NSLocationWhenInUseUsageDescription` | 只请求约 3 公里精度的单次位置；WeatherKit 结果转为温度、湿度、降水、紫外线、风速和天气描述，再在设备上生成用药环境提示 | 原始位置交给 CoreLocation/WeatherKit 系统服务 | 在线智能体仅在问题需要天气语境时接收派生的环境提示；当前请求构造不包含经纬度 | WeatherKit 属 Apple 系统服务；在线 provider 只接收派生摘要 |
| 药品资料、计划、库存、记录、风险与说明书 | 用户在 App 内录入、导入或确认 | SwiftData 本地存储；写入通过应用层 command 提交与回滚；Watch 只接收当天所需的精简快照 | App Group 保存 Watch 快照，WatchConnectivity 在配对设备间同步 | 仅当用户授权具体 AI scope 并发送问题时，相应快照才进入在线请求；端点受 allowlist 与禁止重定向策略约束 | 本地与在线边界已有授权模型和回归测试 |
| AI 对话 | 用户接受提示、选择共享范围并主动发送 | 用户消息、最终 assistant/system 消息写入 SwiftData；最终响应只在安全 Guard 和提交成功后显示；中断请求会被标记为未完成 | 无跨设备自动同步 | 在线模式直接请求已配置的豆包或百川固定 HTTPS 端点；本地仓库没有可证明的服务端日志与保留策略 | Token Broker 尚未部署，属于外部阻塞项 |
| 本地模型 | 用户主动下载并选择离线智能体 | GGUF 保存到 Application Support，先校验大小和 SHA-256；prompt、生成、质量修复和 Guard 均在设备内完成 | Background Assets/URLSession 负责下载传输 | 模型文件从固定下载地址获取；推理内容不上传 | GGUF 被 Git、Release 断言和最终打包规则排除 |
| 偏好与运行状态 | App 功能使用过程中写入 | UserDefaults 保存授权完成状态、UI 偏好、失败提示和 Watch 快照；SwiftData 保存业务记录 | App Group 中的 Watch 快照可供 Watch/Widget 读取 | 不因 UserDefaults 本身产生云端上传 | `PrivacyInfo.xcprivacy` 声明 UserDefaults required-reason API |

## 三类声明必须分开

1. `Info.plist` 权限用途：解释相机、位置、HealthKit、AlarmKit 为什么在用户触发后被请求。
2. `PrivacyInfo.xcprivacy`：声明 required-reason API。当前清单声明 UserDefaults 的 `1C8F.1` 与 `CA92.1`，并由主 App、Watch App、Watch Widget 三个 target 复制到各自 bundle。
3. App Store Connect collected data：是否收集、是否关联身份、是否用于追踪等答案只能在发布后台核验。本仓库没有后台截图或导出，因此保持“待发布者核验”，不得写成已完成。

## 外部阻塞项

- Token Broker：本地可以准备客户端接口、端点策略和部署文档，但在没有服务器访问方式、域名/TLS 与 provider 服务端密钥前不能真实部署。
- App Store Connect 隐私答案：需要发布者账户权限核对实际提交值。
- 真机权限矩阵：相机、HealthKit、位置、通知、AlarmKit、Live Activity、Watch 重连与后台行为仍需真实设备覆盖；Simulator 结果不能替代。
