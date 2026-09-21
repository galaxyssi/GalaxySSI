package com.galaxyssi.watch

import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.tls.HandshakeCertificates
import okhttp3.tls.HeldCertificate
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class WatchApiTest {
    @org.junit.Test fun retiredModelCannotBeProvisionedOrRestored() {
        for (model in listOf("gpt-5.3-codex-spark", " GPT-5.3-CODEX-SPARK ")) {
            assertThrows(IllegalArgumentException::class.java) {
                ApiProfile("https://example.com/chat/completions", model, "test-key")
            }
        }
        assertFalse(WATCH_MODEL_PRESETS.any {
            com.galaxyssi.chat.RetiredAgentModelPolicy.isRetired(it.model)
        })
    }

    @Test fun nativeWebToolCallsRoundTripWithCorrelatedResults() = withServer { server, api ->
        val profile = ApiProfile(server.url("/chat/completions").toString(), "test", "test-key")
        val task = WatchTask.create("api", profile.id, profile.model, "Technology news")
        val tools = com.galaxyssi.chat.CloudWebGrounding.openAiTools()
        val native = JSONObject("""{"id":"call_news","type":"function","function":{"name":"web_search","arguments":"{\"query\":\"technology news\"}"}}""")
        server.enqueue(MockResponse().setBody(JSONObject().put("choices", org.json.JSONArray().put(JSONObject()
            .put("message", JSONObject().put("content", JSONObject.NULL).put("tool_calls", org.json.JSONArray().put(native))))).toString()))
        val decision = WatchWebLookup.parseDecision(api.execute(api.request(profile, task, emptyList(),
            webTools = tools, toolMessages = org.json.JSONArray())))
        val call = decision.getJSONArray("tool_calls").getJSONObject(0)
        assertEquals("call_news", call.getString("id"))
        assertEquals("technology news", call.getJSONObject("arguments").getString("query"))
        assertEquals(12, JSONObject(server.takeRequest().body.readUtf8()).getJSONArray("tools").length())
        val exchange = org.json.JSONArray()
            .put(JSONObject().put("role", "assistant").put("tool_calls", org.json.JSONArray().put(native)))
            .put(JSONObject().put("role", "tool").put("tool_call_id", call.getString("id")).put("content", "Retrieved evidence"))
        server.enqueue(MockResponse().setBody("""{"choices":[{"message":{"content":"# News\n\n- Launch [Source](https://example.com/news)"}}]}"""))
        val reply = api.execute(api.request(profile, task, emptyList(), webTools = tools, toolMessages = exchange))
        assertTrue(JSONObject(reply).getString("answer").startsWith("# News"))
        val messages = JSONObject(server.takeRequest().body.readUtf8()).getJSONArray("messages")
        assertEquals("tool", messages.getJSONObject(messages.length() - 1).getString("role"))
        assertEquals("call_news", messages.getJSONObject(messages.length() - 1).getString("tool_call_id"))
    }
    @Test fun unexpectedNativeToolsCannotLeakWhenWebIsDisabled() = withServer { server, api ->
        val profile = ApiProfile(server.url("/chat/completions").toString(), "test", "test-key")
        val task = WatchTask.create("api", profile.id, profile.model, "Hello")
        server.enqueue(MockResponse().setBody("""{"choices":[{"message":{"tool_calls":[{"id":"unexpected"}]}}]}"""))
        assertThrows(ApiFailure::class.java) { api.execute(api.request(profile, task, emptyList())) }
    }
    @Test fun deepSeekUsesBoundedNonThinkingRepliesWithoutChangingOtherProviders() {
        for (host in listOf("api.deepseek.com", "api.openai.com")) {
            val profile = ApiProfile("https://$host/chat/completions", "test", "test-key")
            val task = WatchTask.create("api", profile.id, profile.model, "Hello")
            val request = WatchApi().request(profile, task, emptyList()).request()
            val buffer = okio.Buffer()
            request.body!!.writeTo(buffer)
            val body = JSONObject(buffer.readUtf8())
            if (host == "api.deepseek.com") {
                assertEquals("disabled", body.getJSONObject("thinking").getString("type"))
                assertEquals(2048, body.getInt("max_tokens"))
            } else assertFalse(body.has("thinking"))
        }
    }
    @Test fun deepSeekWebRepliesHaveRoomForCompleteSourceLinks() {
        val profile = ApiProfile("https://api.deepseek.com/chat/completions", "test", "test-key")
        val task = WatchTask.create("api", profile.id, profile.model, "News")
        val request = WatchApi().request(profile, task, emptyList(), toolMessages = org.json.JSONArray()).request()
        val buffer = okio.Buffer()
        request.body!!.writeTo(buffer)
        val body = JSONObject(buffer.readUtf8())
        assertEquals(8192, body.getInt("max_tokens"))
        assertEquals("disabled", body.getJSONObject("thinking").getString("type"))
    }
    @Test fun allAndroidPresetsValidateAndNativeProtocolsRoundTrip() = withServer { server, api ->
        assertEquals(19, WATCH_MODEL_PRESETS.size)
        WATCH_MODEL_PRESETS.forEach { ApiProfile(it.endpoint, it.model, "test", style = it.style) }
        for (style in listOf("anthropic", "gemini")) {
            val path = if (style == "anthropic") "/v1/messages" else "/v1beta/models/test:generateContent"
            val profile = ApiProfile(server.url(path).toString(), "test", "test-key", style = style)
            val task = WatchTask.create("api", profile.id, profile.model, "Hello")
            server.enqueue(MockResponse().setBody(if (style == "anthropic")
                """{"content":[{"type":"text","text":"Reply"}]}""" else
                """{"candidates":[{"content":{"parts":[{"thought":true,"text":"Hidden"},{"text":"Reply"}]}}]}"""))
            assertEquals("Reply", api.execute(api.request(profile, task, emptyList())))
            val request = server.takeRequest()
            assertNull(request.getHeader("Authorization"))
            assertEquals("test-key", request.getHeader(if (style == "anthropic") "x-api-key" else "x-goog-api-key"))
            val body = JSONObject(request.body.readUtf8())
            assertTrue(body.has(if (style == "anthropic") "messages" else "contents"))
            assertEquals(style, ApiProfile.fromJson(profile.json()).style)
        }
    }
    private fun withServer(block: (MockWebServer, WatchApi) -> Unit) {
        val certificate = HeldCertificate.Builder().addSubjectAlternativeName("localhost").addSubjectAlternativeName("127.0.0.1").build()
        val serverCertificates = HandshakeCertificates.Builder().heldCertificate(certificate).build()
        val trusted = HandshakeCertificates.Builder().addTrustedCertificate(certificate.certificate).build()
        val server = MockWebServer()
        server.useHttps(serverCertificates.sslSocketFactory(), false)
        server.start()
        try {
            val client = OkHttpClient.Builder().sslSocketFactory(trusted.sslSocketFactory(), trusted.trustManager)
                .followRedirects(false).followSslRedirects(false).retryOnConnectionFailure(false).build()
            block(server, WatchApi(client))
        } finally { server.shutdown() }
    }
    @Test fun rejectsInsecureEndpointsAndHeaderInjection() {
        for (endpoint in listOf("http://example.com/chat/completions", "https://user:pass@example.com/chat/completions", "https://example.com/chat/completions?key=secret")) {
            assertThrows(Exception::class.java) { ApiProfile(endpoint, "model", "test-key") }
        }
        assertThrows(Exception::class.java) { ApiProfile("https://example.com/chat/completions", "model", "key\nInjected: yes") }
        assertFalse(ApiProfile("https://example.com/chat/completions", "model", "test-secret").toString().contains("test-secret"))
    }
    @Test fun sendsAuthorizedHttpsRequestAndKeepsConversationHistoryIsolated() = withServer { server, api ->
        val profile = ApiProfile(server.url("/v1/chat/completions").toString(), "test-model", "test-key")
        val task = WatchTask.create("api", profile.id, profile.model, "Hello")
        val unrelated = WatchTask.create("api", "other-profile", "other-model", "Private other conversation", task.conversationId)
            .copy(state = TaskState.COMPLETED, reply = "Private reply")
        server.enqueue(MockResponse().setBody("{\"choices\":[{\"message\":{\"content\":\"Watch reply\"}}]}"))
        assertEquals("Watch reply", api.execute(api.request(profile, task, listOf(unrelated))))
        val request = server.takeRequest()
        assertEquals("Bearer test-key", request.getHeader("Authorization"))
        val body = request.body.readUtf8()
        assertFalse(body.contains("Private"))
        assertFalse(body.contains("test-key"))
        assertEquals("test-model", JSONObject(body).getString("model"))
    }
    @Test fun doesNotFollowRedirectOrReplayUnauthorizedRequest() = withServer { server, api ->
        val profile = ApiProfile(server.url("/chat/completions").toString(), "test-model", "test-key")
        val task = WatchTask.create("api", profile.id, profile.model, "Hello")
        server.enqueue(MockResponse().setResponseCode(302).addHeader("Location", "https://example.com/chat/completions"))
        assertThrows(ApiFailure::class.java) { api.execute(api.request(profile, task, emptyList())) }
        assertEquals(1, server.requestCount)
        server.enqueue(MockResponse().setResponseCode(401).setBody("Do not display provider internals"))
        val error = assertThrows(ApiFailure::class.java) { api.execute(api.request(profile, task, emptyList())) }
        assertEquals(R.string.api_auth_error, error.reason)
        assertFalse(error.toString().contains("provider internals"))
        assertEquals(2, server.requestCount)
    }
    @Test fun rejectsUnsupportedResponseAndWrongProfile() = withServer { server, api ->
        val profile = ApiProfile(server.url("/chat/completions").toString(), "test-model", "test-key")
        val task = WatchTask.create("api", profile.id, profile.model, "Hello")
        server.enqueue(MockResponse().setBody("{\"choices\":[]}"))
        assertThrows(ApiFailure::class.java) { api.execute(api.request(profile, task, emptyList())) }
        assertThrows(IllegalArgumentException::class.java) { api.request(profile, task.copy(routeId = "other"), emptyList()) }
    }
}
