package com.galaxyssi.chat

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationNumericFeedbackTest {
    private class Fixture {
        val workspace = CollaborationResearchWorkspace(CollaborationEvolutionTest.Rows())
        val access = CollaborationWorkspaceAccess("group", "run", "turn", 10, "reader", "reader")
        fun publish(id: String, round: Long, count: Int = 120, model: String = """{"constant":0}""", previous: JSONObject? = null): JSONObject {
            val receipt = workspace.publish(access.copy(round = round, nodeId = id, personId = id),
                CollaborationNumericFeedbackFixture.raw(id, count, model, previous))
            assertEquals(receipt.toString(), "recorded", receipt.getString("status"))
            return receipt.getJSONArray("revisions").getJSONObject(0)
        }
        fun record(ref: JSONObject) = workspace.read(access, ref.getString("object_id"), ref.getInt("revision"))!!
    }
    private fun allPages(record: JSONObject, filter: String): JSONObject {
        val text = StringBuilder(); var cursor = ""; var pages = 0
        do {
            val page = CollaborationNumericFeedback.page(record, CollaborationNumericFeedbackFixture.input(record, filter, cursor))
            val part = page.getString("content")
            assertTrue(part.length <= 8000); text.append(part)
            cursor = if (page.isNull("next_cursor")) "" else page.getString("next_cursor")
            assertTrue(++pages < 1000)
        } while (cursor.isNotEmpty())
        return JSONObject(text.toString())
    }
    private fun reject(record: JSONObject, input: Map<String, Any?>) {
        try { CollaborationNumericFeedback.page(record, input); fail("Expected invalid feedback request") }
        catch (_: IllegalArgumentException) { }
    }

    @Test fun largestTrialHasCompactReceiptButAllOriginalChecksSurvive() {
        val f = Fixture(); val ref = f.publish("baseline", 1, count = 4096); val saved = f.record(ref)
        val original = saved.toString()
        val receipt = ref.getJSONObject("host_evolution")
        assertTrue(ref.toString().length < 4000)
        println("NUMERIC_FEEDBACK_SIZE cases=4096 compact=${ref.toString().length} full_host_receipt=" +
            JSONObject(ref.toString()).put("host_evolution", saved.getJSONObject("host_evolution")).toString().length)
        assertFalse(receipt.getJSONObject("evaluation").has("checks"))
        assertEquals(4095, receipt.getJSONObject("evaluation").getInt("failed_cases"))
        val recovered = allPages(saved, "all").getJSONArray("cases")
        assertEquals(4096, recovered.length())
        assertEquals(original, saved.toString())
        repeat(recovered.length()) { i ->
            val row = recovered.getJSONObject(i)
            assertEquals("case-$i", row.getString("id"))
            assertEquals(saved.getJSONObject("body").getJSONObject("numeric_model_trial").getJSONObject("validator")
                .getJSONArray("cases").getJSONObject(i).getJSONObject("input").toString(), row.getJSONObject("input").toString())
        }
    }

    @Test fun receiptAndDirectoryDoNotRepeatComparisonCaseArrays() {
        val f = Fixture(); val first = f.publish("baseline", 1, 4096)
        val next = f.publish("candidate", 2, 4096, CollaborationNumericFeedbackFixture.SQUARE, first)
        val comparison = next.getJSONObject("host_evolution").getJSONObject("comparison")
        assertEquals(4095, comparison.getInt("improved_case_count"))
        assertFalse(comparison.has("improved_case_ids"))
        assertTrue(next.toString().length < 6000)
        val full = f.record(next)
        assertEquals(4095, full.getJSONObject("host_evolution").getJSONObject("comparison").getJSONArray("improved_case_ids").length())
        assertTrue(f.workspace.browseEvolution(f.access).revisions.all { it.toString().length < 6000 })
    }

    @Test fun failedFilterContainsInputsReferencesAndObservedErrors() {
        val f = Fixture(); val ref = f.publish("baseline", 1)
        val rows = allPages(f.record(ref), "failed").getJSONArray("cases")
        assertEquals(119, rows.length())
        repeat(rows.length()) { i ->
            val row = rows.getJSONObject(i)
            assertFalse(row.getJSONObject("observed").getBoolean("passed"))
            assertTrue(row.has("input") && row.has("expected") && row.has("absolute_tolerance"))
            assertTrue(row.getJSONObject("observed").has("absolute_error"))
        }
    }

    @Test fun regressionAndImprovementFiltersExposeDifferentCases() {
        val f = Fixture(); val ref = f.publish("baseline", 1)
        val next = f.publish("changed", 2, model = """{"constant":1}""", previous = ref)
        val saved = f.record(next)
        val improved = allPages(saved, "improved").getJSONArray("cases")
        val regressed = allPages(saved, "regressed").getJSONArray("cases")
        assertEquals(2, improved.length()); assertEquals(1, regressed.length())
        assertEquals("case-60", regressed.getJSONObject(0).getString("id"))
        assertTrue(regressed.getJSONObject(0).getJSONArray("changes").toString().contains("error_increased"))
        assertEquals(119, allPages(saved, "error_reduced").getJSONArray("cases").length())
    }

    @Test fun domainErrorsAndRecoveryDoNotInventNumericalValues() {
        val f = Fixture(); val first = f.publish("invalid", 1, model = """{"op":"div","args":[{"constant":1},{"constant":0}]}""")
        val failed = allPages(f.record(first), "domain_error").getJSONArray("cases")
        assertEquals(120, failed.length()); assertFalse(failed.getJSONObject(0).getJSONObject("observed").has("actual"))
        val next = f.publish("finite", 2, previous = first)
        assertEquals(120, allPages(f.record(next), "domain_recovered").getJSONArray("cases").length())
        assertEquals(0, allPages(f.record(next), "error_reduced").getJSONArray("cases").length())
    }

    @Test fun absentComparisonAndEmptyFiltersAreExplicit() {
        val f = Fixture(); val saved = f.record(f.publish("first", 1, model = CollaborationNumericFeedbackFixture.SQUARE))
        val page = CollaborationNumericFeedback.page(saved, CollaborationNumericFeedbackFixture.input(saved))
        assertFalse(page.getBoolean("has_comparison")); assertEquals(0, page.getInt("matched_case_count"))
        assertTrue(page.isNull("next_cursor")); assertEquals(0, JSONObject(page.getString("content")).getJSONArray("cases").length())
    }

    @Test fun cursorCannotMoveAcrossFiltersRevisionsOrTrials() {
        val f = Fixture(); val a = f.record(f.publish("a", 1)); val b = f.record(f.publish("b", 2))
        val input = CollaborationNumericFeedbackFixture.input(a)
        val cursor = CollaborationNumericFeedback.page(a, input).getString("next_cursor")
        reject(a, input + ("case_filter" to "all") + ("cursor" to cursor))
        reject(b, CollaborationNumericFeedbackFixture.input(b) + ("cursor" to cursor))
        reject(a, input + ("revision" to 2)); reject(a, input + ("revision" to 1.5))
        reject(a, input + ("sha256" to "0".repeat(64))); reject(a, input + ("object_id" to b.getString("object_id")))
    }

    @Test fun invalidCursorAndArgumentsAreRejectedNotCoerced() {
        val f = Fixture(); val record = f.record(f.publish("first", 1)); val input = CollaborationNumericFeedbackFixture.input(record)
        for (offset in listOf(-1, 0, 1.5, Int.MAX_VALUE, "8000")) reject(record, input + ("cursor" to JSONObject()
            .put("sha256", record.getString("sha256")).put("case_filter", "failed").put("offset", offset).toString()))
        reject(record, input + ("cursor" to "not-json")); reject(record, input + ("cursor" to true))
        reject(record, input + ("case_filter" to "made-up")); reject(record, input + ("case_filter" to 2))
        reject(record, input + ("offset" to 0)); reject(record, input + ("group_id" to "other"))
    }

    @Test fun wrongKindAndCorruptCaseOrderCannotBePresentedAsFeedback() {
        val f = Fixture(); val record = f.record(f.publish("first", 1)); val input = CollaborationNumericFeedbackFixture.input(record)
        reject(JSONObject(record.toString()).put("kind", "artifact"), input)
        val changed = JSONObject(record.toString())
        changed.getJSONObject("host_evolution").getJSONObject("evaluation").getJSONArray("checks").getJSONObject(0).put("id", "wrong")
        reject(changed, input)
    }
}
