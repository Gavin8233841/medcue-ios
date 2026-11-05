import Foundation
import MedicationAdherenceCore
import Testing
@testable import MedicationAdherenceApp

struct LocalMedicalAIClientTests {
    @Test
    func lowQualityInitialOutputIsRepairedExactlyOnce() async throws {
        let runtime = StubLocalMedicalRuntime(outputs: [
            "<answer>当前任务：复述提示词</answer>",
            "<answer>今天可以核对提醒并及时记录处理情况。</answer>"
        ])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )

        let response = try await client.respond(to: Self.request())

        #expect(response.message == "今天可以核对提醒并及时记录处理情况。")
        #expect(await runtime.callCount == 2)
    }

    @Test
    func failedRepairIsRejectedInsteadOfDisplayingUnstableText() async {
        let runtime = StubLocalMedicalRuntime(outputs: [
            "<answer>当前任务：复述提示词</answer>",
            "<answer>用户问题：仍然复述提示词</answer>"
        ])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )

        do {
            _ = try await client.respond(to: Self.request())
            Issue.record("Expected unstable response rejection")
        } catch let error as LocalMedicalAIError {
            #expect(error.diagnosticSummary == LocalMedicalAIError.unstableResponse.diagnosticSummary)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(await runtime.callCount == 2)
    }

    @Test(arguments: [
        "很抱歉，今天本地记录不足，无法根据现有记录判断完成情况。",
        "基于这些信息，今天可以核对提醒，并把处理情况保存到记录中。",
        "今天可以在记录中标注\"稍后\"，以便之后核对实际处理情况。"
    ])
    func safeWordingDoesNotTriggerASecondGeneration(answer: String) async throws {
        let runtime = StubLocalMedicalRuntime(outputs: [answer])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"), runtime: runtime
        )
        let response = try await client.respond(to: Self.request())
        #expect(response.message == answer)
        #expect(await runtime.callCount == 1)
    }

    @Test(arguments: [
        "今天请核对**提醒**，并补充__记录__。",
        "- 今天核对提醒。\n- 处理后补充记录。",
        "今天先核对提醒，记录重点 ### 核对处理情况。"
    ])
    func safeFormattingDoesNotTriggerRepair(answer: String) async throws {
        let runtime = StubLocalMedicalRuntime(outputs: [answer])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"), runtime: runtime
        )
        let response = try await client.respond(to: Self.request())
        #expect(response.message.contains("今天"))
        #expect(response.message.contains("记录"))
        if answer.contains("**") { #expect(response.message.contains("**提醒**")) }
        if answer.contains("__") { #expect(response.message.contains("__记录__")) }
        #expect(await runtime.callCount == 1)
    }

    @Test
    func factualTrendWithoutPrescribedSuggestionWordsIsAccepted() async throws {
        var request = Self.request()
        request.userMessage = "近期忽略或稍后趋势怎么样？"
        request.medicationSnapshots = [MedicalAIMedicationSnapshot(
            medication: Medication(displayName: "合成测试药", kind: .prescription, inputSource: .manual),
            doseEvents: [DoseEvent(scheduledDoseID: UUID(), status: .delayed, recordedAt: Date())]
        )]
        let answer = "过去14天有稍后1次，记录来自合成测试药。下次处理提醒后及时标记实际情况。"
        let runtime = StubLocalMedicalRuntime(outputs: [answer])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"), runtime: runtime
        )
        let response = try await client.respond(to: request)
        #expect(response.message == answer)
        #expect(await runtime.callCount == 1)
    }

    @Test(arguments: ["acetaminophen", "ibuprofen", "loratadine"])
    func unsharedEnglishMedicationIsRejected(name: String) async {
        let answer = "今天建议吃 \(name)，每次两片，并做好记录。"
        let runtime = StubLocalMedicalRuntime(outputs: [answer, answer])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"), runtime: runtime
        )
        do {
            _ = try await client.respond(to: Self.request())
            Issue.record("Unshared medication must not enter the accepted response")
        } catch let error as LocalMedicalAIError {
            #expect(error.diagnosticSummary == "unstable-response")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(await runtime.callCount == 2)
    }

    @Test(arguments: ["acetaminophen", "ibuprofen", "loratadine"])
    func sharedEnglishMedicationAdviceIsStillRejected(name: String) async {
        var request = Self.request()
        request.medicationSnapshots = [MedicalAIMedicationSnapshot(medication: Medication(
            displayName: name, kind: .overTheCounter, inputSource: .manual
        ))]
        let answer = "今天建议吃 \(name)，每次两片，并做好记录。"
        let runtime = StubLocalMedicalRuntime(outputs: [answer, answer])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"), runtime: runtime
        )
        do {
            _ = try await client.respond(to: request)
            Issue.record("Shared medication must not allow treatment advice")
        } catch let error as LocalMedicalAIError {
            #expect(error.diagnosticSummary == "unstable-response")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(await runtime.callCount == 2)
    }

    @Test(arguments: ["acetaminophen", "ibuprofen", "loratadine"])
    func englishMedicationNamesAreNormalProseWithOrWithoutSharedContext(name: String) async throws {
        for hasSharedContext in [false, true] {
            var request = Self.request()
            if hasSharedContext {
                request.medicationSnapshots = [MedicalAIMedicationSnapshot(medication: Medication(
                    displayName: name, kind: .overTheCounter, inputSource: .manual
                ))]
            }
            let answer = "\(name) 可以保留英文名称，核对药盒时请同时查看通用名和规格。"
            let runtime = StubLocalMedicalRuntime(outputs: [answer])
            let client = LocalMedicalAIClient(modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"), runtime: runtime)
            let response = try await client.respond(to: request)
            #expect(response.message == answer)
            #expect(await runtime.callCount == 1)
            let finalized = try MedicalAIResponseFinalizer().finalize(answer: response.message)
            #expect(!finalized.boundaryBlockedAction)
            #expect(finalized.displayMessage.contains(name))
        }
    }

    @Test(arguments: [
        "### 天气提示\n今天没有天气数据，可以先记录用药。",
        "本地记录：\n今天没有可用资料，请先核对已保存的记录。"
    ])
    func headingAndReadableBodySurvivePostprocessing(answer: String) async throws {
        let runtime = StubLocalMedicalRuntime(outputs: [answer])
        let client = LocalMedicalAIClient(modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"), runtime: runtime)
        let response = try await client.respond(to: Self.request())
        #expect(response.message == answer)
        #expect(await runtime.callCount == 1)
    }

    @Test
    func laterWarningIsNotDiscardedBySentenceOrCharacterLimit() async throws {
        let detail = String(repeating: "核对记录时应保留实际发生的时间和情况，", count: 14)
        let answer = "今天先查看提醒。核对是否已保存。\(detail)。不要自行停药或调整剂量。"
        let runtime = StubLocalMedicalRuntime(outputs: [answer])
        let client = LocalMedicalAIClient(modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"), runtime: runtime)
        let response = try await client.respond(to: Self.request())
        #expect(response.message == answer)
        #expect(response.message.hasSuffix("不要自行停药或调整剂量。"))
        #expect(await runtime.callCount == 1)
    }

    @Test
    func topicSynonymsDoNotRequireExactKeywordMatches() async throws {
        var request = Self.request()
        request.userMessage = "药盒和库存需要注意什么？"
        let answer = "当前资料不足，请先查看实物包装上的有效期并补充剩余数量。"
        let runtime = StubLocalMedicalRuntime(outputs: [answer])
        let client = LocalMedicalAIClient(modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"), runtime: runtime)
        let response = try await client.respond(to: request)
        #expect(response.message == answer)
        #expect(await runtime.callCount == 1)
    }

    @Test
    func actualChatBoundaryStillCutsHallucinatedNextTurn() {
        let policy = LocalMedicalResponsePolicy()
        let request = Self.request()
        let output = policy.postprocessLocalResponse("本地记录：今天没有可用资料。<|im_end|><|im_start|>assistant 建议服药10克", request: request)
        #expect(output == "本地记录：今天没有可用资料。")
    }

    @Test(arguments: ["hi", "你好", "睡眠对健康有什么作用？", "我今日的心率"])
    func everydayConversationDoesNotRequirePersonalRecords(question: String) {
        let policy = LocalMedicalResponsePolicy()
        var request = Self.request()
        request.userMessage = question
        let prompt = policy.buildLocalPrompt(for: request, answerPlan: policy.localAnswerPlan(for: request))
        #expect(prompt.contains(question))
        if question != "hi" && question != "你好" {
            #expect(prompt.contains("一般健康知识和日常交流可以直接回答"))
            #expect(prompt.contains("不要只回答“资料不足”"))
        }
        #expect(!policy.isLowQualityLocalResponse("你好！有什么健康或用药问题想聊聊吗？", request: request))
    }

    @Test(arguments: ["hi", "你能干些什么", "你能帮我做什么？", "介绍一下自己"])
    func unrelatedPersonalFactsAreNotSentForGeneralConversation(question: String) {
        let policy = LocalMedicalResponsePolicy()
        var request = Self.request()
        request.userMessage = question
        let plan = LocalMedicalAnswerPlan(focus: "一般问题", factSummary: "无关药品资料_SENTINEL", factGuidance: "", requiredFragments: [])
        let prompt = policy.buildLocalPrompt(for: request, answerPlan: plan)
        #expect(!prompt.contains("无关药品资料_SENTINEL"))
        #expect(prompt.contains(question))
    }

    @Test(arguments: ["我的药品有哪些？", "我有几种药？", "帮我整理复诊重点", "你能做什么？顺便看看今天的服药记录", "请解释我的服药记录", "如何理解我的风险卡"])
    func explicitPersonalRecordQuestionStillReceivesFacts(question: String) {
        let policy = LocalMedicalResponsePolicy()
        var request = Self.request()
        request.userMessage = question
        let plan = LocalMedicalAnswerPlan(focus: "药品清单", factSummary: "相关药品资料_SENTINEL", factGuidance: "", requiredFragments: [])
        #expect(policy.buildLocalPrompt(for: request, answerPlan: plan).contains("相关药品资料_SENTINEL"))
    }

    @Test
    func unsharedTodayRecordsAreUnknownRatherThanZero() {
        var request = Self.request()
        request.userMessage = "我今天吃了什么？"
        let policy = LocalMedicalResponsePolicy()
        let prompt = policy.buildLocalPrompt(for: request, answerPlan: policy.localAnswerPlan(for: request))
        #expect(prompt.contains("本次未共享药品或服药记录"))
        #expect(!prompt.contains("今天没有已记录为服用的条目"))
    }

    @Test
    func takenTodayUsesRecordedTakenEventsOnly() {
        var request = Self.request()
        request.userMessage = "我今天吃了什么？"
        request.authorization = MedicalAIUserAuthorization(grantedScopes: [.medicationProfile, .doseEvents])
        request.medicationSnapshots = [MedicalAIMedicationSnapshot(
            medication: Medication(displayName: "已服药名", kind: .overTheCounter, inputSource: .manual),
            doseEvents: [DoseEvent(scheduledDoseID: UUID(), status: .taken, recordedAt: Date())]),
            MedicalAIMedicationSnapshot(medication: Medication(displayName: "仅稍后药名", kind: .overTheCounter, inputSource: .manual),
            doseEvents: [DoseEvent(scheduledDoseID: UUID(), status: .delayed, recordedAt: Date())])]
        let policy = LocalMedicalResponsePolicy()
        let prompt = policy.buildLocalPrompt(for: request, answerPlan: policy.localAnswerPlan(for: request))
        #expect(prompt.contains("已服药名：今日已记录服用 1 次"))
        #expect(!prompt.contains("仅稍后药名"))
    }

    @Test(arguments: ["我不舒服", "我不好"])
    func discomfortPromptAsksAboutSymptomsWithoutUnrelatedMedication(question: String) {
        var request = Self.request()
        request.userMessage = question
        let policy = LocalMedicalResponsePolicy()
        let prompt = policy.buildLocalPrompt(for: request, answerPlan: LocalMedicalAnswerPlan(focus: "一般问题", factSummary: "无关药品事实_SENTINEL", factGuidance: "", requiredFragments: []))
        #expect(!prompt.contains("无关药品事实_SENTINEL"))
        #expect(prompt.contains("哪里不舒服、何时开始"))
    }

    @Test(arguments: ["我不舒服，胸痛已经半小时", "我不好判断今天吃了什么药"])
    func specificOrMixedQuestionIsNotTreatedAsVagueDiscomfort(question: String) {
        var request = Self.request()
        request.userMessage = question
        let policy = LocalMedicalResponsePolicy()
        let prompt = policy.buildLocalPrompt(for: request, answerPlan: policy.localAnswerPlan(for: request))
        #expect(!prompt.contains("本次没有提供具体症状"))
        #expect(!prompt.contains("用户表达不适，需要具体帮助而非寒暄"))
    }

    @Test
    func greetingWithPollutedHistoryDoesNotReplayOldAssistantText() {
        var request = Self.request()
        request.userMessage = "晚上好"
        request.conversation = [MedicalAIConversationTurn(role: "user", text: "well i feel illness"), MedicalAIConversationTurn(role: "assistant", text: "OLD_WELCOME_SENTINEL 以上内容仅用于用药风险提示和复诊沟通。")]
        let policy = LocalMedicalResponsePolicy()
        let prompt = policy.buildLocalPrompt(for: request, answerPlan: policy.localAnswerPlan(for: request))
        #expect(prompt.contains("晚上好"))
        #expect(!prompt.contains("OLD_WELCOME_SENTINEL"))
        #expect(!prompt.contains("已提供资料"))
    }

    @Test
    func followupKeepsHistoryButEndsWithCurrentQuestion() {
        var request = Self.request()
        request.userMessage = "把上一个回答整理成表格"
        request.conversation = [MedicalAIConversationTurn(role: "assistant", text: "HISTORY_SENTINEL")]
        let policy = LocalMedicalResponsePolicy()
        let prompt = policy.buildLocalPrompt(for: request, answerPlan: policy.localAnswerPlan(for: request))
        #expect(prompt.contains("HISTORY_SENTINEL"))
        #expect(prompt.hasSuffix("当前用户消息：把上一个回答整理成表格"))
        #expect(prompt.contains("背景资料结束。"))
    }

    @Test
    func englishMedicalQuestionRetainsRecordContextPath() {
        var request = Self.request()
        request.userMessage = "请用英语告诉我今天吃了什么药"
        let policy = LocalMedicalResponsePolicy()
        let prompt = policy.buildLocalPrompt(for: request, answerPlan: policy.localAnswerPlan(for: request))
        #expect(prompt.contains("Answer in English."))
        #expect(prompt.contains("本次未共享药品或服药记录"))
        #expect(!prompt.contains("本轮仅切换对话语言"))
    }

    @Test
    func explicitEnglishSwitchOverridesDefaultChinese() {
        var request = Self.request()
        request.userMessage = "lets speak English"
        let policy = LocalMedicalResponsePolicy()
        let prompt = policy.buildLocalPrompt(for: request, answerPlan: policy.localAnswerPlan(for: request))
        #expect(prompt.contains("Answer in English."))
        #expect(!prompt.contains("简短中文直接回答"))
    }

    @Test
    func generalQuestionIsNotForcedIntoTodayMedicationPrompt() {
        let policy = LocalMedicalResponsePolicy()
        var request = Self.request()
        request.userMessage = "按时记录用药有什么意义？"
        let prompt = policy.buildLocalPrompt(for: request, answerPlan: policy.localAnswerPlan(for: request))
        #expect(prompt.contains("按时记录用药有什么意义"))
        #expect(!prompt.contains("今日待处理药品是"))
        request.userMessage = "今天需要注意什么？"
        let emptyTodayPrompt = policy.buildLocalPrompt(for: request, answerPlan: policy.localAnswerPlan(for: request))
        #expect(!emptyTodayPrompt.contains("必须包含这些词"))
        #expect(emptyTodayPrompt.contains("资料"))
    }

    @Test(arguments: ["什么是 ibuprofen？", "怎样开始保存用药记录？", "请用一句话说明按时记录用药的意义。"])
    func genericQuestionsAreNotRoutedToMissedDoseTrend(question: String) {
        let policy = LocalMedicalResponsePolicy()
        var request = Self.request()
        request.userMessage = question
        let plan = policy.localAnswerPlan(for: request)
        let prompt = policy.buildLocalPrompt(for: request, answerPlan: plan)
        #expect(!plan.focus.contains("忽略或稍后趋势"))
        #expect(!prompt.contains("过去14天"))
        #expect(!prompt.contains(plan.factGuidance))
    }

    @Test
    func explicitConsultationTopicWinsOverSupportingRiskWords() {
        let policy = LocalMedicalResponsePolicy()
        var request = Self.request()
        request.userMessage = "请只基于 App 内授权共享的服药记录、剂量变化、风险提醒和药品信息，整理复诊时可以说明的重点。"
        #expect(policy.localAnswerPlan(for: request).focus.contains("复诊"))
    }

    @Test(arguments: [
        "本地记录不足，建议吃 ibuprofen，每次两片。",
        "- 建议吃 ibuprofen，每次两片。",
        "1. 建议吃 ibuprofen，每次两片。",
        "本地资料不足，请勿继续使用该药。"
    ])
    func treatmentCommandsFollowingCommaAreStillRejected(answer: String) async {
        let runtime = StubLocalMedicalRuntime(outputs: [answer, answer])
        let client = LocalMedicalAIClient(modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"), runtime: runtime)
        do {
            _ = try await client.respond(to: Self.request())
            Issue.record("Expected direct treatment command rejection")
        } catch let error as LocalMedicalAIError {
            #expect(error.diagnosticSummary == "unstable-response")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func streamedSafeWordingCompletesWithoutRepair() async throws {
        let answer = "很抱歉，今天本地记录不足，不能根据现有记录判断完成情况。"
        let runtime = StubLocalMedicalRuntime(outputs: [answer])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"), runtime: runtime
        )
        var completedAnswer: String?
        for try await event in client.streamResponse(to: Self.request()) {
            if case let .generationCompleted(answer, _) = event {
                completedAnswer = answer
            }
            if case .generationFailed = event {
                Issue.record("Safe streamed answer must not fail quality validation")
            }
        }
        #expect(completedAnswer == answer)
        #expect(await runtime.callCount == 1)
    }

    @Test(arguments: [
        "今天的记录是 {\"completed\": 3}。",
        "func 今日记录() { return 3 }",
        "今天建议暂停使用药品，并保存记录。"
    ])
    func structuredOrUnsafeOutputStillFailsAfterRepair(answer: String) async {
        let runtime = StubLocalMedicalRuntime(outputs: [answer, answer])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"), runtime: runtime
        )
        do {
            _ = try await client.respond(to: Self.request())
            Issue.record("Expected malformed or unsafe output to fail quality validation")
        } catch let error as LocalMedicalAIError {
            #expect(error.diagnosticSummary == "unstable-response")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(await runtime.callCount == 2)
    }

    @Test
    func streamingResponseRepairsPromptEchoBeforeCompletion() async throws {
        let runtime = StubLocalMedicalRuntime(
            outputs: ["<answer>今天可以核对提醒并及时记录处理情况。</answer>"],
            streamDeltas: ["<answer>当前任务：", "复述提示词</answer>"]
        )
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )

        var completedAnswers: [String] = []
        for try await event in client.streamResponse(to: Self.request()) {
            if case let .generationCompleted(answer, _) = event {
                completedAnswers.append(answer)
            }
        }

        #expect(completedAnswers == ["今天可以核对提醒并及时记录处理情况。"])
        #expect(await runtime.callCount == 1)
    }

    @Test
    func streamingFailedRepairNeverCompletesAResponse() async {
        let runtime = StubLocalMedicalRuntime(
            outputs: ["<answer>当前任务：仍然复述提示词</answer>"],
            streamDeltas: ["<answer>当前任务：复述提示词</answer>"]
        )
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )

        var completed = false
        do {
            for try await event in client.streamResponse(to: Self.request()) {
                if case .generationCompleted = event {
                    completed = true
                }
            }
            Issue.record("Expected unstable response rejection")
        } catch let error as LocalMedicalAIError {
            #expect(error.diagnosticSummary == LocalMedicalAIError.unstableResponse.diagnosticSummary)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(!completed)
        #expect(await runtime.callCount == 1)
    }

    @Test
    func singleAndStreamingResponsesPreserveTheSameThoughtBoundary() async throws {
        let generated = "<thought>先核对记录。</thought><final>今天可以核对提醒并及时记录处理情况。</final>"
        let singleClient = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: StubLocalMedicalRuntime(outputs: [generated])
        )
        let streamClient = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: StubLocalMedicalRuntime(outputs: [], streamDeltas: [generated])
        )

        let single = try await singleClient.respond(to: Self.request())
        var completed: (answer: String, thinking: String)?
        for try await event in streamClient.streamResponse(to: Self.request()) {
            if case let .generationCompleted(answer, thinking) = event {
                completed = (answer, thinking)
            }
        }

        #expect(single.message.contains("今天可以核对提醒并及时记录处理情况。"))
        #expect(single.message.contains("先核对记录。"))
        #expect(completed?.answer == "今天可以核对提醒并及时记录处理情况。")
        #expect(completed?.thinking == "先核对记录。")
    }

    @Test
    func fabricatedCompletionCountIsRepairedBeforeReturn() async throws {
        let runtime = StubLocalMedicalRuntime(outputs: [
            "<answer>甲药已完成999次，近期有忽略记录，建议核对。</answer>",
            "<answer>近期甲药有忽略记录，建议核对原因并继续记录。</answer>"
        ])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )

        let response = try await client.respond(to: Self.trendRequest())

        #expect(!response.message.contains("999"))
        #expect(response.message.contains("甲药有忽略记录"))
        #expect(await runtime.callCount == 2)
    }

    @Test
    func inconsistentMedicationCountIsRepairedBeforeReturn() async throws {
        let runtime = StubLocalMedicalRuntime(outputs: [
            "<answer>近期两种药品中甲药有忽略记录，建议核对原因。</answer>",
            "<answer>近期甲药有忽略记录，建议核对原因并继续记录。</answer>"
        ])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )

        let response = try await client.respond(to: Self.trendRequest())

        #expect(!response.message.contains("两种药品"))
        #expect(response.message.contains("甲药有忽略记录"))
        #expect(await runtime.callCount == 2)
    }

    @Test
    func equivalentTrendWordingDoesNotRequireHardcodedKeywords() async throws {
        let answer = "甲药这周有几次没有按计划服用，可以回看时间安排。"
        let runtime = StubLocalMedicalRuntime(outputs: [answer])
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"), runtime: runtime
        )
        let response = try await client.respond(to: Self.trendRequest())
        #expect(response.message == answer)
        #expect(await runtime.callCount == 1)
    }

    @Test
    func callerCancellationStopsGenerationBeforeAResponseIsReturned() async {
        let runtime = StubLocalMedicalRuntime(
            outputs: ["<answer>今天可以核对提醒并及时记录处理情况。</answer>"],
            delay: .seconds(5)
        )
        let client = LocalMedicalAIClient(
            modelURL: URL(fileURLWithPath: "/tmp/test-model.gguf"),
            runtime: runtime
        )
        let task = Task {
            try await client.respond(to: Self.request())
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }

    private static func request() -> MedicalAIRequest {
        MedicalAIRequest(
            kind: .chat,
            userMessage: "今天需要注意什么？",
            authorization: MedicalAIUserAuthorization(
                grantedScopes: [],
                grantedAt: Date(),
                expiresAt: Date().addingTimeInterval(300)
            )
        )
    }

    private static func trendRequest() -> MedicalAIRequest {
        let medication = Medication(
            displayName: "甲药",
            genericName: "合成测试药品",
            kind: .overTheCounter,
            form: "片剂",
            strength: "10 mg",
            inputSource: .demoData
        )
        return MedicalAIRequest(
            kind: .chat,
            userMessage: "近期忽略或稍后趋势如何？",
            authorization: MedicalAIUserAuthorization(grantedScopes: [.medicationProfile]),
            medicationSnapshots: [MedicalAIMedicationSnapshot(medication: medication)]
        )
    }
}

