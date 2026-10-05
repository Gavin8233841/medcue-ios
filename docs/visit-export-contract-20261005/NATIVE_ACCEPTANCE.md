# Xcode / PDFKit 最小验收与串行协调

当前全部为待执行清单。没有编译过的 Swift 测试附件，也没有宣称可直接导入 Xcode 的新测试 API。

## 1. 开始前与版本协调

1. 检查真实 checkout 的 AGENTS、branch/upstream、HEAD、dirty files、可用 Xcode 与 SDK；记录唯一实现负责人
2. 本目录只读输入。先读准确版本的 `AGENTS.md`、`CONTEXT.md`、`docs/PROJECT_STATUS.md` 和 `docs/DEVELOPMENT_WORKFLOW.md`；不要覆盖已有未提交改动
3. #150 的 9 个候选路径与本任务相关：`VisitSummaryDataPipeline.swift`、`VisitSummarySnapshotRevision.swift`、`VisitSummaryPDFViews.swift`、`VisitSummaryTextBuilder.swift`、`VisitSummaryView.swift` 及四个相关测试文件。先由协调人确定 #150 串行整合次序与唯一写入者；不并行改写同一候选文件，不隐式 cherry-pick
4. 基线审查是 main `4d9c6d50d46a5735dc014da5434e1063d8cf7493`；#150 日期候选是 `683c54c4a808560b4b7c0350c9e1b1b9e25a6893`。若本地已换基线，重读差异并选择匹配 JSON profile，不能混用旧 API/新期望
5. 后续实现应只触及已协调的 PDF 标题/绘制和必要独立测试路径。不要改 queries、计数、Schema、HealthKit、AI、导出生命周期、README 或 PROJECT_STATUS 等已占用文件来消解冲突；最终状态文档由协调人统一处理

## 2. 接入真实类型，复用现有测试 seam

以下类型均来自源码；JSON 的 alias/purpose/expected/rationale 仅测试元数据，不入 App：

- 药物 → `StoredMedication(id:displayName:kind:form:strength:inputSource:lifecycleStatus:createdAt:)`；枚举分别 `.prescription`、`.manual`、`.active/.archived`
- 计划 → `StoredMedicationPlan(id:medicationID:doseValue:doseUnit:timingSummary:timeZonePolicy:sourceNote:createdAt:)`，时区策略 `.localClock`
- 任务 → `StoredDoseTask(id:medicationID:planID:dueAt:doseValue:doseUnit:status:recordedAt:reason:)`；`effectiveAdherenceRecordedAt` 是计算属性，源为 `recordedAt`，不能直接赋值；`corrected` 同 `taken` 计已服用
- 剂量变化 → `StoredMedicationDoseChange(id:medicationID:planID:previousDoseValue:previousDoseUnit:newDoseValue:newDoseUnit:effectiveFrom:changedAt:note:)`
- 生命周期 → `StoredMedicationLifecycleEvent(id:medicationID:status:occurredAt:note:)`；B 的归档事件在期末之后，药物当前属性仍 archived，不能为把它排出报告而改历史
- 风险 → `StoredRiskCard` 原初始化器；`isActive` 是 `archivedAt == nil && resolvedAt == nil` 计算属性，不能直接给 `isActive` 赋值；原 raw 枚举 `.labelRisk/.medium/.localRule`
- `healthSignals` 固定空数组；不要调用授权界面或读取真实健康数据

复用 `MedicationAdherenceAppTests/VisitSummaryDataPipelineTests.swift` 中 `VisitSummaryDataFixture` 的形状：`@MainActor`，内存 `ModelContainer` 明确登记上述六个 Stored 类型，构造 `ModelContext`，插入并 `try context.save()`。该 helper 是文件内 `private`，新文件不能直接调用；小范围复制已核验的 setup 形状或经协调提取，不能猜它是公开 API。

原 `emptyTrendDashboard` 使用 `MedicationTrendDashboardBuilder().build(scheduledDoses:events:doseChanges:healthSignals:timeZone:now:)`。测试可使用空 dashboard 隔离 PDF 列表绘制；这不能代替 Snapshot 的真实集合/计数测试。

接力需覆盖两层：

1. SwiftData → `VisitSummaryDataCommand.load` → `VisitSummarySnapshot.build(revision:medications:tasks:doseChanges:plans:lifecycleEvents:riskCards:healthSignals:healthRefreshedAt:generatedAt:)`：逐字段核对 JSON 的 loader / report / text 期望；`VisitSummarySnapshotRevision` 使用真实字段，main 为 `endDate`，#150 为 `endDateExclusive`
2. Snapshot → `VisitSummaryExportPayload(medications:tasks:doseChanges:riskCards:trendDashboard:healthSignals:startDate:…:generatedAt:exportSignature:)` → `VisitSummaryPDFExporter.export(payload:lifecycle:)`：遵从 checkout 的准确结束字段。不要使用 `VisitSummaryExportPayload(data:)` 把 loader 的中间集合直接当生产 Snapshot 集合；event-only 中间集合含 C，而最终 PDF 不含 C

