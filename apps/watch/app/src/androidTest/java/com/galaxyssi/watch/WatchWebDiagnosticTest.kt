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
