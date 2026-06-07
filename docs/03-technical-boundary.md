# 技术边界

## 当前环境状态

- Windows Swift Toolchain 6.3.2 已验证 SwiftPM build 和 run。
- Visual Studio Community 2022、MSVC、Windows 11 SDK 已配置。
- VS Code Swift 扩展与 LLDB DAP 已安装。
- Build iOS Apps 插件可用，但当前没有绑定 Xcode 项目、Scheme 或模拟器。

## 重要现实

Windows SwiftPM 能验证 Swift 语言、包结构和部分业务逻辑，但不能替代 macOS/Xcode 对 iPhone/iPad App 的构建、模拟器运行、签名和 TestFlight 流程。

真正进入 iOS App 阶段后，需要以下至少一种路径：

- 本机或远程 macOS + Xcode。
- 可供 Codex 操作的 Xcode 项目、Scheme 和 iOS 模拟器。
- 若进入上架或 TestFlight，另需 Apple Developer 账号或组委会后续支持。

## 推荐技术范围

- SwiftUI 原生界面。
- 本地轻量数据：JSON、UserDefaults、简单文件存储。
- 少量网络请求或可替换的模拟数据。
- 可解释的轻 AI 能力：文本整理、提醒生成、简单分类。
- iPhone 与 iPad 自适应布局，但不强依赖复杂多窗口。
- 本地通知：用于服药提醒。
- OCR 或扫码：先作为辅助录入，不作为强依赖。
- HealthKit：先作为复赛增强项，等 Xcode 项目和可用 SDK 确认后再纳入实现。

## 避免的技术范围

- 重后端、实时多人协作、大规模数据库。
- 复杂硬件接入。
- 高精度医疗诊断、金融决策、法律判断。
- 需要长期训练的模型或不可解释算法。
- 离线大模型、复杂计算机视觉、复杂三维空间计算。
- 药品剂量计算器。
- 自动处方、自动调整剂量或个体化治疗建议。
- 使用 HealthKit 数据作广告、营销或无关数据挖掘。
- 扫描药品追溯码后声称判断药品真伪或医保销售信息。

## App 架构上限

- 1 个主流程。
- 3-5 个核心页面。
- 1 个设置或历史记录页面。
- 1 套演示数据。
- 1 个清晰的社会价值叙事。

## 当前 App 功能上限

- 手动录入药品。
- 本地提醒。
- 服药打卡与漏服记录。
- 用户自行添加药品图片。
- 说明书可读化演示。
- 风险关键词提示。
- 本地隐私保护。

以下功能作为后续增强：

- Apple 健康/HealthKit 读取。
- 条码或追溯码辅助录入。
- 处方或医嘱 OCR。
- 外部医疗 AI 接口。
- 关键联系人共享。
