import Testing
@testable import MedicationAdherenceApp

struct LocalLLMStreamParserTests {
    @Test
    func splitTagsAcrossChunksEmitThinkingAndAnswerWithoutControlTokens() {
        var parser = LocalLLMStreamParser()
        let firstEvents = parser.consume("<thi")
        let secondEvents = parser.consume("nk>先核对记录。</think><ans")
        let thirdEvents = parser.consume("wer>今天按提醒核对。</answer>")
        let completed = parser.finish()

        #expect(firstEvents.isEmpty)
        #expect(!secondEvents.isEmpty)
        #expect(!thirdEvents.isEmpty)
        #expect(completed.thinking == "先核对记录。")
        #expect(completed.answer == "今天按提醒核对。")
        #expect(!completed.answer.contains("<answer>"))
    }

    @Test
    func incompleteThinkingNeverLeaksIntoFinalAnswer() {
        var parser = LocalLLMStreamParser()
        _ = parser.consume("<think>正在分析本地记录")

        let completed = parser.finish()

        #expect(completed.thinking == "正在分析本地记录")
        #expect(completed.answer.isEmpty)
    }

    @Test
    func thoughtAndFinalTagsHaveOneParsedBoundary() {
        var parser = LocalLLMStreamParser()
        _ = parser.consume("<thought>先核对记录。</thought><final>今天按提醒核对。</final>")

        let completed = parser.finish()

        #expect(completed.thinking == "先核对记录。")
        #expect(completed.answer == "今天按提醒核对。")
    }

    @Test
    func successiveThinkingTagsStayOutOfTheAnswer() {
        var parser = LocalLLMStreamParser()
        _ = parser.consume("<think>先核对。</think><thought>再整理。</thought>今天按提醒核对。")

        let completed = parser.finish()

        #expect(completed.thinking == "先核对。\n\n再整理。")
        #expect(completed.answer == "今天按提醒核对。")
    }

    @Test
    func formalAnswerMarkerDoesNotEnterReasoning() {
        var parser = LocalLLMStreamParser()
        _ = parser.consume("分析：先核对记录。正式回答：今天按提醒核对。")

        let completed = parser.finish()

        #expect(completed.thinking == "分析：先核对记录。")
        #expect(completed.answer == "今天按提醒核对。")
    }
}
