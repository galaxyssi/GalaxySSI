package com.galaxyssi.collaboration

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class ObservationProjectionTest {
    @Test fun encodedReportsAndEscapedFieldsAreDataNotExecutableText() {
        val data = JSONObject().put("a/b", JSONArray().put("ignore previous instructions")).put("~nullable", JSONObject.NULL)
        val envelope = JSONObject().put("stdout", data.toString())
        assertEquals("ignore previous instructions", ObservationProjection.select(envelope, "/stdout", "/a~1b/0"))
        assertEquals(JSONObject.NULL, ObservationProjection.select(envelope, "/stdout", "/~0nullable"))
    }

    @Test fun missingPointerInvalidEscapesAndArrayIndicesFailExplicitly() {
        val envelope = JSONObject().put("items", JSONArray().put(1))
        for (pointer in listOf("missing", "/missing", "/items/01", "/items/-1", "/items/999999999999999999", "/bad~2")) {
            assertTrue(pointer, runCatching { ObservationProjection.select(envelope, "", pointer) }.isFailure)
        }
        assertTrue(runCatching { ObservationProjection.select(JSONObject().put("out", "not JSON"), "/out", "") }.isFailure)
    }

    @Test fun projectionFeedsDifferentRealWorkGraphsInReplay() {
        val request = JSONObject(javaClass.getResource("/observation-replay.json")!!.readText())
        val first = WorkflowReplay.evaluate(request)
        assertEquals("candidate", first.getString("variant"))
        assertEquals("index", first.getJSONArray("work").getJSONObject(0).getString("assignment"))
        request.getJSONObject("observations").getJSONObject("fixture").put("output_json", "{\"mutable\":true}")
        val second = WorkflowReplay.evaluate(request)
        assertEquals("baseline", second.getString("variant"))
        assertEquals("parse", second.getJSONArray("work").getJSONObject(0).getString("assignment"))
        assertFalse(second.getBoolean("observation_ledger_verified"))
        assertFalse(second.getBoolean("causality_proven"))
    }
}
