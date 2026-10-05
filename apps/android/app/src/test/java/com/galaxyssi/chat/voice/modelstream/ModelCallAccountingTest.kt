package com.galaxyssi.chat.voice.modelstream

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ModelCallAccountingTest {
    private fun request() = ModelStreamRequest("parent:r0", ModelStreamProvider.OPENAI_COMPATIBLE,
        "https://example.invalid/private-path", mapOf("Authorization" to "private-key"),
        """{"model":"requested-model","messages":[{"content":"private prompt"}]}""")
    private fun run(payload: String?, done: Boolean = true, failed: Boolean = false): JSONObject {
        val rows = mutableListOf<JSONObject>()
        val audit = ModelCallAccounting(request(), ModelCallAuditSink(rows::add), { 20L }, { 40L })
        audit.begin()
        payload?.let(audit::observe)
        if (done) audit.observe("[DONE]")
        audit.event(if (failed) ModelStreamEvent.Failed("parent:r0", ModelStreamError("NETWORK_ERROR", "private text"))
            else ModelStreamEvent.Completed("parent:r0", "stop", 21L))
        audit.finish()
        audit.finish()
        assertEquals(2, rows.size)
        assertEquals("started", rows.first().getString("status"))
        assertFalse(rows.first().getBoolean("tokens_complete"))
        assertTrue(rows.last().isNull("cost_micros"))
        assertFalse(rows.last().toString().contains("private"))
        return rows.last()
    }

    @Test fun missingUsageIsUnknownWhileExplicitZeroIsKnown() {
        assertFalse(run(null).getBoolean("tokens_complete"))
        val known = run("""{"id":"response-1","model":"actual-model","usage":{"prompt_tokens":0,"completion_tokens":0,"total_tokens":0}}""")
        assertTrue(known.getBoolean("tokens_complete"))
        assertEquals(0, known.getJSONObject("usage").getLong("total_tokens"))
        assertEquals("requested-model", known.getString("requested_model"))
        assertEquals("actual-model", known.getString("reported_model"))
        assertTrue(known.getJSONObject("usage").isNull("cached_input_tokens"))
    }

    @Test fun snapshotsAreNotSummedAndCacheAndReasoningAreSubsets() {
        val rows = mutableListOf<JSONObject>()
        val audit = ModelCallAccounting(request(), ModelCallAuditSink(rows::add))
        audit.begin()
        val payload = """{"usage":{"prompt_tokens":100,"completion_tokens":20,"total_tokens":120,"prompt_cache_hit_tokens":70,"prompt_tokens_details":{"cached_tokens":70},"completion_tokens_details":{"reasoning_tokens":12}}}"""
        repeat(100) { audit.observe(payload) }
        audit.observe("[DONE]")
        audit.event(ModelStreamEvent.Completed("parent:r0", "stop", 1))
        audit.finish()
        val receipt = rows.last()
        assertTrue(receipt.getBoolean("tokens_complete"))
        assertEquals(120, receipt.getJSONObject("usage").getLong("total_tokens"))
        assertEquals(70, receipt.getJSONObject("usage").getLong("cached_input_tokens"))
        assertEquals(12, receipt.getJSONObject("usage").getLong("reasoning_output_tokens"))
    }

    @Test fun malformedAndConflictingCountsNeverBecomeMeasuredZero() {
        listOf("null", "false", "\"0\"", "-1", "1.5", "9223372036854775808").forEach { bad ->
            assertFalse(run("""{"usage":{"prompt_tokens":$bad,"completion_tokens":1}}""").getBoolean("tokens_complete"))
        }
        listOf(
            """{"prompt_tokens":2,"input_tokens":3,"completion_tokens":1}""",
            """{"prompt_tokens":2,"completion_tokens":1,"total_tokens":99}""",
            """{"prompt_tokens":2,"completion_tokens":1,"prompt_cache_hit_tokens":3}""",
            """{"prompt_tokens":2,"completion_tokens":1,"completion_tokens_details":{"reasoning_tokens":2}}""",
            """{"prompt_tokens":9223372036854775807,"completion_tokens":1}"""
        ).forEach { usage -> assertFalse(run("""{"usage":$usage}""").getBoolean("tokens_complete")) }
    }

    @Test fun partialOrFailedResponsesRemainIncompleteEvenWithSomeUsage() {
        val payload = """{"usage":{"prompt_tokens":10,"completion_tokens":2}}"""
        assertFalse(run(payload, done = false).getBoolean("tokens_complete"))
        val failed = run(payload, failed = true)
        assertFalse(failed.getBoolean("tokens_complete"))
        assertEquals(12, failed.getJSONObject("usage").getLong("total_tokens"))
        assertEquals("failed", failed.getString("status"))
    }

    @Test fun changedProviderIdentityInvalidatesUsageAndMissingModelIsNotInferred() {
        val rows = mutableListOf<JSONObject>()
        val audit = ModelCallAccounting(request(), ModelCallAuditSink(rows::add))
        audit.begin()
        audit.observe("""{"id":"one","model":"model-a"}""")
        audit.observe("""{"id":"two","model":"model-b","usage":{"prompt_tokens":1,"completion_tokens":1}}""")
        audit.observe("[DONE]")
        audit.event(ModelStreamEvent.Completed("parent:r0", "stop", 1))
        audit.finish()
        assertFalse(rows.last().getBoolean("tokens_complete"))
        assertTrue(rows.last().getJSONArray("issues").toString().contains("identity_changed"))
        assertTrue(run("""{"usage":{"prompt_tokens":1,"completion_tokens":1}}""").isNull("reported_model"))
    }

    @Test fun completeJsonAndResponsesUsageAreCapturedWithoutExtraSummation() {
        val rows = mutableListOf<JSONObject>()
        val audit = ModelCallAccounting(request().copy(transport = ModelStreamTransport.COMPLETE_JSON), ModelCallAuditSink(rows::add))
        audit.begin()
        audit.observe("""{"response":{"id":"r1","model":"actual","usage":{"input_tokens":5,"output_tokens":2,"input_tokens_details":{"cached_tokens":3}}}}""")
        audit.event(ModelStreamEvent.Completed("parent:r0", "stop", 1))
        audit.finish()
        assertTrue(rows.last().getBoolean("tokens_complete"))
        assertEquals(7, rows.last().getJSONObject("usage").getLong("total_tokens"))
    }

    @Test fun cancellationUnsupportedProvidersAndUnfinishedCallsAreNotFreeSuccesses() {
        for (provider in ModelStreamProvider.entries) {
            val rows = mutableListOf<JSONObject>()
            val audit = ModelCallAccounting(request().copy(provider = provider), ModelCallAuditSink(rows::add))
            audit.begin()
            audit.observe("""{"usage":{"prompt_tokens":10,"completion_tokens":2}}""")
            if (provider == ModelStreamProvider.OPENAI_COMPATIBLE) audit.cancelled()
            audit.finish()
            assertFalse(rows.last().getBoolean("tokens_complete"))
            assertTrue(rows.last().isNull("cost_micros"))
        }
    }
}
