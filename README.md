# 2026 移动应用创新赛准备包

继续开发前请先读：`PROJECT_UPDATE_LOG.md`。该文件是项目修改更新操作日志，说明当前项目是什么、已经做到哪、下一步先修什么，以及不能执行的危险操作。

## 当前策略

- 参赛路线：启迪主线，启明保底。
- 不走启航：当前没有已上架或 TestFlight App。
- 核心目标：稳妥冲奖，优先低开发复杂度、高创新表达、高社会价值。
- 主方案：专精用药依从性 App，方向为健康医疗与养老。
- 指导老师：计划由班主任担任。

## 官方依据

- 官网通知页：https://www.appcontest.net/REDACTED_HOME_PATH
- 章程：official/2026-附件二-大赛章程.pdf
- 组织机构：official/2026-附件一-组织机构名单0323.pdf
- 报名手册：official/2026报名手册.pdf
- 初赛模板：official/初赛作品说明文档模板.docx

## 目录说明

- docs：规则、赛道、技术边界、产品方向、数据源、安全边界和环境状态。
- docs/11-development-todo.md：当前后端、前端和 AI 接入待办清单。
- checklists：报名、作品提交和复赛前检查。
- templates：文档写作和沟通模板。
- official：本地保存的官方附件副本。
- swift-core：Windows 可测试的 SwiftPM 核心模块。
- ios-app：SwiftUI iOS App 工程，接入 swift-core 作为本地 Swift Package；当前已有今日、药物、AI 助手、风险、设置五 Tab。

## 当前实现状态

- swift-core：45 个 Swift Testing 测试通过，覆盖提醒、风险聚合、说明书可读化、依从性洞察、库存、导入审核、医疗 AI 接口、请求提示构造和风险三类分组。
- ios-app：iPhone 17 Pro 和 iPad Pro 13-inch (M5) 模拟器 Debug build 通过，iPhone 17 Pro 模拟器可安装并启动；根目录 Git 元数据已用非破坏性 `git init` 补齐。
- 已落地的可交互能力：首启引导横移/缩放/淡入动画、今日任务完成/撤销、今日天气与环境用药关注、已处理记录横滑操作、药物页健康式概览、药物详情、详情页药品照片选择/拍照入口、疗程和多提醒时间编辑、药盒低量提示、周/月历记录、复诊摘要分享、三入口添加药品、本机 OCR、条码图片识别、真机相机扫码、AI 助手首次确认、聊天式 AI 界面、AI 授权、后台 Keychain 凭据读取、Apple 账号与 iCloud 备份准备入口、风险置顶收敛与二级详情。
- 已接入的外部能力入口：豆包 Ark Responses API 已接到 AI 助手并完成真实请求冒烟；豆包供应商、模型和 endpoint 已作为后台默认值，真实密钥只通过启动环境或 Keychain 进入 App，不写入源码、文档、测试或构建日志；发送提示词约束 100 字以内纯文字，模型返回内容按原文展示。
- 仍等待外部资料：可靠条码 API 字段和授权方式、真机签名 Team 是否调整。

## 下一步

1. 确认班主任是否愿意担任指导老师，并准备报名所需信息。
2. 保持 swift-core 测试全绿，继续确保所有外部能力都有离线演示路径。
3. 按 docs/06-medical-safety-and-data-sources.md 控制医疗安全边界。
4. 用 templates/initial-work-description-outline.md 生成初赛说明文档第一版。
5. 继续完善 ios-app 的可靠条码数据源、医疗 AI 联调、iCloud/Apple 账号能力、真机签名和比赛材料。
