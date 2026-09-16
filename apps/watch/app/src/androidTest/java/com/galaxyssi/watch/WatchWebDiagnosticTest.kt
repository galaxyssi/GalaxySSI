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
    @Test fun requestedForecastAndResearchUseLiveEvidence() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("grounding_diagnostic") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext.applicationContext as WatchApplication
        val repo = context.repository
        val profile = requireNotNull(repo.store.apiProfile)
        require(repo.store.webSearch)
        val scenario = args.getString("scenario", "weather")
        val question = when (scenario) {
            "followup" -> "好的"
            "analysis" -> "请深入检索并分析：AI普及、远程办公和交通改善，可能缩小还是扩大城市中心与周边的房价差距？结合环境质量，区分研究证据、推理和不确定性。"
            else -> "明天珠海的天气。"
        }
        val task = WatchTask.create("api", profile.id, profile.model, question).copy(state = TaskState.RUNNING)
        val history = if (scenario == "followup") listOf(task.copy(id = "context-fixture", prompt = "明天珠海的天气。",
            reply = "上一次没拿到明天的预报。要我继续查吗？", state = TaskState.COMPLETED)) else emptyList()
        val tools = mutableListOf<String>()
        val evidence = mutableListOf<JSONObject>()
        val answer = WatchWebLookup(context, observeTool = { name, arguments, output ->
            tools.add(name)
            val items = JSONObject(output).optJSONObject("evidence_pack")?.optJSONArray("items") ?: org.json.JSONArray()
            for (i in 0 until items.length()) evidence.add(items.getJSONObject(i))
            println("WATCH_GROUNDING tool=$name arguments=$arguments items=${items.length()}")
        }).answer(profile, task, history, WatchApiOperation())
        assertTrue("Expected real retrieval for $scenario", tools.isNotEmpty())
        if (scenario != "analysis") {
            val date = java.time.LocalDate.now(java.time.ZoneId.of("Asia/Shanghai")).plusDays(1).toString()
            assertTrue("Expected requested forecast date", evidence.any { it.toString().contains(date) })
            assertTrue("Expected actual weather values", answer.contains("°") || answer.contains("℃"))
        } else {
            val hosts = evidence.mapNotNull { runCatching { java.net.URI(it.optString("url")).host?.removePrefix("www.") }.getOrNull() }.toSet()
            assertTrue("Analysis should use independent sources", hosts.size >= 2)
            assertTrue("Expected source body retrieval", evidence.any { it.optString("evidence_level") == "retrieved_body" })
            assertTrue("Expected an evidence-based explanation", answer.length >= 120)
        }
        val completed = task.copy(state = TaskState.COMPLETED, reply = answer)
        repo.store.save(completed)
        repo.store.activeTask = completed.id
        println("WATCH_GROUNDING scenario=$scenario calls=${tools.size} answer=$answer")
        instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK).putExtra("task_id", completed.id))
        instrumentation.waitForIdleSync()
    }

    @Test fun inspectRecentConversation() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("history_diagnostic") == "true")
        val repo = (InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as WatchApplication).repository
        repo.store.tasks().take(12).reversed().forEach {
            println("WATCH_HISTORY " + JSONObject().put("id", it.id).put("prompt", it.prompt).put("reply", it.reply).put("state", it.state).toString())
        }
    }

    @Test fun realSendStaysInConversationAndReleasesScreenAfterSpeechGrace() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("send_screen_diagnostic") == "true")
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext.applicationContext as WatchApplication
        val repo = context.repository
        require(repo.store.apiProfile != null && repo.store.apiPreferred)
        val activity = instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        instrumentation.waitForIdleSync()
        fun descendants(view: android.view.View): List<android.view.View> = listOf(view) +
            if (view is android.view.ViewGroup) (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
        val oldIds = repo.store.tasks().map { it.id }.toSet()
        var completed: WatchTask? = null
        instrumentation.runOnMainSync {
            val ui = descendants(activity.window.decorView).filterIsInstance<WatchConversationView>().single()
            ui.input.setText("Reply with just OK.")
            descendants(ui).filterIsInstance<android.widget.ImageButton>().first {
                it.contentDescription == context.getString(R.string.send)
            }.performClick()
            assertTrue(activity.window.attributes.flags and android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON != 0)
        }
        val deadline = android.os.SystemClock.elapsedRealtime() + 190_000
        while (android.os.SystemClock.elapsedRealtime() < deadline) {
            completed = repo.store.tasks().firstOrNull { it.id !in oldIds && it.prompt == "Reply with just OK." }
            if (completed?.state?.terminal == true) break
            Thread.sleep(250)
        }
        assertEquals(TaskState.COMPLETED, completed?.state)
        val page = MainActivity::class.java.getDeclaredField("page").apply { isAccessible = true }
        val speech = MainActivity::class.java.getDeclaredField("speech").apply { isAccessible = true }
        val speechDeadline = android.os.SystemClock.elapsedRealtime() + 100_000
        var active = true
        while (active && android.os.SystemClock.elapsedRealtime() < speechDeadline) {
            instrumentation.runOnMainSync {
                assertEquals("home", page.get(activity))
                active = (speech.get(activity) as WatchReplySpeech).active
                assertTrue(activity.window.attributes.flags and android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON != 0)
            }
            if (active) Thread.sleep(250)
        }
        assertFalse("Speech should finish or report its network error", active)
        Thread.sleep(25_000)
        instrumentation.runOnMainSync {
            assertEquals("home", page.get(activity))
            assertTrue(activity.window.attributes.flags and android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON != 0)
        }
        Thread.sleep(6_000)
        instrumentation.runOnMainSync {
            assertEquals(0, activity.window.attributes.flags and android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        println("WATCH_SEND_SCREEN completed=true stayed_home=true grace_30_seconds=true")
    }

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
