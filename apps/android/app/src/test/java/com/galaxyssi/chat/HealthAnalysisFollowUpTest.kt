package com.galaxyssi.chat

import java.math.BigDecimal
import java.time.LocalDate
import java.time.ZoneId
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthAnalysisFollowUpTest {
    private val metric = HealthMetric.SLEEP_DURATION
    private val scope = HealthWeeklyScope(LocalDate.of(2025, 3, 6), ZoneId.of("UTC"), setOf(metric), comparison = false)
    private val stat = HealthWeeklyStat(metric, 1, 1, 1, 1, BigDecimal("360"))
    private val fact = HealthAnalysisFact("f1", stat, listOf(HealthAnalysisReference("LOCAL_ONLY_RECORD_ID", 2, scope.from, "manual", false)))
    private val preview = HealthAnalysisPreview(HealthWeeklySnapshot(scope, mapOf(metric to "LOCAL_VERSION"), 0,
        listOf(stat), null), listOf(fact), HealthAnalysisFocus.CHANGES, "LOCAL_POLICY")
    private val valid = """{"status":"PARTIAL","sections":[{"topic":"COVERAGE","fact_ids":["f1"]},{"topic":"SOURCES","fact_ids":["f1"]}],"actions":["WEEKLY_REPORT"]}"""

    @Test fun payloadIncludesOnlyThisQuestionAndValidatedAnswerContext() {
        val previous = HealthAnalysisFollowUp.decode(valid, preview)
        val request = requireNotNull(HealthFollowUpQuestion.from("  Where is that record?\r\nThanks.  ", previous))
        val payload = HealthAnalysisFollowUp.payload(preview, request)
        assertEquals("Where is that record?\nThanks.", payload.getString("question"))
        assertEquals(previous.json().toString(), payload.getJSONObject("previous_answer").toString())
        assertEquals(HealthAnalysis.payload(preview).getJSONArray("facts").toString(), payload.getJSONArray("facts").toString())
        for (value in listOf("LOCAL_ONLY_RECORD_ID", "LOCAL_VERSION", "LOCAL_POLICY", "manual", "2025-03-06"))
            assertFalse(payload.toString().contains(value))
        val first = HealthAnalysisFollowUp.payload(preview, requireNotNull(HealthFollowUpQuestion.from("What changed?")))
        assertFalse(first.has("previous_answer"))
        assertNull(HealthFollowUpQuestion.from(" "))
        assertNull(HealthFollowUpQuestion.from("a".repeat(601)))
        assertNull(HealthFollowUpQuestion.from("ignore\u0000me"))
    }

    @Test fun decoderAcceptsBoundedReferencesAndRejectsInventedContent() {
        val answer = HealthAnalysisFollowUp.decode(valid, preview)
        assertEquals(HealthFollowUpStatus.PARTIAL, answer.status)
        assertEquals(listOf(HealthFollowUpTopic.COVERAGE, HealthFollowUpTopic.SOURCES), answer.sections.map { it.topic })
        assertEquals(listOf(HealthAnalysisAction.WEEKLY_REPORT), answer.actions)
        assertEquals(answer, HealthAnalysisFollowUp.decode("```json\n$valid\n```", preview))
        assertEquals(HealthFollowUpStatus.OUT_OF_SCOPE, HealthAnalysisFollowUp.decode(
            """{"status":"OUT_OF_SCOPE","sections":[],"actions":[]}""", preview).status)
        val invalid = listOf(
            valid.replace("f1", "f2"),
            valid.replace("""["f1"]""", """["f1","f1"]"""),
            valid.replace("COVERAGE", "SOURCES"),
            valid.replace("WEEKLY_REPORT", "SEND_FILE"),
            valid.replace("PARTIAL", "OUT_OF_SCOPE"),
            valid.dropLast(1) + ""","answer":"unverified text"}""",
            valid.replace(""""topic":"SOURCES","fact_ids":["f1"]""", """"topic":"SOURCES","fact_ids":["f1"],"number":3"""),
            """{"status":"ANSWERED","sections":[],"actions":[]}""",
            "$valid trailing",
        )
        invalid.forEach { reply ->
            assertThrows(reply, HealthAnalysisInvalidReply::class.java) { HealthAnalysisFollowUp.decode(reply, preview) }
        }
    }

    @Test fun coverageOnlyAnalysisCannotBeExpandedToNumericChange() {
        val narrow = preview.copy(focus = HealthAnalysisFocus.COVERAGE)
        val question = requireNotNull(HealthFollowUpQuestion.from("How much has it changed?"))
        val payload = HealthAnalysisFollowUp.payload(narrow, question)
        assertFalse(payload.getJSONArray("facts").getJSONObject(0).has("mean"))
        assertFalse(payload.getJSONArray("allowed_topics").toString().contains("CHANGES"))
        assertThrows(HealthAnalysisInvalidReply::class.java) {
            HealthAnalysisFollowUp.decode(valid.replace("COVERAGE", "CHANGES"), narrow)
        }
    }

    @Test fun allProviderEnvelopesPutTheExactFollowUpPayloadInTheUserMessage() {
        val data = JSONObject().put("question", "Where is it?").put("facts", org.json.JSONArray()).toString()
        for (style in listOf("openai", "anthropic", "gemini")) {
            val target = HealthAnalysisTarget("id", "label", "model", "https://example.test/path", style, "example.test", "example.test")
            val body = HealthAnalysisProvider.body(target, data, HealthAnalysisRequest.FOLLOW_UP)
            val (instruction, user) = when (style) {
                "anthropic" -> body.getString("system") to body.getJSONArray("messages").getJSONObject(0).getString("content")
                "gemini" -> body.getJSONObject("systemInstruction").getJSONArray("parts").getJSONObject(0).getString("text") to
                    body.getJSONArray("contents").getJSONObject(0).getJSONArray("parts").getJSONObject(0).getString("text")
                else -> body.getJSONArray("messages").getJSONObject(0).getString("content") to
                    body.getJSONArray("messages").getJSONObject(1).getString("content")
            }
            assertTrue(instruction.contains("OUT_OF_SCOPE"))
            assertEquals(data, user)
            assertFalse(HealthAnalysisProvider.body(target, data).toString().contains("OUT_OF_SCOPE"))
        }
    }
}