private actor StubLocalMedicalRuntime: LocalMedicalGenerating {
    private var outputs: [String]
    nonisolated let streamDeltas: [String]
    private let delay: Duration?
    private(set) var callCount = 0

    init(outputs: [String], streamDeltas: [String] = [], delay: Duration? = nil) {
        self.outputs = outputs
        self.streamDeltas = streamDeltas
        self.delay = delay
    }

    func generateResponse(prompt: String, modelURL: URL, maxTokens: Int) async throws -> String {
        callCount += 1
        if let delay {
            try await Task.sleep(for: delay)
        }
        guard !outputs.isEmpty else {
            throw LocalMedicalAIError.emptyResponse
        }
        return outputs.removeFirst()
    }

    nonisolated func generateResponseStream(
        prompt: String,
        modelURL: URL,
        maxTokens: Int
) -> LocalMedicalGenerationStream {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let worker = Task {
            do {
                if !streamDeltas.isEmpty {
                    for delta in streamDeltas { continuation.yield(delta) }
                } else {
                    let output = try await generateResponse(prompt: prompt, modelURL: modelURL, maxTokens: maxTokens)
                    let split = output.index(output.startIndex, offsetBy: output.count / 2)
                    continuation.yield(String(output[..<split]))
                    continuation.yield(String(output[split...]))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }

        }
        continuation.onTermination = { @Sendable _ in worker.cancel() }
        return LocalMedicalGenerationStream(stream: stream) { worker.cancel() }
    }
}
