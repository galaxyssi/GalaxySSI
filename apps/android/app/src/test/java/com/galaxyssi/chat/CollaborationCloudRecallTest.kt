package com.galaxyssi.chat

import com.galaxyssi.chat.voice.modelstream.ModelStreamProvider
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationCloudRecallTest {
    @Test fun addsProviderNativeReadOnlySchemaWithoutReplacingOtherTools() {
        ModelStreamProvider.entries.forEach { provider ->
            val body = JSONObject().put("tools", JSONArray().put(JSONObject().put("sentinel", true)))
            val prepared = PreparedCloudConversationStream("request", provider, "https://example.invalid", emptyMap(),
                body, JSONArray(), "messages")
            CollaborationCloudRecall.install(prepared)
            assertTrue(body.getJSONArray("tools").getJSONObject(0).getBoolean("sentinel"))
            val added = body.getJSONArray("tools").getJSONObject(1)
            val function = when (provider) {
                ModelStreamProvider.OPENAI_COMPATIBLE -> added.getJSONObject("function")
                ModelStreamProvider.ANTHROPIC -> added
                ModelStreamProvider.GEMINI -> added.getJSONArray("functionDeclarations").getJSONObject(0)
            }
            assertEquals("collaboration_recall", function.getString("name"))
            assertTrue(function.getString("description").contains("source_reference"))
            assertTrue(function.getString("description").contains("only records this recall"))
            val schema = function.getJSONObject(if (provider == ModelStreamProvider.ANTHROPIC) "input_schema" else "parameters")
            val properties = schema.getJSONObject("properties")
            assertEquals(setOf("mode", "cursor", "object_id", "revision", "evidence_id", "sha256", "offset", "record_id"),
                properties.keys().asSequence().toSet())
            assertEquals(listOf("evidence", "workspace", "goal_contract", "archive"), properties.getJSONObject("mode").getJSONArray("enum").let {
                (0 until it.length()).map(it::getString) })
            assertFalse(properties.has("group_id"))
            assertFalse(properties.has("source_message_id"))
            assertFalse(properties.has("person_id"))
        }
    }
}
