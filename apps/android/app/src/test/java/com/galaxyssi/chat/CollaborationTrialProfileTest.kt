package com.galaxyssi.chat

import com.galaxyssi.chat.voice.modelstream.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationTrialProfileTest {
    private val profile = CollaborationTrialProfile(2048, 0.0, "disabled")
    private fun receipt(body: JSONObject): JSONObject {
        val values = mutableListOf<JSONObject>()
        ModelCallAccounting(ModelStreamRequest("r", ModelStreamProvider.OPENAI_COMPATIBLE, "https://example.invalid",
            emptyMap(), body.toString()), ModelCallAuditSink(values::add), singleHttpRequest = true).begin()
        return values.single()
    }

    @Test fun explicitControlsSurviveJsonAndDoNotMutateSavedContact() {
        val contact = JSONObject().put("cloud_context_model_summary", true).put("cloud_model", "model")
        assertFalse(profile.contact(contact).getBoolean("cloud_context_model_summary"))
        assertTrue(contact.getBoolean("cloud_context_model_summary"))
        val body = JSONObject("""{"model":"model","messages":[],"tools":[{}],"tool_choice":"auto","top_p":0.9,"reasoning_effort":"high","max_completion_tokens":999}""")
        profile.apply(body)
        assertFalse(body.has("tools") || body.has("top_p") || body.has("max_completion_tokens"))
        assertEquals(2048, body.getInt("max_tokens"))
        assertEquals(profile, CollaborationTrialProfile.from(profile.json()))
        profile.requireControls(receipt(body))
        val policy = CollaborationTrialPolicy("a".repeat(64), "target", "model", 3, 1000, profile)
        assertEquals(policy, CollaborationTrialPolicy.from(policy.json()))
        policy.requireRequest(receipt(body))
    }

    @Test fun driftOrMalformedRequestIsDeniedBeforeAdmission() {
        val changes: List<(JSONObject) -> Unit> = listOf(
            { it.put("max_tokens", 4096) }, { it.put("max_tokens", "2048") },
            { it.put("temperature", 0.7) }, { it.remove("temperature") },
            { it.put("thinking", JSONObject().put("type", "enabled")) },
            { it.put("tools", org.json.JSONArray().put(JSONObject())) },
            { it.put("tools", "private malformed payload") }, { it.put("top_p", 0.8) },
            { it.put("reasoning_effort", "high") }
        )
        changes.forEach { change ->
            val body = JSONObject().also(profile::apply).also(change)
            assertThrows(ModelCallAdmissionDenied::class.java) { profile.requireControls(receipt(body)) }
        }
        val forged = receipt(JSONObject().also(profile::apply))
        forged.getJSONObject("request_controls").put("tool_definitions", "0")
        assertThrows(ModelCallAdmissionDenied::class.java) { profile.requireControls(forged) }
    }

    @Test fun accountingControlsNeverLeakArbitraryValuesOrToolDefinitions() {
        val body = JSONObject("""{"model":"model","messages":[{"content":"private prompt"}],"tools":[{"description":"private tool"}],"temperature":"private setting","thinking":{"type":"private thinking"},"reasoning_effort":"private effort"}""")
        val recorded = receipt(body)
        assertFalse(recorded.toString().contains("private"))
        assertFalse(recorded.getJSONObject("request_controls").getBoolean("types_valid"))
        assertEquals(1, recorded.getJSONObject("request_controls").getInt("tool_definitions"))
    }

    @Test fun profilesRejectCoercedOrUnsupportedConfiguration() {
        listOf<Any>("2048", 2048.1, 0, -1).forEach { value -> assertThrows(RuntimeException::class.java) {
            CollaborationTrialProfile.from(profile.json().put("max_output_tokens", value))
        } }
        assertThrows(IllegalArgumentException::class.java) { profile.copy(thinkingMode = "enabled") }
        assertThrows(IllegalArgumentException::class.java) { profile.copy(temperature = Double.NaN) }
        assertThrows(IllegalArgumentException::class.java) { CollaborationTrialProfile.from(profile.json().put("external_tools", true)) }
    }
}
