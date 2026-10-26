package com.galaxyssi.chat

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class VoiceReminderDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test fun oldPersonalReminderSurvivesHundredsOfNewArticlesWithoutReadingTheirBodies() = isolated { app ->
        val repository = GlobalAgentRepository(app)
        val personal = message("personal", 1)
        val news = (1..200).map { message("attention-feed:$it", it + 10L).copy(newsArticleKey = "article-$it") }
        repository.saveProactiveMessages(news + personal)
        val snapshot = repository.voiceReminderPreview()
        assertEquals(listOf("global-agent:personal"), snapshot.first.map { it.key })
        assertEquals(200, snapshot.second)
        repository.markProactiveViewed(setOf("personal", "attention-feed:1"), 1000)
        assertTrue(repository.voiceReminderPreview().first.isEmpty())
        assertEquals(199, repository.voiceReminderPreview().second)
        assertEquals(201, repository.proactiveMessages().size)
    }

    @Test fun legacyReadIndexMigratesWithoutDiscardingStoredMessages() = isolated { app ->
        val db = AgentEncryptedDatabase(app, GlobalAgentRepository.DATABASE_NAME)
        db.indexedTransaction { sql ->
            sql.execSQL("CREATE TABLE proactive_message_read_index (id TEXT PRIMARY KEY NOT NULL, storage_key TEXT NOT NULL, " +
                "delivered INTEGER NOT NULL, created INTEGER NOT NULL, viewed INTEGER NOT NULL, digest TEXT NOT NULL)")
        }
        db.writeString("proactive_message_read_index_v3_article_bodies", "1")
        db.writeString("proactive_messages", """[{"id":"old-reminder","source_event_id":"old-event","source_conversation_id":"c",
            "target":"CURRENT_CONVERSATION","title":"Reminder","content":"Call the school","topic":"personal",
            "status":"DELIVERED","created_at_millis":1,"delivered_at_millis":2}]""")
        val repository = GlobalAgentRepository(app)
        assertEquals("Call the school", repository.voiceReminderPreview().first.single().content)
        assertEquals(1, repository.proactiveMessages().size)
        assertEquals(0, repository.voiceReminderPreview().second)
        assertFalse(db.contains("proactive_messages"))
    }

    @Test fun unavailableAndEmptySourcesHaveDifferentVisibleStatesAndNoFixedHeight() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            var reminders: AgentVoiceReminders? = null
            var snapshot = VoiceReminderSnapshot(emptyList(), mapOf("calendar" to "permission_not_granted"))
            try {
                scenario.onActivity { activity ->
                    reminders = AgentVoiceReminders(activity) { snapshot }
                    reminders!!.setActive(true)
                }
                waitUntil { reminders!!.scroll.visibility == View.VISIBLE }
                scenario.onActivity { activity ->
                    assertTrue(texts(reminders!!.scroll).contains(activity.getString(R.string.voice_reminder_empty)))
                    assertEquals(-1, reminders!!.scroll.layoutParams.height)
                    reminders!!.setActive(false)
                    assertTrue(texts(reminders!!.scroll).isEmpty())
                    snapshot = VoiceReminderSnapshot(emptyList(), mapOf("tasks" to "unavailable"))
                    reminders!!.setActive(true)
                }
                waitUntil { reminders!!.scroll.visibility == View.VISIBLE }
                scenario.onActivity { activity ->
                    assertTrue(texts(reminders!!.scroll).contains(activity.getString(R.string.voice_reminder_unavailable)))
                }
            } finally { scenario.onActivity { reminders?.setActive(false) } }
        }
    }

    @Test fun leavingDuringLoadCannotRepopulateHiddenReminderPlaintext() {
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val finished = CountDownLatch(1)
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            var reminders: AgentVoiceReminders? = null
            try {
                scenario.onActivity { activity ->
                    reminders = AgentVoiceReminders(activity) {
                        started.countDown(); release.await(10, TimeUnit.SECONDS)
                        finished.countDown()
                        VoiceReminderSnapshot(listOf(VoiceReminderItem("p", "personal", "Private", "Do not retain", 1)), emptyMap())
                    }
                    reminders!!.setActive(true)
                }
                assertTrue(started.await(10, TimeUnit.SECONDS))
                scenario.onActivity { reminders!!.setActive(false) }
                release.countDown()
                assertTrue(finished.await(10, TimeUnit.SECONDS))
                instrumentation.waitForIdleSync()
                scenario.onActivity {
                    assertEquals(View.GONE, reminders!!.scroll.visibility)
                    assertTrue(texts(reminders!!.scroll).isEmpty())
                }
            } finally { release.countDown(); scenario.onActivity { reminders?.setActive(false) } }
        }
    }

    @Test fun liveToolUsesTheSameTypedSourcesAsTheScreen() {
        val registry = AgentNativeToolRegistry().registerAll(AgentAppControlTools.definitions(AndroidAppControlPlatform(context)))
        val result = registry.invoke("galaxyssi.app.reminders", emptyMap())
        assertTrue(result.error?.code.orEmpty(), result.isSuccess)
        assertEquals(false, result.output["news_bodies_included"])
        val items = result.output["reminders"] as List<*>
        assertTrue(items.size <= 7)
        assertTrue(items.count { (it as Map<*, *>)["kind"] == "news" } <= 1)
        assertTrue(items.none { (it as Map<*, *>)["id"].toString().startsWith("global-agent:attention-feed:") })
        assertEquals("not_connected", (result.output["sources"] as Map<*, *>)["weather"])
    }

    private fun message(id: String, at: Long) = GlobalProactiveMessage(id = id, sourceEventId = "source:$id",
        sourceConversationId = "c", target = GlobalProactiveTarget.CURRENT_CONVERSATION, title = "Test reminder",
        content = "Private reminder or article body: $id", topic = "topic", urgent = false,
        status = GlobalProactiveMessageStatus.DELIVERED, createdAtMillis = at, deliveredAtMillis = at)

    private fun texts(view: View): List<String> = when (view) {
        is TextView -> listOf(view.text.toString())
        is ViewGroup -> (0 until view.childCount).flatMap { texts(view.getChildAt(it)) }
        else -> emptyList()
    }
    private fun waitUntil(condition: () -> Boolean) {
        val deadline = android.os.SystemClock.elapsedRealtime() + 10_000
        while (android.os.SystemClock.elapsedRealtime() < deadline) {
            var ready = false
            instrumentation.runOnMainSync { ready = condition() }
            if (ready) return
            Thread.sleep(25)
        }
        fail("Reminder view did not finish loading")
    }
    private fun isolated(block: (Context) -> Unit) {
        val app = IsolatedContext(context)
        try { block(app) } finally {
            AgentEncryptedDatabase(app, GlobalAgentRepository.DATABASE_NAME).clear()
            app.cleanup()
        }
    }
    private class IsolatedContext(base: Context) : ContextWrapper(base) {
        private val prefix = "voice-reminders-${UUID.randomUUID()}-"
        private val names = mutableSetOf<String>()
        private val preferences = mutableSetOf<String>()
        override fun getApplicationContext(): Context = this
        override fun getDatabasePath(name: String): File = if (File(name).isAbsolute) File(name) else {
            names.add(prefix + name); baseContext.getDatabasePath(prefix + name)
        }
        override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?): SQLiteDatabase =
            baseContext.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory)
        override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?, handler: DatabaseErrorHandler?): SQLiteDatabase =
            baseContext.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory, handler)
        override fun getSharedPreferences(name: String, mode: Int): SharedPreferences {
            preferences.add(prefix + name); return baseContext.getSharedPreferences(prefix + name, mode)
        }
        fun cleanup() { names.forEach(baseContext::deleteDatabase); preferences.forEach(baseContext::deleteSharedPreferences) }
    }
}