`VisitSummaryMedicationValue` 有 `init(_ medication: StoredMedication)`；不可假定存在 `init(id:displayName:…)`。当前 `VisitSummaryPDFReport` 唯一已核验入口是 `init(payload:)` 与 `draw(in:pageBounds:)`，没有现成分页 planner 或 row-height API。

日期用 ISO 8601 显式 offset 转 Date，固定生成时间，测试日历设 Gregorian/Asia/Shanghai 并恢复任何全局改动；不要把中文标题的日期格式绑定到未设置的系统 locale。日期 API/SwiftData 使用 `Calendar.current` 的部分应串行执行，不让测试相互改时区。#150 的日期测试已有 calendar 参数覆盖 UTC/Shanghai/New York/São Paulo，应复用而非从头改日期实现。

## 3. 最小断言集（真实原生，不能由 Python 代替）

- 6药：loader 7 条任务含 A 的逻辑重复，Snapshot 6条；3已服用、1稍后、1忽略；药物 A/B/D/E/F/G，排除 C；F/G 不按名字合并
- 5药：5个ID，首页4，续页1；4药：首页4，无续页；0药：药数0，保留原2页，不加空续页
- 6药排序：01/02/03/04/05/05；相同05名称的F/G相对顺序只要求与 loader 相同，不强制 UUID 次序；首页 A/B/D/E，续页 F/G，各规格 11 mg/22 mg 区分
- event-only：loader A/B/C，Snapshot/PDF A/B，药数2，任务0；文本摘要任务药数0、无A/B用药记录行。不要对完整文本做「不能包含 B」断言，风险段允许含 B
- 更正前后同 task UUID：前态 effective date 在次日，报告0；后态在期末且 corrected，报告1、完成1。原 `exportPayloadCopiesValuesBeforeStoredModelsChange` 继续通过；旧 payload 不跟随后续 StoredModel 变动
- 跨末日：main 纳入B/E/F，#150 纳入A/B/E/F；恰好次日00:00不纳入。只有整合 #150 后才能使用后者断言
- 检查 Snapshot 药数与 PDF 药数不变。fixture 保证引用完整；悬挂 ID 是本轮范围外，不借此改既有计数逻辑

## 4. PDFKit + 实际页面检查

在具备 PDFKit 的原生测试 target 中读取真实导出的 URL。用 SDK 自身 `PDFDocument(url:)`、`pageCount`、`page(at:)`、页的 `string`/边界与渲染能力；先用本地 SDK 编译核验 API 可用性，不在云端声称已运行。

- 必须非 nil 可打开，保留595×842 pt；原有两页顺序保持。0/4药恰好2页；5/6药至少3页且只有需要时才继续分页，不把某个固定页数当通用规则
- 首页标题只用「所选期间涉及药品」，不残留「当前药品」作为药品集合标题。溢出时提示应明确剩余药品位于后续明细页；无续页回退版必须仍诚实提示未展开
- 在第1页的药品列表区域和续页药品列表区域定位名称/规格/次数。不要全报告按药名出现次数计数：时间线/风险可能再次引用药名；F/G同名时以规格、行分配与模型ID联合验收
- 全称中文不出现乱码。续页 F/G 长名与规格完整可提取、可搜索/复制；截图确认换行、不尾截断、不重叠、不压页脚，文字提取成功不能证明没有视觉裁切
- 首页原字号/边距/颜色/结构不扩大改动。检查普通字号与辅助功能最大字号下生成、预览、分享按钮的真实点击区与文字布局；PDF固定排版另验，不因 SwiftUI Dynamic Type 通过就声称 PDF 可访问
- QuickLook/VoiceOver 实际读序、页间导航与长名可读；无法证明时标「未验证」，不由 PDFKit.text 或颜色对比推定通过
- 在当前合成字体预算下5/6药目标是单张续页；若实际需要更多页，先查测量/留白原因。一般文本长度无上限，不固定最大页数来截断其余药物

**可选后续：跨第二次换页压力检查。** 仅当真实实现需要验证第二次换页时，由本地协调人选取最小足够的合成输入；不固定48药、总页数或设备执行次数，不阻挡本轮0/4/5/6药、长名与日期验收。实现仍须满足基本的分页推进、每ID一次和不死循环要求；可在测量/分页单测中使用很小的可用页高验证换页与终止，无需批量造药走实机流程。是否追加原生压力检查，按实际证据缺口决定。

