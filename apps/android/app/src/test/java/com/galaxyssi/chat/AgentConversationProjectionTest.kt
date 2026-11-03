package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentConversationProjectionTest {
    private fun row(id: String, user: Boolean, text: String, conversation: String = "research") = AgentTranscriptEntry(
        id = id, role = if (user) AgentTranscriptRole.USER else AgentTranscriptRole.ASSISTANT,
        text = text, timestampMillis = 1, conversationId = conversation, turnId = id.substringBefore('-'))
    private fun payload(value: String) = JSONObject(value.substringAfter('\n').substringBeforeLast('\n'))
    private fun records(value: String): List<JSONObject> = payload(value).getJSONArray("turns").let { array ->
        (0 until array.length()).map { array.getJSONObject(it) }
    }

    @Test fun longOriginalGoalAndMiddleConstraintsStayVerbatim() {
        val original = "Research online PhD programs.\n" + "Public background. ".repeat(700) +
            "\nMIDDLE REQUIREMENT: no residential attendance.\n" + "More background. ".repeat(700) +
            "\nEND REQUIREMENT: Chinese names and tuition."
        val rows = listOf(row("1-u", true, original), row("1-a", false, "University results. ".repeat(2000)),
            row("2-u", true, "Change the subject to AI only; keep the other requirements."),
            row("2-a", false, "New results. ".repeat(1000)), row("3-u", true, "Continue without adding conditions."))
        val block = AgentConversationProjection.encode("research", rows, 32_768, 100, false)
        assertEquals(original, records(block).first().getString("content"))
        assertTrue(records(block).all { it.getBoolean("content_complete") })
        assertEquals(rows.map { it.id }, records(block).map { it.getString("entry_id") })
    }

    @Test fun twentyThousandTokenHistoryIsNotPrecompactedByLegacyThreshold() {
        val rows = (1..7).flatMap { listOf(row("$it-u", true, "Find more online universities: round $it"),
            row("$it-a", false, "University information and verified source. ".repeat(300))) }
        val block = AgentConversationProjection.encode("research", rows, 32_768, 100, false)
        assertTrue(ConversationContextCompactor.estimateTokens(block) > 19_600)
        assertEquals(rows.map { it.text }, records(block).map { it.getString("content") })
        assertFalse(payload(block).getBoolean("history_omitted"))
    }

    @Test fun overflowingHistoryHasExplicitSourceReferencesNotInventedSummary() {
        val rows = (1..20).flatMap { listOf(row("$it-u", true, "Requirement $it " + "detail ".repeat(80)),
            row("$it-a", false, "Research result $it ".repeat(500))) }
        val block = AgentConversationProjection.encode("research", rows, 2_048, 101, true)
        assertTrue(ConversationContextCompactor.estimateTokens(block) <= 2_048)
        assertTrue(payload(block).getBoolean("history_omitted"))
        assertEquals("", payload(block).getString("summary"))
        assertEquals(AgentConversationRecallTool.ID, payload(block).getJSONObject("history_scope").getString("recall_tool"))
        assertTrue(records(block).any { it.getString("entry_id") == "20-u" })
        assertTrue(records(block).all { it.getString("source_sha256").length == 64 })
    }

    @Test fun oversizedUserMessageIsMarkedPartialAndRemainsRetrievable() {
        val source = row("1-u", true, "A long instruction with details. ".repeat(10000))
        val block = AgentConversationProjection.encode("research", listOf(source), 2_048, 100, false)
        val item = records(block).single()
        assertFalse(item.getBoolean("content_complete"))
        assertEquals(source.text.length, item.getInt("source_characters"))
        assertEquals(AgentLargeOutputPolicy.digest(source.text), item.getString("source_sha256"))
    }

    @Test fun foreignConversationAndProcessRecordsAreNotExposed() {
        val rows = listOf(row("u", true, "Current conversation"), row("foreign", true, "SECRET", "other"),
            row("p", false, "INTERNAL").copy(role = AgentTranscriptRole.PROCESS))
        val block = AgentConversationProjection.encode("research", rows, 2_048, 100, false)
        assertFalse(block.contains("SECRET"))
        assertFalse(block.contains("INTERNAL"))
        assertEquals(1, records(block).size)
    }

    @Test fun modelBudgetReservesOutputToolsAndSafetyMargin() {
        assertEquals(32_768, AgentConversationBudget.historyTokens(272_000, 16_000, "tool contract"))
        assertEquals(0, AgentConversationBudget.historyTokens(4_096, 2_048, "instruction ".repeat(3000)))
        assertTrue(AgentConversationBudget.historyTokens(16_000, 4_096, "tools") <
            AgentConversationBudget.historyTokens(64_000, 4_096, "tools"))
        assertTrue(AgentConversationBudget.historyTokens(64_000, 4_096, "tools ".repeat(20000)) < 32_768)
    }

    @Test fun unicodeAndJsonEscapingStayWithinMeasuredEnvelope() {
        val rows = (1..50).map { row("$it-u", true, "\"中文条件\"\n\\带转义文本。".repeat(100)) }
        val block = AgentConversationProjection.encode("research", rows, 4_096, 100, true)
        assertTrue(ConversationContextCompactor.estimateTokens(block) <= 4_096)
        assertEquals("research", payload(block).getString("conversation_id"))
    }

    @Test fun globalReferenceAndRedactionSurviveReprojection() {
        val block = AgentConversationProjection.encode("research", listOf(row("1-u", true,
            "Find online programs. api_key=SECRET123456")), 4_096, 100, false, "User prefers Chinese replies.")
        assertEquals("User prefers Chinese replies.", payload(block).getString("global_context"))
        assertFalse(block.contains("SECRET123456"))
        assertTrue(records(block).single().getBoolean("content_redacted"))
    }

    @Test fun promptCharacterEnvelopeIsReservedIndependentlyOfTokens() {
        val rows = (1..7).map { row("$it-u", true, "long English condition ".repeat(300)) }
        val block = AgentConversationProjection.encode("research", rows, 32_768, 100, true, maximumCharacters = 8_000)
        assertTrue(block.length <= 8_000)
        assertTrue(payload(block).getBoolean("history_omitted"))
    }

    @Test fun originalSourceRecallIsActuallyCallableBySupervisedProviders() {
        assertTrue(PhoneAssistantToolPolicy.allowsGeneralPhoneTool(AgentConversationRecallTool.ID))
        assertTrue(PhoneAssistantToolPolicy.allowsRemotePhoneTool(AgentConversationRecallTool.ID))
        assertTrue(AgentConversationRecallTool.ID in AgentPhoneNativeToolCatalog.defaultToolIds)
    }

    @Test(timeout = 5_000) fun legacySummaryDoesNotBacktrackAcrossLongOrdinaryProse() {
        val rows = listOf(ConversationContextItem("1", ConversationContextRole.USER, "Find online universities"),
            ConversationContextItem("2", ConversationContextRole.ASSISTANT,
                "Detailed factual university information without a filename extension. ".repeat(4000)))
        val summary = ConversationContextCompactor.handoffSummary(rows, "", 512)
        assertTrue(summary.contains("Find online universities"))
    }
}
