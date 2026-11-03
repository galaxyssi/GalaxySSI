package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.Base64
import java.util.concurrent.TimeUnit
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Controlled external effect, real process death, production browser adapter/journal; no real model. */
@RunWith(AndroidJUnit4::class)
class AgentEffectRecoveryQueryDeviceTest {
    @Test fun verifyProcessPhase() {
        val arguments = InstrumentationRegistry.getArguments()
        val phase = arguments.getString("effectRecoveryPhase")
        assumeTrue(phase in setOf("crash", "recover"))
        val token = arguments.getString("effectRecoveryToken").orEmpty()
        require(token.matches(Regex("[a-f0-9]{32}")))
        val endpoint = arguments.getString("effectRecoveryUrl").orEmpty().trimEnd('/')
        val uri = java.net.URI(endpoint)
        require(uri.scheme == "http" && uri.host == "127.0.0.1" && uri.port in 1024..65535)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val database = "test-effect-recovery-$token.db"
        val pidFile = context.getFileStreamPath("test-effect-recovery-$token.pid")
        val ledger = AgentRunEventStore(context, database)
        val journal = EncryptedAgentNativeToolReplayStore(ledger)
        val invocation = AgentNativeToolInvocationContext(sessionId = "public-effect-agent-$token",
            conversationId = "public-effect-conversation-$token", turnId = "public-effect-turn-$token",
            invocationId = if (phase == "crash") "before-$token" else "after-$token",
            idempotencyKey = "public-effect-$token", attributes = mapOf("workspace_id" to "public-effect-workspace-$token",
                "client_route_id" to "public-fixture", "goal_id" to token, "task_id" to token))
        val input = mapOf("operation" to "fill", "session_id" to "public-session", "page_id" to "public-page",
            "node_id" to "public-node", "revision" to "public-revision", "value" to "private-fixture-draft-$token")
        val key = AgentNativeToolReplayKey(AgentInteractiveBrowserTools.ACT, "1.2.0", invocation.idempotencyKey!!,
            AgentNativeEffectScope.from(invocation))
        val expectedId = AgentInteractiveBrowserTools.operationId(invocation.copy(invocationId = "before-$token"))
        val http = OkHttpClient.Builder().callTimeout(20, TimeUnit.SECONDS).build()
        var verified = false
        try {
            val definitions = AgentInteractiveBrowserTools.definitions({ request ->
                val count = request.secretEnvironment.getValue("GALAXYSSI_BROWSER_REQUEST_COUNT").toInt()
                val encoded = (0 until count).joinToString("") { request.secretEnvironment.getValue("GALAXYSSI_BROWSER_REQUEST_$it") }
                val command = JSONObject(String(Base64.getDecoder().decode(encoded), Charsets.UTF_8))
                val readOnly = command.getString("operation") == "operation_status"
                if (!readOnly) {
                    check(phase == "crash") { "Recovery must not repeat a mutation" }
                    val claimed = journal.observe(key)!!
                    assertNull(claimed.result)
                    assertEquals(expectedId, claimed.recoveryQuery!!.arguments["request_id"])
                    assertEquals(expectedId, request.secretEnvironment["GALAXYSSI_BROWSER_OPERATION_ID"])
                    assertFalse(request.source.contains("private-fixture-draft"))
                    assertFalse(AgentNativeJsonCodec.stringify(claimed.recoveryQuery.toJsonValue()).contains("private-fixture-draft"))
                }
                val id = if (readOnly) command.getString("request_id") else request.secretEnvironment.getValue("GALAXYSSI_BROWSER_OPERATION_ID")
                val builder = Request.Builder().url("$endpoint/$token/effect/$id")
                if (!readOnly) builder.post("".toRequestBody(null))
                val body = http.newCall(builder.build()).execute().use { response ->
                    check(response.isSuccessful) { "Controlled effect server rejected the fixture request" }
                    response.body!!.string()
                }
                if (!readOnly) {
                    pidFile.writeText(android.os.Process.myPid().toString())
                    android.os.Process.killProcess(android.os.Process.myPid())
                    error("Fixture process must terminate before the outcome is committed")
                }
                AgentRuntimeExecutionResponse(0, body, "", 1)
            })
            val runtime = AgentNativeToolRegistry(replayStore = journal).registerAll(definitions)
            val result = runtime.invoke(AgentInteractiveBrowserTools.ACT, input, invocation)
            check(phase == "recover") { "Crash phase unexpectedly returned" }
            assertNotEquals(pidFile.readText().toInt(), android.os.Process.myPid())
            assertEquals("effect_outcome_unknown", result.error?.code)
            assertEquals(false, result.error?.details?.get("executed_again"))
            val query = AgentNativeEffectRecoveryQuery.fromJsonValue(result.error?.details?.get("recovery_query"))
            assertEquals(expectedId, query.arguments["request_id"])
            assertNotEquals(AgentInteractiveBrowserTools.operationId(invocation), query.arguments["request_id"])
            assertFalse(result.toJson().contains("private-fixture-draft"))
            val observation = runtime.invoke(query.toolId, query.arguments, invocation.copy(invocationId = "observe-$token", idempotencyKey = null))
            assertTrue(observation.toJson(), observation.isSuccess)
            assertEquals("completed", observation.output["state"])
            assertEquals(1, (observation.output["submissions"] as Number).toInt())
            assertEquals(expectedId, observation.output["request_id"])
            assertEquals(false, observation.output["business_success_verified"])
            assertNull(journal.observe(key)!!.result)
            context.openOrCreateDatabase(database, 0, null).use { db ->
                db.rawQuery("SELECT count(*) FROM run_events WHERE encrypted_event LIKE '%$expectedId%'", null).use {
                    assertTrue(it.moveToFirst()); assertEquals(0, it.getInt(0))
                }
            }
            verified = true
        } finally {
            http.connectionPool.evictAll()
            http.dispatcher.executorService.shutdown()
            ledger.close()
            if (verified) { context.deleteDatabase(database); pidFile.delete() }
        }
    }
}
