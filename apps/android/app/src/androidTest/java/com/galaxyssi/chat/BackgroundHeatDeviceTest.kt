package com.galaxyssi.chat

import android.content.Context
import android.util.Log
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class BackgroundHeatDeviceTest {
    @Test fun migrateOneThousandEncryptedRecordsAndAppendWithoutRewritingHistory() = isolated { database ->
        val records = (1..1_000).map { record("fixture-$it", it.toLong()) }
        database.writeString(GlobalDeadLetterStore.LEGACY, JSONArray(records).toString())
        val store = GlobalDeadLetterStore(database)
        assertEquals(1_000, store.ids().size)
        assertFalse(database.contains(GlobalDeadLetterStore.LEGACY))
        val before = ciphertext(database, "fixture-500")
        val started = android.os.SystemClock.elapsedRealtime()
        repeat(12) { store.upsert(listOf(record("new-$it", 2_000L + it, 2))) }
        val elapsed = android.os.SystemClock.elapsedRealtime() - started
        assertEquals(before, ciphertext(database, "fixture-500"))
        assertEquals(1_000, GlobalDeadLetterStore(database).all().size)
        assertFalse(store.ids().contains("fixture-1"))
        assertTrue(store.ids().contains("new-11"))
        assertTrue(store.hasRecoveryCandidate(2))
        assertFalse(store.hasRecoveryCandidate(1))
        Log.i("GalaxySSIHeatTest", "dead_letters=1000 append_12_ms=$elapsed unchanged_payload=preserved")
    }

    @Test fun failedMigrationRollsBackAndRetainsLegacyData() = isolated { database ->
        val raw = JSONArray().put(record("valid", 1)).put(JSONObject().put("event", JSONObject())).toString()
        database.writeString(GlobalDeadLetterStore.LEGACY, raw)
        assertTrue(runCatching { GlobalDeadLetterStore(database).all() }.isFailure)
        assertEquals(raw, database.readString(GlobalDeadLetterStore.LEGACY, ""))
        assertTrue(database.keys(GlobalDeadLetterStore.PREFIX).isEmpty())
    }

    @Test fun replacementAndUpgradeEligibilitySurviveReopenAndClear() = isolated { database ->
        val store = GlobalDeadLetterStore(database)
        store.upsert(listOf(record("old", 1), record("attempted", 2).put("last_auto_recovery_version_code", 2)))
        assertTrue(store.hasRecoveryCandidate(2))
        store.replace(listOf(record("attempted", 2).put("last_auto_recovery_version_code", 2)))
        assertFalse(GlobalDeadLetterStore(database).hasRecoveryCandidate(2))
        assertEquals(setOf("attempted"), store.ids())
        database.clear()
        assertTrue(GlobalDeadLetterStore(database).all().isEmpty())
        store.upsert(listOf(record("fresh", 3, 3)))
        assertEquals(setOf("fresh"), store.ids())
    }

    @Test fun timersCannotExecuteCollectionOrLearningInline() {
        assertTrue(ProactiveAttentionFeedScheduler.buildRequest(1_000).workSpec.input
            .getBoolean(ProactiveAttentionFeedScheduler.TIMER_INPUT, false))
        assertFalse(ProactiveAttentionFeedScheduler.buildRequest(0).workSpec.input
            .getBoolean(ProactiveAttentionFeedScheduler.TIMER_INPUT, false))
        assertTrue(AndroidCognitionScheduler.buildRequest(AndroidCognitionWorkMode.ATTENTION, 15_000, true)
            .workSpec.input.getBoolean(AndroidCognitionScheduler.KEY_TIMER, false))
        assertFalse(AndroidCognitionScheduler.buildRequest(AndroidCognitionWorkMode.SCHEDULED, 0, false)
            .workSpec.input.getBoolean(AndroidCognitionScheduler.KEY_TIMER, false))
    }

    @Test fun emptyPublicationDoesNotEvenOpenStoresOrStartWork() {
        val context = object : android.content.ContextWrapper(ApplicationProvider.getApplicationContext()) {
            override fun getApplicationContext(): Context = error("Empty poll opened application stores")
        }
        ProactiveAttentionFeedDelivery.published(context, 0)
    }

    @Test fun inspectInstalledFailureReasonsWithoutRunningModels() {
        assumeTrue(InstrumentationRegistry.getArguments().getString("inspect_existing") == "true")
        val context = ApplicationProvider.getApplicationContext<Context>()
        val repository = GlobalAgentRepository(context)
        val letters = repository.deadLetters()
        Log.i("GalaxySSIHeatTest", "installed_dead_letters=${letters.size} pending=${repository.pendingEventCount()}")
        letters.groupBy { it.failure.reason }.entries.sortedByDescending { it.value.size }.take(5).forEach {
            Log.i("GalaxySSIHeatTest", "failure_count=${it.value.size} reason=${it.key.take(240)}")
        }
    }

    private fun ciphertext(database: AgentEncryptedDatabase, id: String): String = database.indexedTransaction { db ->
        db.rawQuery("SELECT encrypted_value FROM encrypted_values WHERE storage_key = ?",
            arrayOf(GlobalDeadLetterStore.PREFIX + id)).use { cursor ->
            check(cursor.moveToFirst()); cursor.getString(0)
        }
    }

    private fun record(id: String, time: Long, version: Int = 1) = JSONObject()
        .put("event", JSONObject().put("id", id).put("content", "Synthetic evidence ".repeat(200)))
        .put("quarantined_at_millis", time).put("quarantined_version_code", version)
        .put("last_auto_recovery_version_code", 0)

    private fun isolated(block: (AgentEncryptedDatabase) -> Unit) {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val name = "heat-fixture-${UUID.randomUUID()}"
        val database = AgentEncryptedDatabase(context, name)
        try { block(database) } finally { database.clear(); context.deleteDatabase("$name.db") }
    }
}
