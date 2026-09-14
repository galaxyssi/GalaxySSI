package com.galaxyssi.watch

import android.content.Intent
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.CloudWebGrounding
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class WatchWebDiagnosticTest {
    @Test fun inspectNewsProtocol() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("news_protocol_diagnostic") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext
        val repo = (context as WatchApplication).repository
        val profile = requireNotNull(repo.store.apiProfile)
        val question = "\u7ed9\u51fa\u4eca\u5929\u7684\u79d1\u6280\u65b0\u95fb"
        repo.store.tasks().filter { it.prompt.contains("\u79d1\u6280\u65b0\u95fb") }.take(3).forEach {
            println("WATCH_NEWS_OLD prompt=${it.prompt.take(120)} reply=${it.reply.take(4000)}")
        }
        val task = WatchTask.create("api", profile.id, profile.model, question)
        val result = WatchWebLookup(context, observeReply = { println("WATCH_NEWS_MODEL=$it") })
            .answer(profile, task, emptyList(), WatchApiOperation())
        println("WATCH_NEWS_FINAL=$result")
    }
    @Test fun newsConversationForScreenshot() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("news_api_diagnostic") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext.applicationContext
        val repo = (context as WatchApplication).repository
        val question = "\u7ed9\u51fa\u4eca\u5929\u7684\u79d1\u6280\u65b0\u95fb"
        println("WATCH_NEWS web_enabled=${repo.store.webSearch}")
        val previous = repo.store.tasks().firstOrNull { it.prompt == question && it.desktopId == "api" }
        previous?.let { println("WATCH_NEWS previous_reply=${it.reply.take(4000)}") }
        require(repo.store.apiProfile != null && repo.store.webSearch && repo.store.apiPreferred)
        val created = CountDownLatch(1)
        var task: WatchTask? = null
        repo.send(question, previous) { task = it; created.countDown() }
        assertTrue(created.await(10, TimeUnit.SECONDS))
        val id = requireNotNull(task).id
        val finished = CountDownLatch(1)
        val listener: () -> Unit = { if (repo.store.task(id)?.state?.terminal == true) finished.countDown() }
        repo.listen(listener)
        try {
            listener()
            assertTrue("News request timed out", finished.await(190, TimeUnit.SECONDS))
            val result = repo.store.task(id)!!
            println("WATCH_NEWS state=${result.state} reply=${result.reply.take(6000)} progress=${result.progress}")
            assertEquals(result.progress, TaskState.COMPLETED, result.state)
            assertNotEquals("A repeated lookup must retrieve fresh evidence", context.getString(R.string.web_planning), result.progress)
            assertFalse(result.reply.contains("tool_calls"))
            assertFalse(result.reply.contains("evidence_pack"))
            assertFalse(result.reply.startsWith(context.getString(R.string.cloud_web_fallback_sources)))
            assertTrue("Expected a news digest", WatchRichReply.blocks(result.reply).any {
                it.type == com.galaxyssi.chat.AgentRichBlockType.LIST && it.rows.size >= 3
            })
            assertTrue("Expected source links", result.reply.contains("https://"))
            val sourceUrls = Regex("https://[^\\s)<>]+").findAll(result.reply).map { it.value }.toList()
            assertTrue("A source directory is not a news digest", sourceUrls.any {
                runCatching { java.net.URI(it).path.trim('/').isNotBlank() }.getOrDefault(false)
            })
            instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).putExtra("task_id", id))
            instrumentation.waitForIdleSync()
        } finally { repo.unlisten(listener) }
    }
    @Test fun sharedAndroidWeatherFetchAndImages() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("web_diagnostic") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext
        val cases = listOf(
            "web_weather" to JSONObject().put("location", "Zhuhai").put("region", "Guangdong").put("country_code", "CN"),
            "web_fetch" to JSONObject().put("url", "https://www.example.com"),
            "web_image_search" to JSONObject().put("query", "Zhuhai skyline").put("max_results", 2)
        )
        for ((name, args) in cases) {
            val result = JSONObject(CloudWebGrounding.executeTool(context, name, args))
            assertNotEquals("$name: ${result.optString("error")}", "failed", result.optString("status"))
            assertTrue("$name needs source evidence", result.optJSONObject("evidence_pack")?.optJSONArray("items")?.length()?.let { it > 0 } == true)
            println("WATCH_WEB tool=$name status=${result.optString("status")}")
        }
    }
    /** Explicit opt-in: sends the screenshot's public weather question and keeps its visible answer. */
    @Test fun weatherConversationForScreenshot() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("web_api_diagnostic") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext.applicationContext
        val repo = (context as WatchApplication).repository
        require(repo.store.apiProfile != null && repo.store.webSearch && repo.store.apiPreferred)
        val question = "\u73e0\u6d77\u4eca\u5929\u7684\u5929\u6c14"
        val previous = repo.store.tasks().firstOrNull { it.prompt == question && it.desktopId == "api" }
        val created = CountDownLatch(1)
        var task: WatchTask? = null
        repo.send(question, previous) { task = it; created.countDown() }
        assertTrue(created.await(10, TimeUnit.SECONDS)); assertNotNull(task)
        val id = task!!.id
        val finished = CountDownLatch(1)
        val listener: () -> Unit = { if (repo.store.task(id)?.state?.terminal == true) finished.countDown() }
        repo.listen(listener)
        try {
            listener()
            assertTrue("Weather request timed out", finished.await(190, TimeUnit.SECONDS))
            val result = repo.store.task(id)!!
            assertEquals(result.progress, TaskState.COMPLETED, result.state)
            assertTrue("Expected weather data", result.reply.contains("°") || result.reply.contains("\u2103"))
            assertTrue("Expected weather source", result.reply.contains("open-meteo.com"))
            instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).putExtra("task_id", id))
            instrumentation.waitForIdleSync()
        } finally { repo.unlisten(listener) }
    }
}
