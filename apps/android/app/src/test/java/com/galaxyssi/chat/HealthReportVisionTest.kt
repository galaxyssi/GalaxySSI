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
    private val target = HealthReportVisionTarget("desktop_fixture:codex", "Fixture Desktop",
        AgentTargetConfiguration("gpt-6-astra", AgentModelReasoningEffort.HIGH), "fixture-desktop", "fixture-route", "fixture-pair")

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
    @Test fun keepsValidRowsAndTracksWhyOtherRowsWereRejected() {
        val mixed = JSONArray().put(row.json()).put(row.json())
            .put(row.json().put("unit", "mmol/L"))
            .put(row.json().put("metric", "UNKNOWN"))
            .put(row.json().put("values", JSONObject().put("crp", "unclear")))
        val decoded = parse(report.json().put("rows", mixed))
        assertEquals(listOf(row), decoded.rows)
        assertTrue(decoded.partial)
        assertEquals(HealthReportRowIssue.entries.filterNot { it == HealthReportRowIssue.UNREADABLE }.associateWith { 1 }, decoded.rejected)
        assertEquals(decoded, HealthReportVisionResult.from(decoded.json()))
    }

    @Test fun separatesUnsupportedUnreadableAndAmbiguousResultsWithoutSavingUnknownRows() {
        fun empty(unsupported: Int, unreadable: Int, ambiguous: Boolean = false) =
            report.json().put("rows", JSONArray()).put("ambiguous_sample", ambiguous)
                .put("omitted", JSONObject().put("unsupported_metric", unsupported).put("unreadable", unreadable))
        for ((payload, problem) in listOf(
            empty(2, 0) to HealthReportReplyProblem.UNSUPPORTED_METRICS,
            empty(0, 2) to HealthReportReplyProblem.UNREADABLE_IMAGE,
            empty(0, 0, true) to HealthReportReplyProblem.AMBIGUOUS_SAMPLE,
            empty(81, 0) to HealthReportReplyProblem.FORMAT,
            report.json().put("ambiguous_sample", true) to HealthReportReplyProblem.FORMAT
        )) {
            assertEquals(problem, assertThrows(HealthReportInvalidReply::class.java) { parse(payload) }.problem)
        }
        val usable = parse(report.json().put("omitted", JSONObject().put("unsupported_metric", 3).put("unreadable", 2)))
        assertEquals(listOf(row), usable.rows)
        assertEquals(mapOf(HealthReportRowIssue.UNSUPPORTED_METRIC to 3, HealthReportRowIssue.UNREADABLE to 2), usable.rejected)
        assertEquals(usable, HealthReportVisionResult.from(usable.json()))
    }

    @Test fun expandedLabMetricsAcceptOnlyEquivalentUnitSpellingAndKeepDifferentObservationsSeparate() {
        val values = JSONArray()
        fun add(metric: HealthMetric, value: String, unit: String) {
            values.put(row.json().put("metric", metric.name)
                .put("values", JSONObject().put(metric.fields.single(), value)).put("unit", unit))
        }
        add(HealthMetric.RED_BLOOD_CELLS, "4.7", "\u00d710\u00b9\u00b2/l")
        add(HealthMetric.NEUTROPHIL_COUNT, "3.2", "10*3/\u03bcL")
        add(HealthMetric.NEUTROPHIL_PERCENT, "60", "%")
        add(HealthMetric.NEUTROPHIL_COUNT, "60", "%")
        add(HealthMetric.TOTAL_BILIRUBIN, "14", "\u00b5mol/l")
        add(HealthMetric.DIRECT_BILIRUBIN, "5", "umol/L")
        add(HealthMetric.UREA, "4.0", "mmol/L")
        add(HealthMetric.BLOOD_UREA_NITROGEN, "12", "mg/dl")
        val decoded = parse(report.json().put("rows", values))
        assertEquals(listOf("10^12/L", "10^3/uL", "%", "umol/L", "umol/L", "mmol/L", "mg/dL"), decoded.rows.map { it.unit })
        assertEquals(7, decoded.rows.map { it.metric }.toSet().size)
        assertEquals(mapOf(HealthReportRowIssue.INVALID_UNIT to 1), decoded.rejected)
        assertTrue(decoded.drafts(job, original, ZoneId.of("UTC"), now).all {
            HealthObservationPolicy.validate(it.copy(evidence = it.evidence!!.copy(confirmed = true)), now) == null
        })
    }

    @Test fun distinguishesEmptyOrUnsupportedReportsFromMalformedReplies() {
        assertEquals(HealthReportReplyProblem.NO_SUPPORTED_ROWS, assertThrows(HealthReportInvalidReply::class.java) {
            parse(report.json().put("rows", JSONArray()))
        }.problem)
        assertEquals(HealthReportReplyProblem.INVALID_ROWS, assertThrows(HealthReportInvalidReply::class.java) {
            parse(report.json().put("rows", JSONArray().put(row.json().put("unit", "mmol/L"))))
        }.problem)
        assertEquals(HealthReportReplyProblem.FORMAT, assertThrows(HealthReportInvalidReply::class.java) {
            HealthReportVisionResult.parse("{")
        }.problem)
        assertEquals(report, HealthReportVisionResult.parse("```JSON\r\n${report.json()}\r\n```"))
    }

    @Test fun pairedCodexReceivesOneImageWithConfiguredModelAndNoToolsOrChatHistory() {
        val request = HealthReportCodexRequest(target)
        val payload = request.payload(byteArrayOf(1, 2, 3))
        assertEquals("codex", payload.getString("agent_id"))
        assertEquals("screen_analysis", payload.getString("request_kind"))
        assertEquals("gpt-6-astra", payload.getJSONObject("agent_invocation").getString("model_id"))
        assertEquals("high", payload.getJSONObject("agent_invocation").getString("reasoning_effort"))
        val images = payload.getJSONArray("attachments")
        assertEquals(1, images.length())
        assertEquals("report.jpg", images.getJSONObject(0).getString("name"))
        assertEquals("AQID", images.getJSONObject(0).getString("data_b64"))
        assertFalse(payload.has("tools")); assertFalse(payload.has("history"))
        assertFalse(payload.toString().contains(original.name))
        assertThrows(IllegalArgumentException::class.java) {
            request.payload(ByteArray(HealthReportCodexGateway.MAX_IMAGE_BYTES + 1))
        }
    }

    @Test fun repliesMustMatchTheExactPairedDesktopAndRequest() {
        val request = HealthReportCodexRequest(target)
        val reply = request.payload(byteArrayOf(1)).put("source_message_id", request.source)
        assertTrue(request.matches(reply, target.desktopId))
        assertFalse(request.matches(reply, "other-desktop"))
        listOf("client_route_id", "conversation_id", "task_id", "turn_id", "contact_id", "source_message_id").forEach {
            assertFalse(request.matches(JSONObject(reply.toString()).put(it, "other"), target.desktopId))
        }
    }
}
