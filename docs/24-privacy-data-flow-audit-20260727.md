# MedCue 隐私数据流核对（2026-07-27）

本文件记录当前源代码能够证明的数据流。当前竞赛与受控真机 Beta 范围内，服务器日志策略和第三方服务后台保留策略不在仓库内，必须由负责人在对应后台逐项核验；只有未来启动 App Store 分发时，App Store Connect 的 collected data 答案才成为提交前核验项。两类事实都不能由本地代码推定为已完成。

| 数据类别 | 触发与授权 | 设备内处理与存储 | 系统或设备间流向 | 云端流向 | 当前结论 |
| --- | --- | --- | --- | --- | --- |
| 相机与照片 | 用户主动选择照片或打开相机；相机使用 `NSCameraUsageDescription` | 图片数据交给 Vision 文本/条码识别；药品照片仅在用户保存后写入 SwiftData；识别任务可取消且旧结果被 generation gate 拒绝 | PhotosPicker/UIImagePickerController 由系统提供选择界面 | 图片本身不由 Vision pipeline 上传。智能体图片问题会先在设备上 OCR，只有用户再次发送且选择在线智能体时，识别出的文字才进入在线请求 | 本地识别边界已由代码和测试固定 |
| HealthKit | 用户主动请求 Apple 健康读取授权；使用 `NSHealthShareUsageDescription` 与 HealthKit entitlement | 读取最近 56 天授权范围内的生命体征，形成内存趋势摘要和本地复诊资料；当前 `MedicalAIRequest` 不包含 HealthKit 样本 | 通过 HealthKit 系统框架读取 | 当前代码不把 HealthKit 样本加入在线 AI 请求 | 若未来启动 App Store 分发，再核验 collected data 答案 |
| 位置与天气 | 用户主动允许使用位置；使用 `NSLocationWhenInUseUsageDescription` | 只请求约 3 公里精度的单次位置；WeatherKit 结果转为温度、湿度、降水、紫外线、风速和天气描述，再在设备上生成用药环境提示 | 原始位置交给 CoreLocation/WeatherKit 系统服务 | 在线智能体仅在问题需要天气语境时接收派生的环境提示；当前请求构造不包含经纬度 | WeatherKit 属 Apple 系统服务；在线 provider 只接收派生摘要 |
| 药品资料、计划、库存、记录、风险与说明书 | 用户在 App 内录入、导入或确认 | SwiftData 本地存储；写入通过应用层 command 提交与回滚；Watch 只接收当天所需的精简快照 | App Group 保存 Watch 快照，WatchConnectivity 在配对设备间同步 | 仅当用户授权具体 AI scope 并发送问题时，相应快照才进入在线请求；端点受 allowlist 与禁止重定向策略约束 | 本地与在线边界已有授权模型和回归测试 |
| AI 对话 | 用户接受提示、选择共享范围并主动发送 | 用户消息、最终 assistant/system 消息写入 SwiftData；最终响应只在安全 Guard 和提交成功后显示；中断请求会被标记为未完成 | 无跨设备自动同步 | 在线模式默认经 HTTPS Token Broker 转发至受控上游；客户端只发送已授权 prompt 和 request ID，不持有供应商主密钥；Broker 的进程内幂等缓存会暂存完整 prompt 与 answer，当前过期清理依赖同 key 再次读取且没有容量上限 | Broker 已完成非医疗请求与真机 Beta 联调；缓存主动过期、容量边界及无内容日志由 [Issue #23](https://github.com/Gavin8233841/medcue-ios/issues/23) 跟踪；商业生产身份控制另行增强 |
| 本地模型 | 用户主动下载并选择离线智能体 | GGUF 保存到 Application Support，先校验大小和 SHA-256；prompt、生成、质量修复和 Guard 均在设备内完成 | Background Assets/URLSession 负责下载传输 | 模型文件从固定下载地址获取；推理内容不上传 | GGUF 被 Git、Release 断言和最终打包规则排除 |
| 偏好与运行状态 | App 功能使用过程中写入 | UserDefaults 保存授权完成状态、UI 偏好、失败提示和 Watch 快照；SwiftData 保存业务记录 | App Group 中的 Watch 快照可供 Watch/Widget 读取 | 不因 UserDefaults 本身产生云端上传 | `PrivacyInfo.xcprivacy` 声明 UserDefaults required-reason API |

## 三类声明必须分开

1. `Info.plist` 权限用途：解释相机、位置、HealthKit、AlarmKit 为什么在用户触发后被请求。
2. `PrivacyInfo.xcprivacy`：声明 required-reason API。当前清单声明 UserDefaults 的 `1C8F.1` 与 `CA92.1`，并由主 App、Watch App、Watch Widget 三个 target 复制到各自 bundle。
3. App Store Connect collected data：仅在未来启动 App Store 分发时进入发布门；是否收集、是否关联身份、是否用于追踪等答案只能在发布后台核验。本仓库没有后台截图或导出，不得提前写成已完成。

## 当前外部核验与未来发布触发项

- 当前隐私修复：DEBUG reminder/Live Activity smoke 日志仍包含不应记录的任务标识与药品显示文本；Broker 幂等缓存的过期与容量也未主动强制。两项均由 [Issue #23](https://github.com/Gavin8233841/medcue-ios/issues/23) 阻塞受控 Beta，不得表述为日志或临时保留边界已完成。
- Token Broker 商业生产增强：当前 Broker 已完成部署、契约测试、非医疗健康检查和真机 Beta 验证；App Attest/DeviceCheck、用户与设备绑定、短时令牌和按主体配额仍需后续发布阶段补齐。
- App Store Connect 隐私答案：当前不阻塞竞赛或受控真机 Beta；若未来启动 App Store 分发，需要发布者账户权限核对实际提交值。
- 真机权限矩阵：相机、HealthKit、位置、通知、AlarmKit、Live Activity、Watch 重连与后台行为仍需真实设备覆盖；Simulator 结果不能替代。
