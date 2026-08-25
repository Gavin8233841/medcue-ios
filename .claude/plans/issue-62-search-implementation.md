# Issue #62 实施计划：药品与风险列表搜索功能

## 背景与目标

为 MedicationsView 和 RisksView 添加符合 iOS 标准的局部搜索功能，让用户快速定位药品或风险警示。

**核心要求**：
- 使用 SwiftUI 原生 `.searchable()` 修饰符
- 搜索仅在内存中处理，不涉及网络、AI、持久化
- 支持中文子串匹配和英文不区分大小写匹配
- 保持现有分组、筛选、排序和导航功能

## 技术方案

### 1. 搜索规范化工具

创建 `SearchTextNormalizer.swift` 统一搜索文本规范化：

```swift
struct SearchTextNormalizer {
    // 规范化单个字符串：去除前后空白、统一大小写、全角转半角
    static func normalize(_ text: String) -> String
    
    // 分词：将查询字符串按空格分割为非空词
    static func tokenize(_ query: String) -> [String]
    
    // 匹配判断：检查所有查询词是否都命中目标文本
    static func matches(query: [String], in text: String) -> Bool
}
```

**规范化规则**：
- 去除前后空白字符
- 统一转小写（英文）
- 全角转半角（数字、字母）
- 保留中文原样
- 去除可忽略标点（.,、。，等）

### 2. 药品搜索索引

创建 `MedicationSearchIndex.swift`：

```swift
struct MedicationSearchIndex {
    let medication: StoredMedication
    let searchableText: String  // 预先规范化的可搜索文本
    
    init(medication: StoredMedication) {
        // 拼接：显示名称、通用名、规格、剂型、药品类别、备注
        let fields = [
            medication.displayName,
            medication.genericName,
            medication.strength,
            medication.form,
            medication.kind.displayName,
            medication.notes
        ]
        self.medication = medication
        self.searchableText = SearchTextNormalizer.normalize(
            fields.joined(separator: " ")
        )
    }
    
    func matches(query: [String]) -> Bool {
        SearchTextNormalizer.matches(query: query, in: searchableText)
    }
}
```

### 3. 风险搜索索引

创建 `RiskSearchIndex.swift`：

```swift
struct RiskSearchIndex {
    let card: StoredRiskCard
    let searchableText: String  // 预先规范化的可搜索文本
    
    init(card: StoredRiskCard, medicationName: String) {
        // 拼接：药品名、警示标题、警示正文、风险分类、严重程度、来源标题、来源片段
        let fields = [
            medicationName,
            card.title,
            card.message,
            card.kind.displayName,
            card.severity.displayName,
            card.sourceTitle,
            card.sourceExcerpt
        ]
        self.card = card
        self.searchableText = SearchTextNormalizer.normalize(
            fields.joined(separator: " ")
        )
    }
    
    func matches(query: [String]) -> Bool {
        SearchTextNormalizer.matches(query: query, in: searchableText)
    }
}
```

### 4. MedicationsView 集成

**修改点**：
1. 添加 `@State private var searchText = ""`
2. 计算属性 `filteredSnapshot` 根据搜索词过滤快照的 medications
3. 在 `.navigationTitle("药品")` 后添加 `.searchable()`
4. 空结果时显示 `ContentUnavailableView`

**关键代码**：
```swift
// 规范化查询
private var searchTokens: [String] {
    SearchTextNormalizer.tokenize(searchText)
}

// 过滤后的快照（保持原 snapshot 结构，只过滤 medications）
private var filteredMedications: [StoredMedication] {
    let tokens = searchTokens
    guard !tokens.isEmpty else {
        return snapshot.medications
    }
    let indexes = snapshot.medications.map { MedicationSearchIndex(medication: $0) }
    return indexes.filter { $0.matches(query: tokens) }.map(\.medication)
}

// 在 body 中使用 filteredMedications 替代 snapshot.medications
.searchable(text: $searchText, prompt: "搜索药品名称、通用名、规格或剂型")
```

### 5. RisksView 集成

**修改点**：
1. 添加 `@State private var searchText = ""`
2. 计算属性过滤 `riskSnapshot` 的活动和归档风险卡
3. 在 `.navigationTitle("风险复核")` 后添加 `.searchable()`
4. 空结果时显示 `ContentUnavailableView`

**关键代码**：
```swift
private var searchTokens: [String] {
    SearchTextNormalizer.tokenize(searchText)
}

private var filteredSnapshot: RiskDisplaySnapshot {
    let tokens = searchTokens
    guard !tokens.isEmpty else {
        return riskSnapshot
    }
    
    // 构建索引并过滤
    let activeIndexes = riskSnapshot.medicationRiskSections.flatMap { section in
        section.cards.map { card in
            RiskSearchIndex(
                card: card,
                medicationName: riskSnapshot.medicationName(for: card)
            )
        }
    }
    let archivedIndexes = riskSnapshot.archivedMedicationRiskSections.flatMap { section in
        section.cards.map { card in
            RiskSearchIndex(
                card: card,
                medicationName: riskSnapshot.medicationName(for: card)
            )
        }
    }
    
    let filteredActiveCards = activeIndexes.filter { $0.matches(query: tokens) }.map(\.card)
    let filteredArchivedCards = archivedIndexes.filter { $0.matches(query: tokens) }.map(\.card)
    
    // 重建 snapshot（保持分组结构）
    return RiskDisplaySnapshot(
        filteredActiveCards: filteredActiveCards,
        filteredArchivedCards: filteredArchivedCards,
        medicationNamesByID: riskSnapshot.medicationNamesByID,
        cardsByGroup: riskSnapshot.cardsByGroup,
        isPlaceholder: false
    )
}

.searchable(text: $searchText, prompt: "搜索药品、警示内容或来源")
```

