# MedCue 复诊导出：最小原生接力契约

状态：可复跑的设计与数据契约；尚未实现 App 改动。Python 合成检查不代表 Swift、Xcode、PDFKit 或实际 PDF 渲染通过。

## 本次产品选择

- PDF 药品节标题改为「所选期间涉及药品」
- 首页仍显示既有排序的前 4 个药品；第 2 页保留现有时间线
- 超过 4 个时，从第 3 页起只展开其余药品；药品列表在整个报告中每个 Snapshot ID 恰好一次，无空续页
- 列表完整的意思是完整覆盖这个所选期间集合，并非完整的当前活跃药单；风险/时间线中再次提及药名不算重复列表行
- 保留原查询、统计、数据 Schema、快照复制、取消和文件保护生命周期；不加入 AI 摘要或新 HealthKit 权限
- 若复用现有绘制工具仍无法小改实现可靠分页，先只修标题，保留原「未在本页展开」提示；续页明确待完成，不重写 PDF 引擎

## 已核验基线与准确入口

仓库基线：[`main@4d9c6d50d46a5735dc014da5434e1063d8cf7493`](https://github.com/Gavin8233841/medcue-ios/commit/4d9c6d50d46a5735dc014da5434e1063d8cf7493)。源码路径以下从 `ios-app/MedicationAdherenceApp/` 起算，逐文件 blob SHA 在 `evidence/source-manifest.json`。

| 源文件/符号 | 真实职责与本契约字段 |
| --- | --- |
| `MedicationAdherenceApp/Views/SettingsView.swift:239–250` | 「复诊」→「复诊资料」→ `VisitSummaryView()` |
| `Services/VisitSummaryDataPipeline.swift`（App 目录内）`VisitSummaryDataCommand.load` | 查询期内任务、剂量变化、风险；并集 `medicationID` 后按存储的 `displayName` 排序取药；不是 active 药单查询 |
| 同文件 `VisitSummaryMedicationValue` | `id/displayName/form/strength/isArchived`；名称经 `userFacingMedicationName`；`isArchived` 来自药物当前生命周期 |
| `Views/VisitSummaryView.swift:333–460`（App 目录内）`VisitSummarySnapshot.build` | 任务先调用 `adherenceMeasurableTasks` 与历史期内过滤；集合为任务ID ∪ 剂量变化ID ∪ 活跃风险ID；保留 loader 排序 |
| `Models/DoseTaskFilters.swift`（App 目录内） | `effectiveAdherenceDate = recordedAt ?? dueAt`；排除系统停用提醒；按药ID/本地到期分钟/剂量/单位选择一个逻辑任务 |
| `Services/VisitSummaryDataPipeline.swift` `VisitSummaryExportPayload` | 在 MainActor 从 StoredModels 复制值；必须复用真实构造器，不能假定存在 value 的成员构造器 |
| `Views/VisitSummaryPDFExportViews.swift:14–30`（App 目录内） | `VisitSummaryPDFExporter.export(payload:lifecycle:afterPublication:)`；595×842 pt，`UIGraphicsPDFRenderer` |
| `Views/VisitSummaryPDFViews.swift:89–176`（App 目录内） | `VisitSummaryPDFReport.draw(in:pageBounds:)` 现在固定调用两次 `beginPage()`；首页 `medications.prefix(4)`，余数已有明确提示；续页最小切入点在现有两页之后 |
| `Views/VisitSummaryTextBuilder.swift:39–69`（App 目录内） | 摘要药数仅按任务ID；用药记录仅展开 `relatedTasks` 非空药物，不是无条件列出 Snapshot 全集合 |

上表省略 App 前缀的行均完整位于 `ios-app/MedicationAdherenceApp/MedicationAdherenceApp/` 下。测试目标已从 `project.pbxproj` 与 `tools/verify-native.sh` 核验为 `MedicationAdherenceAppTests`，scheme 为 `MedicationAdherenceApp`。

### 文本与 PDF 的范围区别

文本没有 PDF 首页的 4 条上限，但只展开有任务的药物。纯剂量变化/纯活跃风险可进入 Snapshot 和 PDF，未必成为文本用药记录行。`event_only_scope.json` 明确保留这个现状：PDF/Snapshot 药数 2，文本按任务药数 0。不能借「渠道一致」改变既有计数，也不能说现 PDF 在静默丢失药物；它已有余数提示。

## 日期版本不要混用

- 基线 main：`load(startDate:endDate:)`、`normalized` 返回 `end`，结束为末日 23:59:59，比较 `<=`
- 日期候选 [PR #150](https://github.com/Gavin8233841/medcue-ios/pull/150) 准确 HEAD `683c54c4a808560b4b7c0350c9e1b1b9e25a6893`：`load(startDate:endDateExclusive:)`、`normalized` 返回 `endExclusive`，比较 `<`；只处理完整所选日边界，不能当作续页已实现
- 每份 fixture 的 `expected.main_inclusive_seconds` 与 `expected.pr150_half_open` 分别标明期望。末日小数秒用例故意不同，不能拿候选期望宣称 main 已通过
- `VisitSummaryDateRangeTests.swift` 在基线 main 不存在；已读取 #150 版本，不凭文件名猜存在性

## 合成用例与运行

所有药名、剂量、风险、时间、UUID 均为合成，不表示真实用药建议或个人病史。JSON 是接力契约，非 App 导入格式或新持久化 Schema。

- `06_medications`：A 活跃期内；B 期内有记录、生成时归档；C 活跃仅期外；6 个期内药含长中文名、F/G 同名不同 UUID/规格；A 多来源、逻辑重复仍只计一个药/任务
- `05_medications / 04_medications / 00_medications`：分页阈值，0/4 不加空续页
- `event_only_scope`：剂量变化-only、活跃风险-only、已解决风险-only 的集合与文本差异
- `correction_before / correction_after`：同任务ID更正前后有效时间跨期界，前态 0，后态 1 药/1 已服用
- `selected_end_boundary`：23:59:59、23:59:59.5、次日 00:00、提前记录与跨开始日；main 3 药，#150 4 药

运行：

```sh
python3 checks/check_contract.py --mutation-checks
```

仅 Python 标准库，无网络、无安装。脚本验证期内 ID 集合、逻辑重复选择、顺序、数量、文本任务行、拟议首页/续页内容分配；不是 SwiftData、Swift 编译、PDFKit 或像素测试。期望写在静态 JSON 中，检查器不会重写期望；负控制验证常见错误会被拒绝。同名顺序未在原查询中指定，`OrderGroups` 接受该组内任一顺序，不能新加 UUID 排序。

## 原生实现设计底线

沿用 595×842 pt、36 pt 左右边距、22 pt 标题、14 pt 节标题、11 pt semibold 药名、9 pt 规格、10 pt 等宽数字与现有 primary/secondary/蓝/绿颜色。续页复用页眉、日期范围、页脚和圆角行；先测量真实字体的药名/规格高度，再换行与分页，不能缩小字号或尾截断冒充完整。原 `drawText` 会尾截断，`drawMultilineText` 在固定矩形中仍可能截断；仅换函数名不是修复。

第一页保留简洁布局；长名称压力项放在续页，原生另核对已有首页长名称呈现，若修正它会推挤风险卡则先报告范围，不偷偷改首页结构。续页行不能压到页脚。5/6 药在当前合成内容与现有字体预算下以一张续页为布局目标，最终页数由原生测量决定，不能保证任意文本固定三页。

SwiftUI 生成/预览/分享保留既有动态字号、44 pt 最小按钮和语义；PDF 固定字体不等于 Dynamic Type。必须单独检查中文可搜索/复制、阅读顺序、VoiceOver/QuickLook，不由颜色或截图推断可访问性通过。

下一步按 [NATIVE_ACCEPTANCE.md](NATIVE_ACCEPTANCE.md) 协调 #150 的串行整合，再接入真实 API 并执行原生验收。

## 本目录证据与校验

[evidence/run-receipt.json](evidence/run-receipt.json) 记录本发布版本的实际检查：8 份合成输入 × 2 个日期 profile 通过，10 项错误期望负控制被拒绝，1 项同名顺序控制通过。固定输入、静态 expected 和检查器与审核基准逐字节相同。收据只记录可复跑的合成结果；本目录不包含源码副本。

[evidence/source-manifest.json](evidence/source-manifest.json) 提供准确版本的公开源码 URL 与 Git blob SHA。源码版本不等于当前工作分支，需按原生 checkout 选择日期 profile。源审查不证明 native execution。

`MANIFEST.sha256` 绑定本目录内容文件，`DIRECTORY_SHA256.txt` 绑定该清单。此发布版本经过公开内容整理，清单指纹独立于先前审核包。目录内运行：

```sh
sha256sum -c MANIFEST.sha256
sha256sum -c DIRECTORY_SHA256.txt
python3 checks/check_contract.py --mutation-checks
```

macOS 可用 `shasum -a 256 -c` 替代 `sha256sum -c`。Python 3.9+ 及系统 IANA 时区数据是前提；无需 Python 第三方库、网络或安装步骤。检查器仅覆盖本组合成编号药名、整数剂量和上海时区，不证明通用日历/DST、SwiftData 排序或任意输入。
