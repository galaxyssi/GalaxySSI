package com.galaxyssi.watch

import com.galaxyssi.chat.CloudMethodHistoryProgress
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class WatchMethodHistoryReuseTest {
    private fun arguments() = JSONObject().put("mode", "method_history")
        .put("object_id", "a".repeat(64)).put("sha256", "b".repeat(64)).put("revision", 1)

    private fun output(method: JSONObject): String = JSONObject().put("status", "returned")
        .put("trust", "host_execution_observation_not_method_effectiveness")
        .put("method", method).put("records", JSONArray().put(JSONObject().put("record_id", "c".repeat(64))))
        .toString()

    @Test fun unrecordedOrMismatchedHistoryCannotCountAsProgress() {
        val args = arguments()
        val tracker = CloudMethodHistoryProgress()
        val value = output(args)
        assertNull(tracker.observe(value))
        val wrong = output(arguments().put("revision", 2))
        tracker.record(args, wrong)
        assertNull(tracker.observe(wrong))
        tracker.record(args, value)
        assertEquals(true, tracker.observe(value))
        assertEquals(false, tracker.observe(value))
    }

    @Test fun numericStringsCannotSubstituteForIntegerVersions() {
        val args = arguments().put("revision", "1")
        val value = output(args)
        val tracker = CloudMethodHistoryProgress()
        tracker.record(args, value)
        assertNull(tracker.observe(value))
    }
}