## 测试策略

### 1. 单元测试 - `SearchTextNormalizerTests.swift`

```swift
@Test func normalize_removesWhitespace()
@Test func normalize_convertsToLowercase()
@Test func normalize_convertsFullwidthToHalfwidth()
@Test func normalize_removesIgnorablePunctuation()
@Test func tokenize_splitsOnWhitespace()
@Test func tokenize_filtersEmptyTokens()
@Test func matches_chineseSubstring()
@Test func matches_englishCaseInsensitive()
@Test func matches_multipleTokensAllRequired()
@Test func matches_mixedChineseEnglishNumber()
```

### 2. 单元测试 - `MedicationSearchIndexTests.swift`

```swift
@Test func searchIndex_includesAllFields()
@Test func searchIndex_matchesDisplayName()
@Test func searchIndex_matchesGenericName()
@Test func searchIndex_matchesStrength()
@Test func searchIndex_matchesForm()
@Test func searchIndex_matchesMedicationKind()
@Test func searchIndex_matchesNotes()
@Test func searchIndex_multipleTokensAllMatch()
@Test func searchIndex_emptyQueryMatchesAll()
```

### 3. 单元测试 - `RiskSearchIndexTests.swift`

```swift
@Test func searchIndex_includesAllFields()
@Test func searchIndex_matchesMedicationName()
@Test func searchIndex_matchesTitle()
@Test func searchIndex_matchesMessage()
@Test func searchIndex_matchesSourceTitle()
@Test func searchIndex_matchesRiskKind()
@Test func searchIndex_matchesSeverity()
```

### 4. UI 测试 - `MedicationSearchUITests.swift`

```swift
@Test func medicationSearch_emptyQuery_showsAll()
@Test func medicationSearch_chineseQuery_filtersCorrectly()
@Test func medicationSearch_englishQuery_caseInsensitive()
@Test func medicationSearch_clearButton_restoresAll()
@Test func medicationSearch_noResults_showsEmptyState()
@Test func medicationSearch_preservesLifecycleFilter()
@Test func medicationSearch_navigateToDetail()
```

### 5. UI 测试 - `RiskSearchUITests.swift`

```swift
@Test func riskSearch_emptyQuery_showsAll()
@Test func riskSearch_filtersByMedicationName()
@Test func riskSearch_filtersByRiskContent()
@Test func riskSearch_clearButton_restoresAll()
@Test func riskSearch_noResults_showsEmptyState()
@Test func riskSearch_preservesGrouping()
```

## 实施顺序

### 阶段 1：搜索基础设施（2 个文件）
1. `SearchTextNormalizer.swift` - 规范化工具
2. `SearchTextNormalizerTests.swift` - 单元测试

**验收**：所有规范化和匹配测试通过

### 阶段 2：药品搜索（3 个文件）
1. `MedicationSearchIndex.swift` - 药品搜索索引
2. `MedicationSearchIndexTests.swift` - 单元测试
3. 修改 `MedicationsView.swift` - 集成搜索

**验收**：药品搜索功能工作，生命周期筛选保持正常

### 阶段 3：风险搜索（3 个文件）
1. `RiskSearchIndex.swift` - 风险搜索索引
2. `RiskSearchIndexTests.swift` - 单元测试
3. 修改 `RisksView.swift` - 集成搜索

**验收**：风险搜索功能工作，分组和归档保持正常

### 阶段 4：UI 测试和完善（2 个文件）
1. `MedicationSearchUITests.swift` - UI 测试
2. `RiskSearchUITests.swift` - UI 测试

**验收**：UI 测试通过，VoiceOver 标识正确

## 文件所有权冲突检查

根据 Issue 要求，需要确认：
- ✅ `MedicationsView.swift` - **检查 PR #58 是否仍在修改此文件**
- ✅ `project.pbxproj` - **检查 PR #60 是否仍在修改此文件**
- ✅ `RisksView.swift` - 无已知冲突

**行动**：
1. 确认 PR #58 和 #60 的状态
2. 如果有冲突，等待这些 PR 合并或协调修改范围

## 性能考虑

- 搜索索引在内存中构建，每次搜索重新过滤
- 药品列表通常 < 50 个，风险卡通常 < 100 个
- 线性过滤足够快（< 10ms）
- 不需要持久化索引或复杂的数据结构

## 隐私和安全

- ✅ 搜索查询仅在内存中处理
- ✅ 不记录、不持久化、不上传
- ✅ 不发送给 AI
- ✅ 不添加 Spotlight 索引
- ✅ 使用合成测试数据，不包含真实医疗信息

## 退出条件

- [x] 搜索规范化工具完成并测试
- [x] 药品搜索索引完成并测试
- [x] 风险搜索索引完成并测试
- [x] MedicationsView 集成搜索
- [x] RisksView 集成搜索
- [x] 所有单元测试通过
- [x] UI 测试覆盖关键场景
- [x] VoiceOver 标识正确
- [x] `tools/verify-native.sh --quick` 通过
- [x] 完整 CI 通过
- [x] 文档更新（如需要）
