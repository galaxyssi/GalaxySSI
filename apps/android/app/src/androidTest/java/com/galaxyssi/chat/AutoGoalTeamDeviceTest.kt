package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger

class AutoGoalTeamDeviceTest {
    private val ctx get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun onlyTheLoopbackTableAuditRequestsStructuredOutputAndItsDraftIsNotReleased() = runBlocking {
        val id = UUID.randomUUID().toString()
        val calls = AtomicInteger()
        val task = "Compare synthetic alternatives.\n|input|gate|left|right|\n|---|---|---|---|\n|sample|<2|2|1|"
        MockWebServer().use { server ->
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    val body = JSONObject(request.body.readUtf8())
                    val messages = body.getJSONArray("messages")
                    val payload = JSONObject(messages.getJSONObject(messages.length()-1).getString("content"))
                    val stage = payload.getString("stage")
                    if (body.has("tools") || body.has("tool_choice") || (stage == "audit") != body.has("response_format"))
                        return MockResponse().setResponseCode(400)
                    val reply = when (stage) {
                        "plan" -> "WORK|-|Compare prices\nREVIEW|1|Audit boundary\nSYNTHESIS|Report comparison"
                        "role" -> """{"finding":"These prices are hypothetical."}"""
                        "synthesis" -> """{"answer":"Disputed initial draft."}"""
                        "audit" -> {
                            if (body.getJSONObject("response_format").getString("type") != "json_schema" ||
                                payload.getString("draft") != "Disputed initial draft.") return MockResponse().setResponseCode(400)
                            """{"purpose":"Compare synthetic alternatives.","limitation":"No measured price.","pass_all":["right"]}"""
                        }
                        else -> return MockResponse().setResponseCode(400)
                    }
                    return MockResponse().setHeader("Content-Type", "application/json").setBody(
                        JSONObject().put("choices", JSONArray().put(JSONObject().put("message",
                            JSONObject().put("role","assistant").put("content",reply)))).toString())
                }
            }
            server.start(java.net.InetAddress.getByName("127.0.0.1"), 0)
            val c = JSONObject().put("id", id).put("name", "Synthetic review").put("cloud_provider", "custom")
                .put("cloud_api_style", "openai").put("cloud_model", "fixture").put("cloud_api_key", "synthetic")
                .put("cloud_endpoint", "http://127.0.0.1:${server.port}/fixture")
            val route = GoalRoute(id, "fixture", ConversationGoalRunner.fingerprint(c))
            val answer = runAutoGoalTeam(task, { s, p -> withContext(Dispatchers.IO) {
                ConversationGoalRunner.text(ctx, route, id, id, calls.incrementAndGet(), s, p,
                    AgentNativeToolCancellationToken.NONE) { _,_,_ -> c }
            } })
            assertEquals(4, server.requestCount)
            assertTrue("Pass all gates: right" in answer)
            assertFalse("Disputed initial draft." in answer)
        }
    }

    @Test fun conceptualPkuReviewUsesIndependentCallsAndPreservesObjections() = runBlocking {
        val id = UUID.randomUUID().toString()
        val calls = AtomicInteger()
        val inputs = mutableListOf<JSONObject>()
        val plan = """ROLE|evidence|worker|-|Separate reported findings from assumptions.
            |ROLE|criteria|worker|-|Summarize functional criteria only.
            |ROLE|review|reviewer|evidence,criteria|Identify unsupported claims.
            |SYNTHESIS|Explain the limitations and preserve dissent.""".trimMargin()
        MockWebServer().use { server ->
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    val body = JSONObject(request.body.readUtf8())
                    if (body.has("tools") || body.has("tool_choice")) return MockResponse().setResponseCode(400)
                    val turns = body.getJSONArray("messages")
                    val input = JSONObject(turns.getJSONObject(turns.length() - 1).getString("content"))
                    synchronized(inputs) { inputs.add(input) }
                    val answer = when (input.getString("stage")) {
                        "plan" -> plan
                        "synthesis" -> "The proposed function remains hypothetical.\nEND"
                        else -> when (input.getString("id")) {
                            "evidence" -> "FINDING|Published endpoints are not candidate-specific evidence.\nDISSENT|-\nEND"
                            "criteria" -> "FINDING|Distinguish a biochemical target from benefit.\nDISSENT|-\nEND"
                            else -> "FINDING|Insufficient evidence.\nDISSENT|Clinical benefit is unverified.\nEND"
                        }
                    }
                    return MockResponse().setHeader("Content-Type", "application/json").setBody(
                        JSONObject().put("choices", JSONArray().put(JSONObject().put("message",
                            JSONObject().put("role", "assistant").put("content", answer)))).toString())
                }
            }
            server.start()
            val c = JSONObject().put("id", id).put("name", "Synthetic team").put("cloud_provider", "custom")
                .put("cloud_api_style", "openai").put("cloud_model", "fixture").put("cloud_api_key", "synthetic")
                .put("cloud_endpoint", server.url("/fixture").toString())
            val r = GoalRoute(id, "fixture", ConversationGoalRunner.fingerprint(c))
            val answer = runAutoGoalTeam("Review functional criteria for a hypothetical PKU protein. No patient data.", { s, p ->
                withContext(Dispatchers.IO) { ConversationGoalRunner.text(ctx, r, id, id, calls.incrementAndGet(),
                    s, p, AgentNativeToolCancellationToken.NONE) { _, _, _ -> c } }
            })
            assertEquals(5, server.requestCount)
            val roles = inputs.filter { it.getString("stage") == "role" }.associateBy { it.getString("id") }
            assertEquals(0, roles.getValue("evidence").getJSONArray("reports").length())
            assertEquals(0, roles.getValue("criteria").getJSONArray("reports").length())
            assertEquals(2, roles.getValue("review").getJSONArray("reports").length())
            assertTrue(answer.contains("Clinical benefit is unverified."))
        }
    }

    @Test fun orphanedJobDoesNotCallAModelOrPublishIntoAnotherChat() {
        val id = UUID.randomUUID().toString()
        val chat = UUID.randomUUID().toString()
        val db = AgentEncryptedDatabase(ctx, "galaxyssi_conversation_teams_v1")
        db.writeString(chat, JSONObject().put("id", id).put("state", "queued").toString())
        try {
            AutoGoalTeamJobs.execute(ctx, chat, id, { false }, AgentNativeToolCancellationSource())
            assertEquals("", db.readString(chat, ""))
        } finally { db.remove(chat) }
    }
}
