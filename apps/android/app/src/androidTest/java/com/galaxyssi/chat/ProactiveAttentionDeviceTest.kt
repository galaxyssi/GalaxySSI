package com.galaxyssi.chat

import android.content.Context
import android.app.NotificationManager
import android.content.ContextWrapper
import android.content.Intent
import android.content.SharedPreferences
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.CheckBox
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.Assume.assumeTrue
import org.junit.runner.RunWith

/** Only isolated synthetic evidence; no provider calls, accounts, trades or existing research tasks. */
@RunWith(AndroidJUnit4::class)
class ProactiveAttentionDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()

    @Test fun configurationAndFavoritesSurviveRecreation() = isolated { context ->
        val store = ProactiveAttentionStore(context)
        assertEquals(31, store.preferences().topics.size)
        store.update { it.copy(configured = true, alertMode = AttentionAlertMode.SILENT, allowPairedModel = true,
            topics = it.topics.map { topic -> if (topic.id == "macro") topic.copy(title = "Edited scope", enabled = false) else topic },
            savedKeys = setOf("fixture")) }
        val restored = ProactiveAttentionStore(context).preferences()
        assertEquals(AttentionAlertMode.SILENT, restored.alertMode)
        assertEquals("Edited scope", restored.topics.first().title)
        assertFalse(restored.topics.first().enabled)
        assertTrue("fixture" in restored.savedKeys)
        assertTrue(restored.allowPairedModel)
        assertFalse(GlobalAgentRepository(context).settings().allowPairedAgentCognition)
    }

    @Test fun reconciliationIsIdempotentAndPauseResumeDoesNotMultiplyTasks() = isolated { context ->
        val store = ProactiveAttentionStore(context)
        val coordinator = ProactiveAttentionCoordinator(context)
        val repository = GlobalAgentRepository(context)
        store.update { it.copy(configured = true) }
        repeat(3) { coordinator.reconcile() }
        assertEquals(31, repository.researchTasks().size)
        assertTrue(repository.researchTasks().all { it.depth == GlobalResearchDepth.CONTINUOUS_MONITOR })
        store.update { it.copy(enabled = false) }
        coordinator.reconcile()
        assertTrue(repository.researchTasks().all { it.status == GlobalResearchTaskStatus.PAUSED })
        store.update { it.copy(enabled = true) }
        coordinator.reconcile()
        assertEquals(31, repository.researchTasks().size)
        assertTrue(repository.researchTasks().all { it.status == GlobalResearchTaskStatus.QUEUED })
    }

    @Test fun previousFinancialConfigurationUpgradesWithoutRestartingActiveResearch() = isolated { context ->
        val store = ProactiveAttentionStore(context)
        val repository = GlobalAgentRepository(context)
        store.update { it.copy(configured = true, alertMode = AttentionAlertMode.SILENT, allowPairedModel = true,
            topics = it.topics.take(15).map { topic -> if (topic.id == "rates") topic.copy(enabled = false) else topic },
            savedKeys = setOf("existing-finding")) }
        val macro = store.preferences().topics.first()
        val running = task("attention-research:macro").copy(topic = macro.title,
            question = ProactiveAttentionPolicy.researchQuestion(macro), status = GlobalResearchTaskStatus.RUNNING,
            sourceMessageId = 12345L, leaseExpiresAtMillis = Long.MAX_VALUE,
            preferredSources = ProactiveAttentionPolicy.preferredSources(macro.id))
        repository.upsertResearchTask(running)
        val persisted = repository.researchTasks().single()
        val coordinator = ProactiveAttentionCoordinator(context)
        repeat(3) { coordinator.reconcile() }
        val reopened = ProactiveAttentionStore(context).preferences()
        assertEquals(31, reopened.topics.size)
        assertEquals(16, reopened.topics.drop(15).count { it.enabled })
        assertFalse(reopened.topics.first { it.id == "rates" }.enabled)
        assertEquals(AttentionAlertMode.SILENT, reopened.alertMode)
        assertEquals(setOf("existing-finding"), reopened.savedKeys)
        assertTrue(reopened.allowPairedModel)
        assertEquals(30, repository.researchTasks().size)
        assertEquals(persisted, repository.researchTasks().first { it.id == running.id })
        val protein = repository.researchTasks().first { it.id == "attention-research:protein_life_sciences" }
        assertTrue(protein.question.contains("computational predictions and experimental validation"))
        assertTrue(protein.preferredSources.joinToString().contains("Original papers"))
    }

    @Test fun disabledTopicDoesNotKeepPendingNotificationsAndOtherTasksAreUntouched() = isolated { context ->
        val store = ProactiveAttentionStore(context)
        val repository = GlobalAgentRepository(context)
        store.update { it.copy(configured = true, topics = it.topics.map { topic -> topic.copy(enabled = topic.id != "macro") }) }
        repository.upsertResearchTask(task("unrelated"))
        repository.appendProactiveMessage(message())
        ProactiveAttentionCoordinator(context).reconcile()
        assertEquals(GlobalResearchTaskStatus.QUEUED, repository.researchTasks().first { it.id == "unrelated" }.status)
        assertEquals(GlobalProactiveMessageStatus.DISMISSED, repository.proactiveMessages().single().status)
        assertFalse(repository.researchTasks().any { it.id == "attention-research:macro" })
    }

    @Test fun sourcesRetainOriginalDatesAndNotificationModeIsIndependent() = isolated { context ->
        val store = ProactiveAttentionStore(context)
        store.update { it.copy(configured = true, alertMode = AttentionAlertMode.SILENT) }
        val task = task("attention-research:macro").copy(lastResultFingerprint = "test", updatedAtMillis = 5000,
            evidenceLedger = GlobalEvidenceLedger(sources = listOf(GlobalEvidenceSource(
                "https://example.org/synthetic", GlobalEvidenceSourceKind.OFFICIAL, 1.0, "Synthetic fixture",
                publishedAtMillis = 1000, retrievedAtMillis = 2000)), verified = true))
        store.saveEvidence(task, true)
        val source = ProactiveAttentionStore(context).evidence(ProactiveAttentionStore.eventId(task))!!
            .getJSONArray("sources").getJSONObject(0)
        assertEquals(1000L, source.getLong("published"))
        assertEquals(2000L, source.getLong("retrieved"))
        assertTrue(store.allows(message()))
        assertFalse(store.allowsNotification(message()))
        store.update { it.copy(alertMode = AttentionAlertMode.ALL) }
        assertTrue(store.allowsNotification(message()))
    }

    @Test fun viewedFindingRemainsSavedAfterStoreRecreation() = isolated { context ->
        val repository = GlobalAgentRepository(context)
        val finding = message().copy(status = GlobalProactiveMessageStatus.DELIVERED,
            deliveredConversationId = "test-destination", deliveredAtMillis = 1000)
        repository.appendProactiveMessage(finding)
        val item = GlobalProactiveInboxPolicy.project(repository.proactiveMessages(), emptyList()).single()
        ProactiveAttentionStore(context).update { it.copy(savedKeys = setOf(item.key)) }
        repository.markProactiveViewed(setOf(finding.id), 2000)
        val reopened = GlobalProactiveInboxPolicy.project(GlobalAgentRepository(context).proactiveMessages(), emptyList()).single()
        assertFalse(reopened.isNew)
        assertTrue(ProactiveAttentionPolicy.matches(reopened, AttentionFeedFilter.SAVED, ProactiveAttentionStore(context).preferences().savedKeys))
    }

    @Test fun settingsEntryShowsAllCategoriesAndReturnsFromDiscoveries() {
        val context = instrumentation.targetContext
        ActivityScenario.launch<ProactiveAttentionActivity>(Intent(context, ProactiveAttentionActivity::class.java)
            .putExtra("settings", true)).use { scenario ->
            await(scenario) { root -> views(root).filterIsInstance<CheckBox>().count() >= 31 }
            scenario.onActivity { activity ->
                val root = activity.window.decorView
                assertTrue(views(root).filterIsInstance<TextView>().any { it.text.toString() == activity.getString(R.string.attention_not_connected) })
                listOf("FINANCE", "TECHNOLOGY", "GALAXYSSI", "RESEARCH").forEach { group ->
                    assertTrue(views(root).any { it.tag == "attention-group:$group" })
                }
                assertEquals(31, activity.resources.getStringArray(R.array.attention_categories).size)
                assertEquals(31, activity.resources.getStringArray(R.array.attention_scopes).size)
                views(root).filterIsInstance<TextView>().first { it.text.toString() == activity.getString(R.string.attention_view) }
                    .parent.let { (it as View).parent as View }.performClick()
            }
            await(scenario) { root -> views(root).filterIsInstance<TextView>().any { it.text.toString() == context.getString(R.string.attention_saved) } }
            scenario.onActivity { it.onBackPressed() }
            await(scenario) { root -> views(root).filterIsInstance<CheckBox>().count() >= 31 }
            scenario.recreate()
            await(scenario) { root -> views(root).filterIsInstance<CheckBox>().count() >= 31 }
        }
    }

    @Test fun importantFindingUsesSystemHeadsUpChannel() {
        val context = instrumentation.targetContext
        val manager = context.getSystemService(NotificationManager::class.java)
        val id = 0x534103
        assumeTrue("System notifications are disabled", manager.areNotificationsEnabled())
        assumeTrue("Preserve an existing discovery notification", manager.activeNotifications.none { it.id == id })
        try {
            assertTrue(AndroidCognitionNotificationCenter.notify(context, GlobalAgentNotificationCandidate(
                title = "GalaxySSI \u6d4b\u8bd5\u63d0\u9192", content = "\u6d4b\u8bd5\u6570\u636e\uff0c\u4ec5\u9a8c\u8bc1\u91cd\u8981\u53d1\u73b0\u901a\u77e5\u3002",
                conversationId = "synthetic-attention-test", messageIds = emptySet(), attention = true, important = true)))
            SystemClock.sleep(800)
            val notification = manager.activeNotifications.single { it.id == id }.notification
            assertEquals(NotificationManager.IMPORTANCE_HIGH, manager.getNotificationChannel(notification.channelId).importance)
            assertNotNull(notification.contentIntent)
            assertNull(notification.fullScreenIntent)
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
                File(context.getExternalFilesDir(null), "attention-notification-test.png").outputStream().use {
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
                }
                bitmap.recycle()
            }
        } finally { manager.cancel(id) }
    }

    private fun await(scenario: ActivityScenario<ProactiveAttentionActivity>, predicate: (View) -> Boolean) {
        val deadline = SystemClock.uptimeMillis() + 15000
        while (SystemClock.uptimeMillis() < deadline) {
            var ready = false
            scenario.onActivity { ready = predicate(it.window.decorView) }
            if (ready) return
            SystemClock.sleep(100)
        }
        fail("Attention UI did not settle")
    }

    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()

    private fun task(id: String) = GlobalResearchTask(id = id, sourceEventId = "test", sourceConversationId = "test",
        topic = "Synthetic fixture", question = "No model execution", depth = GlobalResearchDepth.CONTINUOUS_MONITOR,
        preferredSources = emptyList())
    private fun message() = GlobalProactiveMessage(id = "test-finding", sourceEventId = "research:attention-research:macro:test",
        sourceConversationId = "test", target = GlobalProactiveTarget.NEW_CONVERSATION, title = "Synthetic fixture",
        content = "Test data, not financial news.", topic = "Macro", urgent = true)

    private fun isolated(block: (Context) -> Unit) {
        val context = IsolatedContext(instrumentation.targetContext)
        try { block(context) } finally {
            AgentEncryptedDatabase(context, GlobalAgentRepository.DATABASE_NAME).clear()
            context.cleanup()
        }
    }

    private class IsolatedContext(base: Context) : ContextWrapper(base) {
        private val prefix = "attention-test-${UUID.randomUUID()}-"
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
