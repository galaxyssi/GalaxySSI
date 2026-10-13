package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Local scripted HTTP only; no user credentials or real model endpoint. */
@RunWith(AndroidJUnit4::class)
class AgentProviderRouteIsolationDeviceTest {
    @Test fun adaptersSnapshotCredentialsAndNewAccountsDoNotReceiveOldOpaqueState() = runBlocking {
        val app = InstrumentationRegistry.getInstrumentation().targetContext
        val token = UUID.randomUUID().toString()
        MockWebServer().use { server ->
            server.start()
            repeat(3) {
                server.enqueue(MockResponse().setHeader("Content-Type", "application/json").setBody(
                    JSONObject().put("choices", JSONArray().put(JSONObject().put("message", JSONObject()
                        .put("role", "assistant").put("content", "公开测试已完成。")
                        .put("reasoning_content", "public-opaque-fixture")))).toString()))
            }
            val contact = JSONObject().put("id", "public-route-$token").put("name", "Public route fixture")
                .put("cloud_provider", "custom").put("cloud_api_style", "openai").put("cloud_model", "fixture-model")
                .put("cloud_api_key", "public-fixture-key-a").put("cloud_endpoint", server.url("/fixture").toString())
            val original = CloudModelClient.nativeToolAdapter(app, contact, emptyList())
            val request = AgentModelRequest("public-session-$token", "public-conversation-$token", "public-turn-$token",
                "public-task-$token", "public-workspace-$token", 1, listOf(AgentModelMessage.user("请验证公开测试路由。")),
                "{}", "", 10, 4_000, 30_000, 1, AgentNativeToolCancellationToken.NONE)
            withTimeout(30_000) {
                val response = original.complete(request)
                assertNotNull(response.continuation)
                val history = request.messages + AgentModelMessage(AgentModelMessageRole.ASSISTANT,
                    response.assistantText, response.toolCalls, continuation = response.continuation)
                contact.put("cloud_api_key", "public-fixture-key-b")
                original.complete(request.copy(round = 2, messages = history))
                CloudModelClient.nativeToolAdapter(app, contact, emptyList()).complete(request.copy(round = 2, messages = history))
            }
            assertEquals(3, server.requestCount)
            val requests = (0..2).map { checkNotNull(server.takeRequest(1, TimeUnit.SECONDS)) }
            assertEquals(listOf("Bearer public-fixture-key-a", "Bearer public-fixture-key-a", "Bearer public-fixture-key-b"),
                requests.map { it.getHeader("Authorization") })
            val bodies = requests.map { it.body.readUtf8() }
            assertTrue(bodies[1].contains("public-opaque-fixture"))
            assertFalse(bodies[2].contains("public-opaque-fixture"))
            assertTrue(bodies[2].contains("公开测试已完成。"))
        }
    }
}
