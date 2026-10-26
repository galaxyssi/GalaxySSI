package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentConversationHandoffRegressionTest {
    private val original = "Online doctoral programs in computer science or artificial intelligence"
    private val constraint = "Must study remotely; include tuition and Chinese university names"
    private fun entry(round: Int, user: Boolean, text: String) = AgentTranscriptEntry(
        id = "$round-$user", role = if (user) AgentTranscriptRole.USER else AgentTranscriptRole.ASSISTANT,
        text = text, timestampMillis = round * 2L + if (user) 0 else 1,
        conversationId = "research", turnId = "turn-$round", taskId = "task-$round")
    private fun history() = (1..7).flatMap { round -> listOf(
        entry(round, true, when (round) { 1 -> original; 2 -> constraint; else -> "Continue online programs $round" }),
        entry(round, false, "Round $round university results " + "Detailed factual university information. ".repeat(700))) }
    private fun payload(block: String) = JSONObject(block.substringAfter('\n').substringBeforeLast('\n'))
    private fun context() = AgentConversationContext("research", "", history(), false)

    @Test fun formerTwoThousandTokenFallbackKeepsOriginalGoalAndRecentPairs() {
        val block = context().asTransportBlock(2_048)
        val json = payload(block)
        assertTrue(ConversationContextCompactor.estimateTokens(block) <= 2_048)
        assertTrue(json.getString("summary").contains(original))
        assertTrue(json.getString("summary").contains(constraint))
        val turns = json.getJSONArray("turns")
        assertTrue(turns.length() >= 2)
        val last = (0 until turns.length()).map { turns.getJSONObject(it) }.filter { it.getString("turn_id") == "turn-7" }
        assertEquals(listOf("user", "assistant"), last.map { it.getString("role") })
        assertTrue(last.first().getString("content").contains("Continue online programs 7"))
    }

    @Test fun handoffKeepsGoalAcrossBudgetsAndChineseFollowUps() {
        for (budget in listOf(2_048, 4_096, 10_000, 32_768)) {
            val block = context().copy(turns = history() + entry(8, true, "继续找在线的，不要加条件")).asTransportBlock(budget)
            val json = payload(block)
            assertTrue("budget=$budget", ConversationContextCompactor.estimateTokens(block) <= budget)
            assertTrue(block.contains(original))
            assertTrue(block.contains(constraint))
            assertTrue(block.contains("继续找在线的，不要加条件"))
            assertEquals("research", json.getString("conversation_id"))
        }
    }

    @Test fun originalGoalSurvivesRepeatedSummaryWindows() {
        var summary = ""
        repeat(12) { round ->
            summary = ConversationContextCompactor.handoffSummary(listOf(
                ConversationContextItem("u-$round", ConversationContextRole.USER, if (round == 0) original else "Continue $round"),
                ConversationContextItem("a-$round", ConversationContextRole.ASSISTANT, "Previous outcome ".repeat(100))
            ), summary, 512)
            assertTrue("round=$round", summary.contains(original))
            assertTrue(ConversationContextCompactor.estimateTokens(summary) <= 512)
        }
    }

    @Test fun largeStaticPrefixCannotSliceConversationJson() {
        val handoff = context().asTransportBlock(4_096)
        val prompt = "Execution rules. ".repeat(2_000) + "Available phone tools:\n- search\n" +
            AgentSupervisedProjectPromptCodec.DYNAMIC_CONTEXT_HEADER + "User goal: continue\n" + handoff + "\nLatest observation: RESULT"
        val compact = AgentSupervisedProjectPromptCodec.preserveToolInventory(prompt, handoff.length + 5_000)
        assertTrue(compact.contains(handoff))
        assertTrue(compact.contains("User goal: continue"))
        assertTrue(compact.contains("Latest observation: RESULT"))
        assertTrue(compact.length <= handoff.length + 5_000)
    }

    @Test fun promiseIsNotDeliveryButActualAnswerAndRequestedAcknowledgementRemainValid() {
        assertFalse(AgentResponseSelfCheck.evaluate("不要加条件", "好的，不加任何额外条件，直接继续查找在线项目。").accepted)
        assertTrue(AgentResponseSelfCheck.evaluate("只回复好的", "好的").accepted)
        assertTrue(AgentResponseSelfCheck.evaluate("继续找在线的", "以下是另外三所大学及学费：A、B、C。").accepted)
    }
}
