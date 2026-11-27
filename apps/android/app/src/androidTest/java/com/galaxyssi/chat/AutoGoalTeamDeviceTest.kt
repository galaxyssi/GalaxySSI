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

    @Test fun ordinaryCustomLoopbackPlansInJsonWithoutRequestingAPlanSchema() =
        runTableFixture(hardPlanSchema = false)

    @Test fun explicitLlamaCppLoopbackRequestsAPlanSchema() = runTableFixture(hardPlanSchema = true)

    @Test fun missingRequestedFinalReviewStopsAfterOneLocalRequest() = runBlocking {
        MockWebServer().use { server ->
            val plan = """{"roles":[{"kind":"WORK","parents":[],"task":"Compare totals"}],"synthesis":"Report totals"}"""
            server.enqueue(MockResponse().setHeader("Content-Type", "application/json").setBody(
                JSONObject().put("choices", JSONArray().put(JSONObject().put("message",
                    JSONObject().put("role", "assistant").put("content", plan)))).toString()))
            server.start(java.net.InetAddress.getByName("127.0.0.1"), 0)
            val id = UUID.randomUUID().toString()
            val c = JSONObject().put("cloud_provider", "Custom").put("cloud_api_style", "openai")
                .put("cloud_model", "fixture").put("cloud_api_key", "synthetic")
                .put("cloud_endpoint", "http://127.0.0.1:${server.port}/v1/chat/completions")
            val route = GoalRoute(id, "fixture", ConversationGoalRunner.fingerprint(c))
            var calls = 0
            try {
                runAutoGoalTeam("请比较两份虚构日程，并独立审核最后的答复。", { s, p ->
                    check(++calls == 1) { "Unexpected model call after incomplete plan" }
                    withContext(Dispatchers.IO) {
                        ConversationGoalRunner.text(ctx, route, id, id, calls, s, p,
                            AgentNativeToolCancellationToken.NONE) { _, _, _ -> c }
                    }
                })
                fail("Do not publish a draft without the requested final reviewer")
            } catch (_: TeamFinalAuditMissing) { }
            assertEquals(1, calls)
            assertEquals(1, server.requestCount)
            val messages = JSONObject(server.takeRequest().body.readUtf8()).getJSONArray("messages")
            val payload = JSONObject(messages.getJSONObject(messages.length() - 1).getString("content"))
            assertEquals("plan", payload.getString("stage"))
            assertTrue(payload.getBoolean("final_review_required"))
        }
    }

    @Test fun modelAuthoredIndependentFinalReviewOnPhoneLoopbackRevisesTheActualDraft() = runBlocking {
        val objective = "Compare schedules, then independently audit the final answer."
        val assignment = "Verify the claim about the Friday handover against the stated limitation."
        val draft = "The Friday handover is fixed."
        val dissent = "No Friday slot was confirmed."
        val approved = "The Friday handover is provisional."
        val replies = listOf(
            JSONObject().put("roles", JSONArray().put("Check the slot.")).put("synthesis", "Report the time.")
                .put("final_review", assignment),
            JSONObject().put("finding", "Worker-only calendar note.").put("dissent", dissent),
            JSONObject().put("answer", draft),
            JSONObject().put("verdict", "revise").put("objection", dissent).put("answer", approved)
        )
        MockWebServer().use { server ->
            for (reply in replies) {
                val message = JSONObject().put("role", "assistant").put("content", reply.toString())
                server.enqueue(MockResponse().setHeader("Content-Type", "application/json").setBody(
                    JSONObject().put("choices", JSONArray().put(JSONObject().put("message", message))).toString()))
            }
            server.start(java.net.InetAddress.getByName("127.0.0.1"), 0)
            val id = UUID.randomUUID().toString()
            val preset = CLOUD_MODEL_PRESETS.single { it.provider == "Custom" && it.apiStyle == "openai" }
            val contact = JSONObject().put("cloud_provider", preset.provider).put("cloud_api_style", preset.apiStyle)
                .put("cloud_model", "fixture").put("cloud_api_key", "synthetic")
                .put("cloud_endpoint", "http://127.0.0.1:${server.port}/v1/chat/completions")
            val route = GoalRoute(id, "fixture", ConversationGoalRunner.fingerprint(contact))
            var count = 0
            val result = runAutoGoalTeam(objective, { system, input ->
                val round = ++count
                check(round <= replies.size) { "Unexpected call after final review" }
                withContext(Dispatchers.IO) {
                    ConversationGoalRunner.text(ctx, route, id, id, round, system, input,
                        AgentNativeToolCancellationToken.NONE) { _, _, _ -> contact }
                }
            })

            assertEquals(replies.size, server.requestCount)
            val inputs = List(replies.size) {
                val request = server.takeRequest()
                assertEquals("/v1/chat/completions", request.path)
                val body = JSONObject(request.body.readUtf8())
                assertEquals("fixture", body.getString("model"))
                for (key in listOf("tools", "tool_choice", "functions", "function_call", "response_format"))
                    assertFalse("Unexpected request field: $key", body.has(key))
                val messages = body.getJSONArray("messages")
                JSONObject(messages.getJSONObject(messages.length() - 1).getString("content"))
            }
            assertEquals(listOf("plan", "role", "synthesis", "audit"), inputs.map { it.getString("stage") })
            assertTrue(inputs.first().getBoolean("final_review_required"))
            val audit = inputs.last()
            assertEquals(objective, audit.getString("objective"))
            assertEquals(assignment, audit.getString("assignment"))
            assertEquals(draft, audit.getString("draft"))
            assertNotEquals(inputs[1].getString("id"), audit.getString("id"))
            assertEquals(0, audit.getJSONArray("reports").length())
            assertFalse(audit.toString().contains("Worker-only calendar note."))
            val forwarded = audit.getJSONArray("additional_objections")
            assertEquals(1, forwarded.length())
            assertEquals(inputs[1].getString("id"), forwarded.getJSONObject(0).getString("id"))
            assertEquals(dissent, forwarded.getJSONObject(0).getString("dissent"))
            assertTrue(result.contains(approved))
            assertFalse(result.contains(draft))
        }
    }

    private fun runTableFixture(hardPlanSchema: Boolean) = runBlocking {
        val id = UUID.randomUUID().toString()
        val calls = AtomicInteger()
        val task = "Compare synthetic alternatives.\n|input|gate|left|right|\n|---|---|---|---|\n|sample|<2|2|1|"
        MockWebServer().use { server ->
            server.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse {
                    val body = JSONObject(request.body.clone().readUtf8())
                    val messages = body.getJSONArray("messages")
                    val payload = JSONObject(messages.getJSONObject(messages.length()-1).getString("content"))
                    val stage = payload.getString("stage")
                    val reply = when (stage) {
                        "plan" -> """{"roles":[{"kind":"WORK","parents":[],"task":"Compare prices"},{"kind":"REVIEW","parents":[1],"task":"Audit boundary"}],"synthesis":"Report comparison"}"""
                        "role" -> """{"finding":"These prices are hypothetical."}"""
                        "synthesis" -> """{"answer":"Disputed initial draft."}"""
                        "audit" -> {
                            if (payload.getString("draft") != "Disputed initial draft.") return MockResponse().setResponseCode(400)
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
            val preset = CLOUD_MODEL_PRESETS.single { it.provider == "Custom" && it.apiStyle == "openai" }
            val c = JSONObject().put("id", id).put("name", "Synthetic review").put("cloud_provider", preset.provider)
                .put("cloud_api_style", if (hardPlanSchema) "llama.cpp-json-schema" else preset.apiStyle)
                .put("cloud_model", "fixture").put("cloud_api_key", "synthetic")
                .put("cloud_endpoint", "http://127.0.0.1:${server.port}/v1/chat/completions")
            val route = GoalRoute(id, "fixture", ConversationGoalRunner.fingerprint(c))
            val answer = runAutoGoalTeam(task, { s, p -> withContext(Dispatchers.IO) {
                ConversationGoalRunner.text(ctx, route, id, id, calls.incrementAndGet(), s, p,
                    AgentNativeToolCancellationToken.NONE) { _,_,_ -> c }
            } })
            assertEquals(4, server.requestCount)
            for (stage in listOf("plan", "role", "synthesis", "audit")) {
                val request = server.takeRequest()
                assertEquals("/v1/chat/completions", request.path)
                val body = JSONObject(request.body.readUtf8())
                val messages = body.getJSONArray("messages")
                val payload = JSONObject(messages.getJSONObject(messages.length() - 1).getString("content"))
                assertEquals(stage, payload.getString("stage"))
                assertEquals("fixture", body.getString("model"))
                assertFalse(body.has("tools"))
                assertFalse(body.has("tool_choice"))
                if (stage == "plan" && !hardPlanSchema) {
                    val system = messages.getJSONObject(0).getString("content")
                    assertTrue("Soft planning must describe the JSON fields", listOf("roles", "parents", "synthesis").all { it in system })
                }
                if ((stage == "plan" && hardPlanSchema) || stage == "audit") {
                    val format = body.getJSONObject("response_format")
                    assertEquals("json_schema", format.getString("type"))
                    val envelope = format.getJSONObject("json_schema")
                    assertTrue(envelope.getBoolean("strict"))
                    val fields = envelope.getJSONObject("schema").getJSONObject("properties").keys().asSequence().toSet()
                    assertEquals(if (stage == "plan") setOf("roles", "synthesis") else setOf("purpose", "limitation", "pass_all"), fields)
                } else assertFalse("$stage must retain its original request shape", body.has("response_format"))
            }
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
                    if (body.has("tools") || body.has("tool_choice") || body.has("response_format"))
                        return MockResponse().setResponseCode(400)
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
