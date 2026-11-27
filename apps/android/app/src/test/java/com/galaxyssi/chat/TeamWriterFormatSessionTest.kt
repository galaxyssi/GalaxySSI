package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class TeamWriterFormatSessionTest {
    private val endpoint = "http://127.0.0.1:8080/v1/chat/completions"
    private val other = endpoint.replace(":8080", ":8081")
    private val claimFields = setOf("purpose", "input", "input_direction", "readout", "expected_direction", "alternative", "gap")

    @Test fun onlyTheExactServerProductConfirmsAnOtherwiseUnknownSession() {
        for (server in listOf(null, "", "unknown", "not-llama.cpp", "llama.cpp-proxy", "llama.cpp/",
            "llama.cpp/1.2 proxy", "nginx, llama.cpp")) {
            val session = TeamWriterFormatSession()
            session.observe(endpoint, endpoint, server)
            assertNull(server, session.format(contrastWriterSystem, endpoint, "synthesis"))
        }
        for (server in listOf("llama.cpp", "llama.cpp/1.2.3")) {
            val session = TeamWriterFormatSession()
            assertNull(session.format(contrastWriterSystem, endpoint, "rewrite"))
            session.observe(endpoint, endpoint, server)
            assertNotNull(server, session.format(contrastWriterSystem, endpoint, "rewrite"))
        }
    }

    @Test fun bothUrlsMustBeCanonicalAndMatchAndTheCapabilityIsRunLocal() {
        val invalid = listOf(endpoint.replace("127.0.0.1", "localhost"), endpoint.replace("127.0.0.1", "api.example.invalid"),
            endpoint.replace("//", "//user@"), endpoint.replace("/v1/chat/completions", "/v1/models"),
            "$endpoint/", "$endpoint?version=1", "$endpoint#fragment")
        for (url in invalid) {
            val session = TeamWriterFormatSession()
            session.observe(url, url, "llama.cpp")
            assertNull(url, session.format(contrastWriterSystem, url, "synthesis"))
        }
        val session = TeamWriterFormatSession()
        for (url in invalid + other) {
            session.observe(endpoint, url, "llama.cpp")
            assertNull(url, session.format(contrastWriterSystem, endpoint, "synthesis"))
            assertNull(url, session.format(contrastWriterSystem, url, "synthesis"))
        }
        session.observe(endpoint, endpoint, "llama.cpp")
        assertNotNull(session.format(contrastWriterSystem, endpoint, "synthesis"))
        for (url in invalid + other) assertNull(url, session.format(contrastWriterSystem, url, "synthesis"))
        assertNull(TeamWriterFormatSession().format(contrastWriterSystem, endpoint, "synthesis"))
    }

    @Test fun aKnownRouteStillRequiresTheExactWriterAndKnownStage() {
        val session = TeamWriterFormatSession().apply { observe(endpoint, endpoint, "llama.cpp") }
        for (stage in listOf("", "plan", "role", "audit", "recheck", "Synthesis", "unknown")) {
            assertNull(stage, session.format(contrastWriterSystem, endpoint, stage))
        }
        for (stage in listOf("synthesis", "rewrite")) for (system in listOf("ordinary writer", contrastWriterSystem + "\n")) {
            assertNull(session.format(system, endpoint, stage))
        }
    }

    private fun JSONArray.strings() = (0 until length()).map { getString(it) }

    private fun assertRecord(schema: JSONObject, fields: Set<String>) {
        assertEquals("object", schema.getString("type"))
        assertFalse(schema.getBoolean("additionalProperties"))
        assertEquals(fields, schema.getJSONObject("properties").keys().asSequence().toSet())
        assertEquals(fields.sorted(), schema.getJSONArray("required").strings().sorted())
        for (field in fields) {
            val property = schema.getJSONObject("properties").getJSONObject(field)
            assertEquals("string", property.getString("type"))
            if (field in setOf("input_direction", "expected_direction")) {
                val values = property.getJSONArray("enum").strings()
                assertEquals(2, values.size)
                assertEquals(setOf("lower", "higher"), values.toSet())
            } else assertFalse(field, property.has("enum"))
        }
    }

    @Test fun synthesisAloneOffersAQualitativeAnswerAndRewriteRequiresTheCompleteDirectionalClaim() {
        val session = TeamWriterFormatSession().apply { observe(endpoint, endpoint, "llama.cpp") }
        fun schema(stage: String): JSONObject {
            val format = checkNotNull(session.format(contrastWriterSystem, endpoint, stage))
            assertEquals("json_schema", format.getString("type"))
            val envelope = format.getJSONObject("json_schema")
            assertTrue(envelope.getBoolean("strict"))
            return envelope.getJSONObject("schema")
        }
        val variants = schema("synthesis").getJSONArray("anyOf")
        assertEquals(2, variants.length())
        val choices = (0 until variants.length()).map { variants.getJSONObject(it) }
        assertRecord(choices.single { it.getJSONObject("properties").has("input") }, claimFields)
        assertRecord(choices.single { it.getJSONObject("properties").has("answer") }, setOf("answer"))
        val rewrite = schema("rewrite")
        assertFalse(rewrite.has("anyOf"))
        assertRecord(rewrite, claimFields)
    }
}
