package com.galaxyssi.chat

import android.content.res.Configuration
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.net.InetAddress
import java.util.Locale
import java.util.UUID

class ReviewedDirectionalClaimDeviceTest {
    private enum class Advertisement { PLAN, ROLE_ONLY, REJECTED_PLAN }

    @Test fun approvedChineseContrastMatchesTheExactRecheckedDraft() = exercise(false)
    @Test fun rejectedChineseContrastNeverReturnsTheDraft() = exercise(true)
    @Test fun serverHeaderOnRoleCannotEnableWriterSchemas() = exercise(false, Advertisement.ROLE_ONLY)
    @Test fun successfulHttpResponseWithRejectedPlanCannotConfirmTheSession() = exercise(false, Advertisement.REJECTED_PLAN)

    private fun exercise(veto: Boolean, advertisement: Advertisement = Advertisement.PLAN) = runBlocking {
        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        val zh = ctx.createConfigurationContext(Configuration(ctx.resources.configuration).apply { setLocale(Locale.SIMPLIFIED_CHINESE) })
        val labels = TeamResultLabels(zh.teamContrastText())
        val task = "请自动组队比较传感器读数，什么观察会推翻这个预测？请独立审核最终答复。"
        fun claim(input: String) = JSONObject().put("purpose", "假想传感器用于报告受力变化").put("input", input)
            .put("input_direction", "higher").put("readout", "输出电压").put("expected_direction", "lower")
            .put("alternative", "温度也可能使电压下降").put("gap", "没有实测读数")
        val initial = claim("负载")
        val revised = claim("轴向负载")
        val plan = JSONObject().put("roles", JSONArray().put("Check the gauge.")).put("synthesis","Write the prediction.")
        if (advertisement != Advertisement.REJECTED_PLAN) plan.put("final_review","Check interpretation.")
        val replies = listOf(plan, JSONObject().put("finding","No measurements."), initial,
            JSONObject().put("verdict","request_changes").put("objection","Which load?"), revised,
            if (veto) JSONObject().put("verdict","withhold").put("objection","Unsupported.") else JSONObject().put("verdict","accept"))
        MockWebServer().use { server ->
            val headerIndex = if (advertisement == Advertisement.ROLE_ONLY) 1 else 0
            replies.forEachIndexed { index, response ->
                val msg = JSONObject().put("role","assistant").put("content",response.toString())
                val http = MockResponse().setHeader("Content-Type","application/json").setBody(
                    JSONObject().put("choices",JSONArray().put(JSONObject().put("message",msg))).toString())
                if (index == headerIndex) http.setHeader("Server", "llama.cpp")
                server.enqueue(http)
            }
            server.start(InetAddress.getByName("127.0.0.1"), 0)
            val id = UUID.randomUUID().toString()
            val contact = JSONObject().put("cloud_provider","Custom").put("cloud_api_style","openai").put("cloud_model","fixture")
                .put("cloud_api_key","synthetic").put("cloud_endpoint","http://127.0.0.1:${server.port}/v1/chat/completions")
            val route = GoalRoute(id,"fixture",ConversationGoalRunner.fingerprint(contact))
            val session = TeamWriterFormatSession()
            var count = 0
            val run = runCatching { runAutoGoalTeam(task, labels, { system, payload ->
                check(++count <= replies.size)
                withContext(Dispatchers.IO) { ConversationGoalRunner.text(ctx,route,id,id,count,system,payload,
                    AgentNativeToolCancellationToken.NONE, writerSession = session) { _,_,_ -> contact } }
            }) }
            if (advertisement == Advertisement.REJECTED_PLAN) {
                assertTrue(run.exceptionOrNull() is TeamFinalAuditMissing)
                assertEquals(1, server.requestCount)
                assertFalse(JSONObject(server.takeRequest().body.readUtf8()).has("response_format"))
                assertNull(session.format(contrastWriterSystem, contact.getString("cloud_endpoint"), "synthesis"))
                return@use
            }
            assertEquals(6, server.requestCount)
            val inputs = List(6) {
                val req = JSONObject(server.takeRequest().body.readUtf8())
                assertEquals("fixture",req.getString("model"))
                assertFalse(req.has("tools"))
                val messages = req.getJSONArray("messages")
                val input = JSONObject(messages.getJSONObject(messages.length()-1).getString("content"))
                val stage = input.getString("stage")
                if (advertisement == Advertisement.PLAN && stage in setOf("synthesis", "rewrite")) {
                    assertWriterRequest(req, stage)
                } else assertFalse(stage, req.has("response_format"))
                input
            }
            assertEquals(listOf("plan","role","synthesis","audit","rewrite","recheck"),inputs.map { it.getString("stage") })
            val draft = inputs.last().getString("draft")
            assertEquals(inputs[3].getString("draft"),inputs.last().getString("rejected_draft"))
            assertEquals(inputs[3].getString("id"),inputs.last().getString("id"))
            assertTrue(draft.contains("轴向负载") && draft.contains("输出电压") && draft.contains("无效"))
            if (veto) assertEquals("Unsupported.",(run.exceptionOrNull() as TeamAnswerWithheld).reservation)
            else assertTrue(run.getOrThrow().startsWith(draft))
        }
    }

    private fun assertWriterRequest(request: JSONObject, stage: String) {
        val format = request.getJSONObject("response_format")
        assertEquals("json_schema", format.getString("type"))
        val root = format.getJSONObject("json_schema").getJSONObject("schema")
        val claim = if (stage == "synthesis") {
            val variants = root.getJSONArray("anyOf")
            assertEquals(2, variants.length())
            val choices = (0 until variants.length()).map { variants.getJSONObject(it) }
            val prose = choices.single { it.getJSONObject("properties").has("answer") }
            assertEquals(setOf("answer"), prose.getJSONObject("properties").keys().asSequence().toSet())
            assertEquals("string", prose.getJSONObject("properties").getJSONObject("answer").getString("type"))
            choices.single { it.getJSONObject("properties").has("input") }
        } else {
            assertFalse(root.has("anyOf"))
            root
        }
        assertFalse(claim.getBoolean("additionalProperties"))
        val properties = claim.getJSONObject("properties")
        val fields = setOf("purpose", "input", "input_direction", "readout", "expected_direction", "alternative", "gap")
        assertEquals(fields, properties.keys().asSequence().toSet())
        val required = claim.getJSONArray("required")
        assertEquals(fields, (0 until required.length()).map { required.getString(it) }.toSet())
        for (key in listOf("input_direction", "expected_direction")) {
            val values = properties.getJSONObject(key).getJSONArray("enum")
            assertEquals(2, values.length())
            assertEquals(setOf("lower", "higher"), (0 until values.length()).map { values.getString(it) }.toSet())
        }
    }
}