## 5. 文件生命周期和 UI 重入

继续跑 `VisitSummaryDataPipelineTests`、`VisitSummarySnapshotRevisionTests`、`VisitSummaryPDFLifecycleTests`；#150 整合后另跑其 `VisitSummaryDateRangeTests`。现有 `pdfExporterWritesAReadablePDF` 只验 `%PDF` 前缀与长度 >1000，不能替代上述 page/text/render 断言。

最小手动路径：设置/个人页→复诊资料→选择范围→生成→预览→关闭→分享→取消→更正合成记录→重生成；快速重复生成、切范围、返回页面后旧完成不能覆盖新快照。预览/分享持有期间旧文件不得提前删；取消/失败不留下未保护或半成品文件。沿用原 lease/generation gate，不为续页另造一套。

## 6. 运行与证据

已核验 `tools/verify-native.sh`：scheme `MedicationAdherenceApp`，unit target `MedicationAdherenceAppTests`，UI target `MedicationAdherenceAppUITests`，项目 `ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj`。默认 simulator 是脚本当前配置 iPhone 17 Pro / iOS 26.5，**不能假定已安装**；用 Xcode 原生工具或 `xcodebuild -showdestinations` 取实际可用 destination。

本轮优先执行受影响的4个测试 suite（第4个日期 suite 仅在 #150 已整合时存在）、`tools/verify-native.sh --quick`、一次目标构建与导出视检。目标构建可复用 focused tests 已产生的同版本构建产物；不要为了同源证据机械重复构建。先完成0/4/5/6药、长名、集合/文本区别、日期与更正核心验收，发现实际问题再补针对性测试。

`--quick` 明确不构建，不能写成 Xcode 测试通过。完整全App原生 gate 仅在本地整合范围或既有仓库门禁要求时运行；本接力不默认要求把准确同源已绿的所有 suite 全部重跑。若最终代码变化触发既有门禁，按门禁执行，不能用云端fixture检查或旧版本证据替代。记录准确HEAD、dirty diff、实际受测范围、SDK/destination、命令、退出码、xcresult及PDF/截图SHA，并分清通过/失败/未运行。

以下是**尚未运行的本地命令模板**。在真实仓库根目录执行，先把 `VERIFIED_DESTINATION` 设置为原生工具/`xcodebuild -showdestinations` 实际确认的完整 destination；不可照搬脚本默认设备来声称可用：

```sh
: "${VERIFIED_DESTINATION:?先填已核验的本地Simulator destination}"
tools/verify-native.sh --quick
xcodebuild -project ios-app/MedicationAdherenceApp/MedicationAdherenceApp.xcodeproj \
  -scheme MedicationAdherenceApp -configuration Debug \
  -destination "$VERIFIED_DESTINATION" \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  -only-testing:MedicationAdherenceAppTests/VisitSummaryDataPipelineTests \
  -only-testing:MedicationAdherenceAppTests/VisitSummarySnapshotRevisionTests \
  -only-testing:MedicationAdherenceAppTests/VisitSummaryPDFLifecycleTests \
  MEDCUE_SIMULATOR_UNIT_TEST_BUILD=YES test
```

#150 已整合时，在同一次 focused test 命令中增加 `-only-testing:MedicationAdherenceAppTests/VisitSummaryDateRangeTests`；未整合时不调用不存在的 suite。新补PDF列表测试如放入独立suite，应按真实类名加入，不能猜名称。若使用现有原生执行工具，可表达同样的目标范围，无需再重复跑命令模板。脚本也支持 `VERIFY_NATIVE_TEST_SUITE=ios-unit`，但它会运行整个unit target，本轮不默认以它替代上述窄范围。

仅在确认完整门禁适用后，才使用 `VERIFY_NATIVE_IOS_TEST_DESTINATION="$VERIFIED_DESTINATION" tools/verify-native.sh`。这些是接力执行入口，不是运行回执；前置条件不足时报告真实失败/未运行。

本项不生成竞赛分发包。验收证据仅使用本目录的合成 fixture。

## 7. 回退与停止点

- 能小改：现有 `draw` 两页后加测量分页；只处理 `medications.dropFirst(4)`，原集合与计数完全沿用；分页时页脚预留与跨页推进必须可证明不死循环
- 不够小：保留标题修正与原余数说明，续页标待办，报告「范围标签已修正，完整列表续页尚未交付」；不宣称通过完整导出验收
- 出现候选文件冲突、需要重做绘制引擎/数据层或改变统计定义与数据范围，停止实现并记录明确决策点
- 本包成功终点仅为输入/期望可审查且契约检查通过；原生终点另需最后代码的实际 Xcode/PDFKit/页面检查与范围内生命周期证据
