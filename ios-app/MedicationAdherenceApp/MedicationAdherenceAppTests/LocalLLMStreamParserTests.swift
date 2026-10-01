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

    @Test
    func caseMappingBeforeAnswerTagDoesNotMoveOriginalTextIndices() {
        for prefix in ["İ", "İİİ", "Ⱥ", "ẞ", "💊 İ"] {
            let parsed = LocalLLMStreamParser.parseComplete(prefix + "<AnSwEr>SAFE</AnSwEr>")
            #expect(parsed.thinking.isEmpty)
            #expect(parsed.answer == "SAFE", "Incorrect answer after Unicode prefix: \(prefix)")
        }
    }

    @Test
    func caseMappingWithinTaggedContentPreservesPayloadAndBoundaries() {
        for content in ["İ", "İİİ", "Ⱥ", "ẞ", "K", "💊 İ e\u{301}"] {
            let parsed = LocalLLMStreamParser.parseComplete(
                "<ThInK>" + content + "</ThInK><FiNaL>" + content + " SAFE</FiNaL>"
            )
            #expect(parsed.thinking == content, "Incorrect thinking payload: \(content)")
            #expect(parsed.answer == content + " SAFE", "Incorrect answer payload: \(content)")
        }
    }

    @Test
    func unicodeTaggedResponseMatchesCompleteParsingAcrossEveryChunkBoundary() {
        let text = "<THINK>İ Ⱥ ẞ</THINK><ANSWER>İ SAFE 💊</ANSWER>"
        for split in text.indices {
            var parser = LocalLLMStreamParser()
            var events = parser.consume(String(text[..<split]))
            events += parser.consume(String(text[split...]))
            let completed = parser.finish()
            events += completed.events
            let thinking = events.compactMap { event -> String? in
                if case .thinkingDelta(let delta) = event { return delta }
                return nil
            }.joined()
            let answer = events.compactMap { event -> String? in
                if case .answerDelta(let delta) = event { return delta }
                return nil
            }.joined()
            #expect(completed.thinking == "İ Ⱥ ẞ")
            #expect(completed.answer == "İ SAFE 💊")
            #expect(thinking == completed.thinking)
            #expect(answer == completed.answer)
        }
    }

    @Test
    func successiveUnicodeThinkingBlocksStayOutOfStreamedAnswer() {
        let text = "<think>İ</think><thought>Ⱥ</thought><answer>SAFE</answer>"
        var parser = LocalLLMStreamParser()
        var events: [LocalLLMGenerationEvent] = []
        for character in text {
            events += parser.consume(String(character))
        }
        let completed = parser.finish()
        events += completed.events
        let answer = events.compactMap { event -> String? in
            if case .answerDelta(let delta) = event { return delta }
            return nil
        }.joined()
        #expect(completed.thinking == "İ\n\nȺ")
        #expect(completed.answer == "SAFE")
        #expect(answer == "SAFE")
    }

    @Test
    func unclosedUnicodeThinkingCannotBecomeAnAnswer() {
        var parser = LocalLLMStreamParser()
        _ = parser.consume("<THOUGHT>İ Ⱥ ẞ")
        let completed = parser.finish()
        #expect(completed.thinking == "İ Ⱥ ẞ")
        #expect(completed.answer.isEmpty)
    }

    @Test
    func closedUnicodeThinkingWithoutAnAnswerDoesNotTrap() {
        for content in ["İ", "Ⱥ", "ẞ"] {
            let parsed = LocalLLMStreamParser.parseComplete("<think>" + content + "</think>")
            #expect(parsed.thinking == content)
            #expect(parsed.answer.isEmpty)
        }
    }

    @Test
    func existingControlAndReplacementCharacterSanitizationIsPreserved() {
        let parsed = LocalLLMStreamParser.parseComplete(
            "<think>A\u{0000}B\u{200D}C</think><answer>X\u{FFFD}Y</answer>"
        )
        #expect(parsed.thinking == "ABC")
        #expect(parsed.answer == "XY")
    }

    @Test
    func caseInsensitiveSearchDoesNotBroadenControlTagGrammar() {
        for (text, expected) in [
            ("<anſwer>FIRST</anſwer><answer>SECOND</answer>", "SECOND"),
            ("<ﬁnal>FIRST</ﬁnal><final>SECOND</final>", "SECOND"),
            ("<answer>A</anſwer>B</answer>", "A</anſwer>B"),
            ("<final>A</ﬁnal>B</final>", "A</ﬁnal>B")
        ] {
            let parsed = LocalLLMStreamParser.parseComplete(text)
            #expect(parsed.thinking.isEmpty)
            #expect(parsed.answer == expected)
        }
        for text in ["<anſwer>SAFE</anſwer>", "<ﬁnal>SAFE</ﬁnal>"] {
            var parser = LocalLLMStreamParser()
            for character in text {
                _ = parser.consume(String(character))
            }
            #expect(LocalLLMStreamParser.parseComplete(text).answer == text)
            #expect(parser.finish().answer == text)
        }
    }
}
