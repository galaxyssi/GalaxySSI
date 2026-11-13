package com.galaxyssi.chat

import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthReportVisionTest {
    private val id = UUID.randomUUID().toString()
    private val original = HealthOriginal(id, UUID.randomUUID().toString(), "report.png", "image/png", 10, "a".repeat(64), 1, "unused", "file")
    private val job = HealthImportJob(id, "", 1, originalId = id, mime = "image/png", state = HealthImportState.REVIEW)
    private val now = Instant.parse("2026-11-13T00:00:00Z").toEpochMilli()
    private val row = HealthVisionRow(HealthMetric.CRP, mapOf("crp" to "<0.50"), "mg/L", "0-5", "CRP <0.50 mg/L 0-5")
    private val report = HealthReportVisionResult(listOf(row), "2026-11-12 08:30+08:00", false)
    private fun parse(value: JSONObject) = HealthReportVisionResult.parse(value.toString())
    private fun target(style: String, host: String = "example.invalid") =
        HealthAnalysisTarget("fixture", "Fixture", "vision", "https://$host/model", style, host, host)

    @Test fun typedValuesAndOriginalEvidenceRemainUnconfirmed() {
        val draft = parse(report.json()).drafts(job, original, ZoneId.of("UTC"), now).single()
        assertEquals("<0.50", draft.values["crp"])
        assertEquals("mg/L", draft.unit)
        assertEquals("0-5", draft.reference)
        assertEquals(Instant.parse("2026-11-12T00:30:00Z").toEpochMilli(), draft.measuredAt)
        val evidence = draft.evidence!!
        assertEquals(HealthRecognition.MODEL, evidence.recognition)
        assertEquals(original.sha256, evidence.sha256)
        assertTrue(evidence.boxes.isEmpty())
        assertFalse(evidence.confirmed)
        assertTrue(evidence.valid())
        assertEquals(HealthValidationIssue.UNCONFIRMED_SOURCE, HealthObservationPolicy.validate(draft, now)!!.issue)
    }

    @Test fun unknownUnitsAndIncompleteOrFutureDatesStayUnset() {
        listOf("", "2026-11-12", "2026-11-14 00:00", "2026-02-31 09:00").forEach { date ->
            val draft = report.copy(rows = listOf(row.copy(unit = "")), collected = date).drafts(job, original, ZoneId.of("UTC"), now).single()
            assertEquals("", draft.unit); assertEquals(0L, draft.measuredAt)
        }
        val date = report.copy(collected = "2025-11-02 01:30")
        assertEquals(0L, date.drafts(job, original, ZoneId.of("America/New_York"), now).single().measuredAt)
    }

    @Test fun schemaRejectsUnknownFieldsUnsupportedUnitsNumbersAndInvalidRows() {
        val altered = listOf(row.json().put("unit", "mmol/L"), row.json().put("values", JSONObject().put("crp", 0.5)),
            row.json().put("values", JSONObject().put("alt", "12")), row.json().put("metric", "UNKNOWN"),
            row.json().put("diagnosis", "untrusted"), row.json().put("values", JSONObject().put("crp", "unclear")))
        altered.forEach { value ->
            assertThrows(HealthAnalysisInvalidReply::class.java) { parse(report.json().put("rows", JSONArray().put(value))) }
        }
        assertThrows(HealthAnalysisInvalidReply::class.java) { parse(report.json().put("rows", JSONArray())) }
        assertThrows(HealthAnalysisInvalidReply::class.java) { parse(report.json().put("partial", "false")) }
        assertThrows(HealthAnalysisInvalidReply::class.java) { HealthReportVisionResult.parse(report.json().toString() + "{}") }
    }

    @Test fun persistedVisionIsAdditiveAndOldPagesStayReadable() {
        val local = HealthOcrPage(1, 120, 240, listOf(HealthOcrLine("Local OCR result")))
        val merged = local.copy(vision = report)
        assertEquals(local, HealthOcrPage.from(local.json()))
        assertEquals(merged, HealthOcrPage.from(merged.json()))
        assertEquals(job, HealthImportJob.from(job.json()))
        assertTrue(HealthImportJob.from(job.copy(modelRecognized = true).json()).modelRecognized)
    }

    @Test fun allSupportedApiStylesCarryOneImageAndNoToolsOrChatHistory() {
        val image = byteArrayOf(1, 2, 3)
        val openAi = HealthReportVisionProvider.body(target("openai", "api.openai.com"), image)
        assertFalse(openAi.getBoolean("store")); assertFalse(openAi.getBoolean("stream"))
        val messages = openAi.getJSONArray("messages")
        assertEquals(2, messages.length())
        assertEquals("data:image/jpeg;base64,AQID", messages.getJSONObject(1).getJSONArray("content").getJSONObject(0)
            .getJSONObject("image_url").getString("url"))
        val anthropic = HealthReportVisionProvider.body(target("anthropic"), image)
        assertEquals("AQID", anthropic.getJSONArray("messages").getJSONObject(0).getJSONArray("content").getJSONObject(0)
            .getJSONObject("source").getString("data"))
        val gemini = HealthReportVisionProvider.body(target("gemini"), image)
        assertEquals("AQID", gemini.getJSONArray("contents").getJSONObject(0).getJSONArray("parts").getJSONObject(0)
            .getJSONObject("inline_data").getString("data"))
        listOf(openAi, anthropic, gemini).forEach { assertFalse(it.has("tools")); assertFalse(it.has("history")) }
    }
}
