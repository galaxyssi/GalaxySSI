package com.galaxyssi.watch

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class WatchWebSearchTest {
    @Test fun fallbackParsesResultCardsWithoutCredentialsOrNavigation() {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setResponseCode(403))
            server.enqueue(MockResponse().setBody("""<nav><a href="https://bad.test/">Menu</a></nav>
                <li class="b_algo"><h2><a href="https://source.test/news">News</a></h2><div class="b_caption"><p>Fresh report</p></div></li>
                <li class="b_algo"><h2><a href="https://source.test/news">Duplicate</a></h2><p>Duplicate</p></li>"""))
            val search = WatchWebSearch(OkHttpClient(), listOf(server.url("/one").toString() to "q", server.url("/two").toString() to "wd"))
            val evidence = search.search("today & news", WatchApiOperation())
            assertEquals(1, evidence.hits.size)
            assertEquals("Fresh report", evidence.hits.single().excerpt)
            assertTrue(evidence.sources().contains("https://source.test/news"))
            repeat(2) {
                val request = server.takeRequest()
                assertNull(request.getHeader("Authorization"))
                assertNull(request.getHeader("x-api-key"))
                assertEquals("today & news", request.requestUrl!!.queryParameter(if (it == 0) "q" else "wd"))
            }
        }
    }
    @Test fun emptyResultsFailInsteadOfPretendingToHaveSearched() {
        MockWebServer().use { server ->
            server.enqueue(MockResponse().setBody("<html>Captcha</html>"))
            val search = WatchWebSearch(OkHttpClient(), listOf(server.url("/").toString() to "q"))
            assertEquals(R.string.web_search_failed, assertThrows(ApiFailure::class.java) {
                search.search("today", WatchApiOperation())
            }.reason)
        }
    }
    @Test fun stopCancelsCurrentCallAndRejectsTheNextStage() {
        val client = OkHttpClient()
        val operation = WatchApiOperation()
        val first = client.newCall(Request.Builder().url("https://example.com/").build())
        operation.attach(first)
        operation.cancel()
        assertTrue(first.isCanceled())
        val next = client.newCall(first.request())
        assertThrows(java.io.IOException::class.java) { operation.attach(next) }
        assertTrue(next.isCanceled())
    }
    @Test fun everyProtocolReceivesEvidenceWithoutChangingTheQuestion() {
        for (style in listOf("openai", "anthropic", "gemini")) {
            val path = when (style) { "anthropic" -> "messages"; "gemini" -> "test:generateContent"; else -> "chat/completions" }
            val profile = ApiProfile("https://api.deepseek.com/$path", "test", "secret", style = style)
            val task = WatchTask.create("api", profile.id, profile.model, "Question")
            val request = WatchApi().request(profile, task, emptyList(), "EVIDENCE").request()
            val buffer = okio.Buffer(); request.body!!.writeTo(buffer)
            val body = JSONObject(buffer.readUtf8())
            val context = when (style) {
                "anthropic" -> body.getString("system")
                "gemini" -> body.getJSONObject("systemInstruction").toString()
                else -> body.getJSONArray("messages").getJSONObject(0).getString("content")
            }
            assertTrue(context.contains("untrusted external data"))
            assertTrue(context.contains("EVIDENCE"))
            assertEquals("Question", task.prompt)
            if (style == "openai") assertEquals("disabled", body.getJSONObject("thinking").getString("type"))
        }
    }
}
